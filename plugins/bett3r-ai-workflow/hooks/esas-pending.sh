#!/bin/sh
[ -f "${CLAUDE_PROJECT_DIR:-.}/.esas/ops.jsonl" ] || exit 0
#
# UserPromptSubmit — "esas: N pending (seq A→B)".
#
# Telemetry, never a trigger. When the user has edited the ESAS design board
# since Claude last synced, this puts the *count* in front of the next prompt
# so Claude knows its picture is stale. It never says what changed and never
# says what to do; the standing rule that Claude must not act on it unsolicited
# lives in skills/esas-pending/SKILL.md, not here.
#
# ## Why this file is written the way it is
#
# There is no per-directory matcher for hooks. This runs on **every prompt in
# every repo** where the plugin is enabled — including every fleet worktree,
# and every repo that has never heard of ESAS. Two consequences shape all of it:
#
#   * **Line 2 is the whole program, most of the time.** No `.esas/ops.jsonl`,
#     no work: one `test`, then gone. Everything below it is for the one
#     checkout in a session that is actually designing.
#
#   * **Exit 0 on every path, always.** Claude Code treats a UserPromptSubmit
#     hook's exit 2 as "block processing, erase original prompt". A hook that
#     throws would eat the user's typing. So: no `set -e`, no `set -u`, no
#     unguarded read, and no exit status but 0. A wrong count costs a sync; a
#     non-zero exit costs the prompt.
#
# Lock-free by contract. `.esas/ops.jsonl` is append-only and every reader of
# it — the board, esas-mcp, this — skips lines it cannot use rather than
# repairing them. Repairing here would make a reader into a writer, racing the
# lock holder it is supposed to stay out of the way of.
#
# ## The two numbers
#
# `.esas/.claude-cursor` is a cross-repo contract owned by @bett3r-dev/esas-store
# (see its `src/cursor.ts`, whose header is addressed to this script). It is
# pretty-printed JSON, so both fields are read **per line** — a one-line
# extractor written against a one-line illustration would fail here, and would
# be debugged in the wrong repository. Only two fields are contractual:
#
#   seq         the last op seq Claude has reconciled
#   byteOffset  the length of the feed prefix holding exactly the ops up to seq
#
# and the store guarantees `size( ops.jsonl ) > byteOffset` ⟺ the feed holds an
# op beyond `seq`. That is the cheap gate: one `wc -c`, one integer compare, no
# parse and no lock. It answers for ops of *any* class, so it is used as the
# fast-path exit and the semantic-human count happens behind it.
#
# ## Staleness — the rule this script must enforce
#
#   byteOffset > size( ops.jsonl )  ⇒  report EVERYTHING pending
#   seq        > lastSeq( feed )    ⇒  report EVERYTHING pending
#
# A cursor is a position in *one* feed, and the feed does not outlive the unit
# of work: `.esas/` is ephemeral and deleted after merge. A cursor left pointing
# into a feed that has since been deleted and restarted is not exotic — it is
# the default state at the start of every unit of work after the first, and it
# points far past a feed that begins again at seq 1. Without the rule the hook
# goes silent for the first `seq` ops of the new session, which is exactly when
# a human edit is pending.
#
# Both directions are checked *whenever the cheap gate lets anything through*.
# The offset rule catches a feed that shrank; the seq rule catches one that
# regrew **longer in bytes but shorter in ops**, which the offset alone reads as
# healthy. `lastSeq` is already computed by the count pass, so the second rule
# costs nothing. Note the deliberate hole: on `byteOffset == size` this exits
# before `lastSeq` is ever known, so the seq rule is not evaluated there. That
# is the fast path D5 asks for, and the state it skips — a regrown feed whose
# byte length lands *exactly* on the old offset — is one the two integers
# cannot distinguish from a synced cursor anyway.
#
# Everything unreadable degrades the same way: an absent, unparsable or
# malformed cursor reads as "nothing has been synced". That over-reports, which
# costs a sync; the opposite mistake costs a clobbered board edit.
#
# ## Numbers reach `test` only after being bounded
#
# `test` does not return false on an operand it cannot parse — it **fails**,
# with a diagnostic on stderr. Behind `&&` a failed test is indistinguishable
# from a false one, so a `byteOffset` of 2^63 made `[ "$size" -lt … ]` fail and
# the staleness branch silently not fire — going quiet in exactly the direction
# the rule exists to prevent, while printing to stderr in front of the user's
# prompt. Every value that reaches a numeric comparison therefore passes
# {@link valid_int} first, and the comparisons are `if` blocks rather than `&&`
# chains so a failure can never masquerade as a decision.

root=${CLAUDE_PROJECT_DIR:-.}
ops=$root/.esas/ops.jsonl
cursor=$root/.esas/.claude-cursor

# True for a string `test` can compare as an integer. The length bound is the
# whole point: `case` alone accepts any run of digits, and an operand past
# 2^63-1 makes every shell's `test` *fail* rather than compare. Eighteen digits
# is the widest value that is safe in all of them.
valid_int(){
  case $1 in ( '' | *[!0-9]* ) return 1 ;; esac
  [ ${#1} -le 18 ]
}

# The gate: the feed's size. `set --` splits off `wc`'s leading padding.
set -- $( wc -c 2>/dev/null <"$ops" )
size=${1:-0}
valid_int "$size" || size=0

# ── The shared scanner ───────────────────────────────────────────────────────
#
# One awk program, two callers. It walks a JSON object character by character,
# tracking string state and brace depth, and reports (a) the values of the
# top-level keys it cares about and (b) whether the object is *balanced* —
# whether every brace, bracket and quote that opened also closed.
#
# Both callers need exactly that pair, for the same reason: a document written
# by a process that died mid-write is a prefix, and a prefix's surviving fields
# are not evidence about the document.
#
#   * **The feed** needs top-level fields because `author` also appears *inside*
#     payloads — an ai op that resolves a human's comment carries
#     `"author":"human"` in its payload, and a substring match would file the
#     user's own edit count against a write Claude just made — and needs
#     balance because a torn last line is a writer killed mid-append, which
#     every other reader of this feed skips.
#
#   * **The cursor** needs balance because that is the closest this script can
#     get to the store's `JSON.parse`. See the note at the cursor read.
ESAS_SCAN='
function setfield( k, v ){
  if ( k == "seq" ) f_seq = v
  else if ( k == "class" ) f_class = v
  else if ( k == "author" ) f_author = v
  else if ( k == "byteOffset" ) f_offset = v
}
# Populates f_seq / f_class / f_author / f_offset from the top level of s.
# Returns 1 when s is a balanced object, 0 when it is a fragment.
function scan( s,   n, i, c, depth, instr, esc, key, start, j, closed ){
  f_seq = ""; f_class = ""; f_author = ""; f_offset = ""
  n = length( s ); depth = 0; instr = 0; esc = 0; key = ""; closed = 0
  for ( i = 1; i <= n; i++ ){
    c = substr( s, i, 1 )
    if ( instr ){
      if ( esc ){ esc = 0; continue }
      if ( c == "\\" ){ esc = 1; continue }
      if ( c != "\"" ) continue
      instr = 0
      if ( depth != 1 ) continue
      j = i + 1
      while ( j <= n && index( " \t", substr( s, j, 1 )) > 0 ) j++
      if ( substr( s, j, 1 ) == ":" ) key = substr( s, start, i - start )
      else if ( key != "" ){ setfield( key, substr( s, start, i - start )); key = "" }
      continue
    }
    if ( c == "\"" ){ instr = 1; start = i + 1; continue }
    if ( c == "{" || c == "[" ){ depth++; if ( depth > 1 ) key = ""; continue }
    if ( c == "}" || c == "]" ){
      depth--
      if ( depth < 0 ) return 0
      if ( depth == 0 ) closed = 1
      continue
    }
    if ( depth == 1 && key != "" && ( c == "-" || ( c >= "0" && c <= "9" ))){
      start = i
      while ( i <= n && index( "-+.eE0123456789", substr( s, i, 1 )) > 0 ) i++
      setfield( key, substr( s, start, i - start ))
      key = ""
      i--
      continue
    }
  }
  return ( closed && depth == 0 && !instr )
}
# The cursor is one document across several lines; the feed is one document per
# line. Joining with a space is safe in both directions because JSON strings
# cannot span lines, so no token is ever split or fused.
mode == "cursor" { doc = doc " " $0; next }
{
  line = $0
  sub( /[ \t\r]+$/, "", line )
  if ( line == "" ) next
  if ( !scan( line )) next
  if ( f_seq !~ /^[0-9]+$/ || length( f_seq ) > 18 ) next
  seq = f_seq + 0
  if ( seq > last ) last = seq
  if ( f_class != "semantic" || f_author != "human" ) next
  total++
  if ( seq > since ) above++
}
END {
  if ( mode == "cursor" ){
    if ( scan( doc ) && f_seq != "" && f_offset != "" ) printf "%s %s\n", f_seq, f_offset
    exit
  }
  printf "%d %d %d\n", above + 0, total + 0, last + 0
}'

# ── The bookmark ─────────────────────────────────────────────────────────────
#
# Read per field, because field order and whitespace are explicitly *not* part
# of the cursor contract — but accepted only if the document is **balanced**.
#
# The store's `readCursor` JSON-parses the file and then requires both contract
# fields; the two conditions are not the same, and the gap is not academic.
# `.claude-cursor` is written `{ seq, byteOffset, writerId, ts }` in that order,
# so a truncation landing anywhere in the `writerId`/`ts` tail leaves *both*
# contract fields syntactically perfect while the document is unparseable — the
# larger part of the window, not an edge of it. Scanning all 126 truncation
# points of a real cursor, a reader that checked only "both fields present"
# disagreed with the store at 94 of them, every time by claiming synced where
# the store says unsynced: the direction that costs a clobbered board edit.
#
# The balance check closes that window, because a prefix of a JSON object can
# never be balanced. What it does *not* do is validate JSON grammar — a
# balanced document with a trailing comma parses here and not in the store.
# That is a hand-edited file rather than a torn write.
cursor_seq=0
cursor_offset=0
if [ -f "$cursor" ]; then
  set -- $( awk -v mode=cursor "$ESAS_SCAN" 2>/dev/null <"$cursor" )
  cursor_seq=${1:-}
  cursor_offset=${2:-}
  # Both fields or neither: a cursor this reader cannot fully trust has synced
  # nothing. Negative reads the same way — it is not a position.
  if ! valid_int "$cursor_seq" || ! valid_int "$cursor_offset"; then
    cursor_seq=0
    cursor_offset=0
  fi
fi

# One integer compare, no parse. Equal means synced; smaller means the feed
# shrank under the bookmark, which is staleness, not silence. `if` rather than
# `&&`, so that a comparison which *fails* can never be mistaken for one that
# came out false.
if [ "$size" -eq "$cursor_offset" ]; then exit 0; fi
if [ "$size" -lt "$cursor_offset" ]; then cursor_seq=0; fi

# Behind the gate: count the pending **semantic human** ops, and find the
# feed's last seq. Both counts come out of the one pass — `above` for a cursor
# that turns out to be usable, `total` for one that turns out to be stale — so
# the seq-staleness rule needs no second read of the feed.
set -- $( awk -v mode=ops -v since="$cursor_seq" "$ESAS_SCAN" 2>/dev/null <"$ops" )
pending=${1:-0}
pending_total=${2:-0}
last_seq=${3:-0}
valid_int "$pending" || pending=0
valid_int "$pending_total" || pending_total=0
valid_int "$last_seq" || last_seq=0

# The second half of the staleness rule: a cursor past the end of the feed is
# a cursor into a feed that no longer exists.
if [ "$cursor_seq" -gt "$last_seq" ]; then
  cursor_seq=0
  pending=$pending_total
fi

[ "$pending" -gt 0 ] || exit 0

# Exactly one line, and only a count. `A→B` is "the cursor stands at A, the
# feed stands at B" — B is the same number the board's footer chip shows, so a
# broken link between the two screens is identifiable by inspection.
printf 'esas: %d pending (seq %d→%d)\n' "$pending" "$cursor_seq" "$last_seq"
exit 0
