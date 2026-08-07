#!/bin/sh
# Oracle for `/design` board-mode and the `esas-design` skill — plus the half of
# the `grill` skill that decides which forks a board is shown at all. That last
# one is deliberately not board-scoped: the decision-tree map `grill` opens with
# applies in every repo, board or no board. It is pinned here because it is the
# terminal half of a split whose other half lives on the canvas, and half a split
# is not worth guarding. See the note above its section.
#
# Both artifacts are text a model reads, so most of what they promise can only
# be reviewed. Two parts can be *executed*, and this suite executes them:
#
#   1. **The preflight.** `/design`'s board-mode detection is one fenced `sh`
#      block in commands/design.md, extracted here verbatim and run against
#      fixture host repos. The block under test is the block that ships — there
#      is no second copy to drift.
#   2. **The decision table.** Every `key: value` verdict the preflight can
#      print must have a row in the table below it. A verdict with no
#      documented response is a branch the model improvises, which is the
#      failure this whole slice exists to prevent.
#
# The rest is presence assertions on the load-bearing sentences — the restart
# step, the four D5 gestures, the tools that do *not* exist yet. Those catch
# deletion and drift, not wrongness; wrongness is a review.
#
# Run locally:  sh scripts/test-esas-design.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# PREFLIGHT_SH selects the interpreter the extracted block runs under. Claude
# Code hands a Bash tool call to bash, but the block is POSIX so it is asserted
# under dash too:
#     for s in sh dash bash; do PREFLIGHT_SH=$s sh scripts/test-esas-design.sh; done

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
COMMAND_MD="$PLUGIN/commands/design.md"
SKILL_MD="$PLUGIN/skills/esas-design/SKILL.md"
PENDING_MD="$PLUGIN/skills/esas-pending/SKILL.md"
GRILL_MD="$PLUGIN/skills/grill/SKILL.md"
FIXTURES="$ROOT/scripts/fixtures/esas-design"
STORE_FIXTURE="$ROOT/scripts/fixtures/esas-pending/pending/.esas"
PREFLIGHT_SH=${PREFLIGHT_SH:-sh}

# Canonicalised, because `$TMPDIR` ends in `/` on macOS and the doubled slash
# that produces is a spelling of a path no board would ever emit — an
# inequality invented by this suite is not one worth asserting.
TMP=$( mktemp -d "${TMPDIR:-/tmp}/esas-design-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -- "$TMP" && pwd ) || exit 1
BOARD_PID=''
cleanup(){ [ -n "$BOARD_PID" ] && kill "$BOARD_PID" 2>/dev/null; rm -rf "$TMP"; }
trap 'cleanup' EXIT INT TERM

passed=0
failed=0

fail(){
  failed=$(( failed + 1 ))
  printf '  \033[31m✗\033[0m %s\n' "$1"
  shift
  for line in "$@"; do printf '      %s\n' "$line"; done
}

pass(){
  passed=$(( passed + 1 ))
  printf '  \033[32m✓\033[0m %s\n' "$1"
}

# ── The preflight, extracted from the command that ships it ───────────────────
#
# Sentinel comments rather than "the first ```sh block", so re-ordering the
# document cannot silently point this suite at different code.

PREFLIGHT="$TMP/preflight.sh"

printf '\npreflight extraction\n'

if [ ! -f "$COMMAND_MD" ]; then
  fail 'commands/design.md exists' "no file at $COMMAND_MD"
else
  awk '/^# --- esas preflight ---/{on=1} on{print} /^# --- end esas preflight ---/{on=0}' \
    "$COMMAND_MD" >"$PREFLIGHT"
  if [ ! -s "$PREFLIGHT" ]; then
    fail 'the preflight block is delimited by its sentinels in commands/design.md' \
      'expected a block between `# --- esas preflight ---` and `# --- end esas preflight ---`'
  elif ! grep -q '^# --- end esas preflight ---' "$PREFLIGHT"; then
    fail 'the preflight block is closed by its end sentinel' 'opening sentinel found, closing one missing'
  elif ! "$PREFLIGHT_SH" -n "$PREFLIGHT" 2>"$TMP/err"; then
    fail 'the shipped preflight block parses as POSIX sh' "$( cat "$TMP/err" )"
  else
    pass 'the preflight block extracts from commands/design.md and parses'
  fi
fi

# Runs the extracted preflight inside a fresh copy of a fixture repo.
# ESAS_BOARD_PORT points the board probe at whatever this suite is (or is not)
# serving, so no assertion depends on what happens to hold :3727 right now.
run_preflight(){
  work="$TMP/work"
  rm -rf "$work"
  mkdir -p "$work"
  cp -R "$FIXTURES/$1/." "$work/"
  ( cd "$work" && ESAS_BOARD_PORT="${2:-1}" "$PREFLIGHT_SH" "$PREFLIGHT" ) >"$TMP/out" 2>"$TMP/err"
  status=$?
}

# assert_report <fixture> <description> <expected-report>
# The report is compared whole: a line the preflight stops printing is as much
# a regression as a wrong one.
assert_report(){
  fixture=$1
  description=$2
  expected=$3
  port=${4:-1}

  run_preflight "$fixture" "$port"
  actual=$( cat "$TMP/out" )
  stderr=$( cat "$TMP/err" )

  if [ "$status" -ne 0 ]; then
    fail "$description" "exit status $status" "stderr: $stderr"
  elif [ -n "$stderr" ]; then
    fail "$description" "wrote to stderr — a preflight the user watches must be quiet" "stderr: $stderr"
  elif [ "$actual" != "$expected" ]; then
    fail "$description" "expected:" "$expected" "actual:" "$actual"
  else
    pass "$description"
  fi
}

printf '\nboard-mode detection (dry-run in fixture host repos)\n'

# No `.esas` is the fleet worktree and every repo that has never designed. The
# report stops at the first line on purpose: nothing below it can matter, and a
# command that keeps probing teaches the model that board mode is negotiable.
assert_report 'no-esas' \
  'a repo with no .esas/: board mode off, and the report stops there' \
  'esas_dir: absent'

assert_report 'no-graph' \
  '.esas/ without graph.json: the extractor has not run here' \
  'esas_dir: present
graph: absent
design: absent
ops: absent
mcp: registered
board: off'

assert_report 'board-ready' \
  'extracted + registered + no design layer yet: the clean board-mode start' \
  'esas_dir: present
graph: present
design: absent
ops: absent
mcp: registered
board: off'

assert_report 'unregistered' \
  'a .mcp.json without the esas entry reads as unregistered, not as absent' \
  'esas_dir: present
graph: present
design: absent
ops: absent
mcp: unregistered
board: off'

assert_report 'no-mcp-json' \
  'no .mcp.json at all is its own verdict — the entry has to create the file' \
  'esas_dir: present
graph: present
design: absent
ops: absent
mcp: absent
board: off'

# A design layer already on disk. The bytes are real store output, borrowed
# from the esas-pending fixtures rather than copied, so "present" here means
# what the store actually writes.
work_in_session="$TMP/in-session"
rm -rf "$work_in_session"
mkdir -p "$work_in_session"
cp -R "$FIXTURES/board-ready/." "$work_in_session/"
cp "$STORE_FIXTURE/design.json" "$STORE_FIXTURE/ops.jsonl" "$STORE_FIXTURE/.claude-cursor" \
  "$work_in_session/.esas/" 2>/dev/null
out=$( cd "$work_in_session" && ESAS_BOARD_PORT=1 "$PREFLIGHT_SH" "$PREFLIGHT" 2>"$TMP/err" )
expected='esas_dir: present
graph: present
design: present
ops: present
mcp: registered
board: off'
if [ "$out" != "$expected" ]; then
  fail 'a design.json + ops.jsonl already on disk are reported, not assumed fresh' \
    'expected:' "$expected" 'actual:' "$out"
elif [ -s "$TMP/err" ]; then
  fail 'a design layer already on disk is reported quietly' "stderr: $( cat "$TMP/err" )"
else
  pass 'a design.json + ops.jsonl already on disk are reported, not assumed fresh'
fi

# ── The board probe ───────────────────────────────────────────────────────────
#
# `/api/esas/status` is served by the real board on :3727; here it is a stub on
# an ephemeral port, because the assertion is about how the preflight *reads*
# the answer, not about vite.

printf '\nthe board probe (GET /api/esas/status)\n'

# $1 = the repoPath to answer with, $2 = 'pretty' to space the JSON out.
# The default separators match the board's `JSON.stringify(status)` byte for
# byte — a stub that merely looks like the real answer is how a reader passes
# its own tests and fails against the thing it reads.
start_stub_board(){
  rm -f "$TMP/port"
  python3 -c '
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
separators = (", ", ": ") if len(sys.argv) > 2 and sys.argv[2] == "pretty" else (",", ":")
body = json.dumps({"repoPath": sys.argv[1], "gitSha": "deadbee", "lastSeq": 7},
                  separators=separators).encode()
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/esas/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a):
        pass
srv = HTTPServer(("127.0.0.1", 0), H)
sys.stdout.write("%d\n" % srv.server_port)
sys.stdout.flush()
srv.serve_forever()
' "$1" "${2:-compact}" >"$TMP/port" 2>/dev/null &
  BOARD_PID=$!
  i=0
  while [ ! -s "$TMP/port" ] && [ "$i" -lt 100 ]; do
    i=$(( i + 1 ))
    sleep 0.05 2>/dev/null || sleep 1
  done
  BOARD_PORT=$( tr -d ' \n' <"$TMP/port" 2>/dev/null )
}

stop_stub_board(){
  [ -n "$BOARD_PID" ] && kill "$BOARD_PID" 2>/dev/null
  wait "$BOARD_PID" 2>/dev/null
  BOARD_PID=''
}

if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  fail 'the board probe cases need python3 and curl' 'one of them is missing on this machine'
else
  # Serving *this* checkout: the second screen is the one the session writes to.
  start_stub_board "$TMP/work"
  if [ -z "$BOARD_PORT" ]; then
    fail 'a stub board comes up' 'the stub never printed a port'
  else
    assert_report 'board-ready' \
      'a board serving this checkout reports `serving` plus the status body' \
      'esas_dir: present
graph: present
design: absent
ops: absent
mcp: registered
board: serving
  status: {"repoPath":"'"$TMP/work"'","gitSha":"deadbee","lastSeq":7}' \
      "$BOARD_PORT"
  fi
  stop_stub_board

  # Same repo, spaced JSON. Which checkout the board serves is not a question
  # about how it serialises the answer, and a false `other-repo` would send the
  # user hunting for a rival board that does not exist.
  start_stub_board "$TMP/work" pretty
  if [ -z "$BOARD_PORT" ]; then
    fail 'a pretty-printing stub board comes up' 'the stub never printed a port'
  else
    assert_report 'board-ready' \
      'a spaced status body from this checkout is still `serving`' \
      'esas_dir: present
graph: present
design: absent
ops: absent
mcp: registered
board: serving
  status: {"repoPath": "'"$TMP/work"'", "gitSha": "deadbee", "lastSeq": 7}' \
      "$BOARD_PORT"
  fi
  stop_stub_board

  # A board on the port, serving somebody else — worse than no board, because
  # the user is watching a screen this session will never move.
  start_stub_board "/somewhere/else"
  if [ -z "$BOARD_PORT" ]; then
    fail 'a stub board serving another repo comes up' 'the stub never printed a port'
  else
    assert_report 'board-ready' \
      'a board serving a different checkout is `other-repo`, never `serving`' \
      'esas_dir: present
graph: present
design: absent
ops: absent
mcp: registered
board: other-repo
  status: {"repoPath":"/somewhere/else","gitSha":"deadbee","lastSeq":7}' \
      "$BOARD_PORT"
  fi
  stop_stub_board

  # Reached through a symlink: node's `process.cwd()` is the physical path, so
  # that is what a board launched in the checkout reports, while the shell that
  # walked in through the link keeps the logical one. Same directory, two
  # spellings, and only one of them is `$PWD`.
  physical_work=$( CDPATH= cd -- "$TMP/work" && pwd -P )
  start_stub_board "$physical_work"
  link="$TMP/link"
  rm -f "$link"
  if [ -z "$BOARD_PORT" ]; then
    fail 'a stub board comes up for the symlink case' 'the stub never printed a port'
  elif ! ln -s "$TMP/work" "$link" 2>/dev/null; then
    fail 'a symlinked checkout can be set up' 'ln -s failed'
  else
    rm -rf "$TMP/work"; mkdir -p "$TMP/work"
    cp -R "$FIXTURES/board-ready/." "$TMP/work/"
    out=$( cd "$link" && ESAS_BOARD_PORT="$BOARD_PORT" "$PREFLIGHT_SH" "$PREFLIGHT" 2>"$TMP/err" )
    case $out in
      *'board: serving'*) pass 'a checkout reached through a symlink is still `serving`' ;;
      *) fail 'a checkout reached through a symlink is still `serving`' "actual: [$out]" ;;
    esac
  fi
  stop_stub_board

  # Nothing listening: the launch is user-owned, so this is the normal state
  # before the user runs the board — an answer, not a failure.
  start_stub_board "$TMP/work"
  dead_port=$BOARD_PORT
  stop_stub_board
  if [ -n "$dead_port" ]; then
    assert_report 'board-ready' \
      'nothing listening reads as `board: off` — not an error, the board is user-launched' \
      'esas_dir: present
graph: present
design: absent
ops: absent
mcp: registered
board: off' \
      "$dead_port"
  fi
fi

# Without curl the board cannot be probed at all. The preflight must say so
# rather than report `off`, which would send the model to tell the user to
# launch a board that may already be running.
work="$TMP/work"
rm -rf "$work"; mkdir -p "$work"
cp -R "$FIXTURES/board-ready/." "$work/"
preflight_sh_abs=$( command -v "$PREFLIGHT_SH" )
out=$( cd "$work" && env -i PATH=/nonexistent PWD="$work" "$preflight_sh_abs" "$PREFLIGHT" 2>"$TMP/err" )
if [ -s "$TMP/err" ]; then
  fail 'a stripped PATH degrades quietly' "stderr: $( cat "$TMP/err" )"
else
  case $out in
    *'board: unknown'*) pass 'without curl the board is `unknown`, never assumed off' ;;
    *) fail 'without curl the board is `unknown`, never assumed off' "actual: [$out]" ;;
  esac
fi

# ── The ambient-shell contract ────────────────────────────────────────────────
#
# Every case above runs the block as a *child script*, where an `exit` is free
# and a leaked variable dies with the process. Production is the opposite: the
# model pastes this into a Bash tool call, which is a shell that outlives the
# command and holds the caller's state. So the property the block claims —
# ends nothing, renames nothing — is asserted the way it ships, dot-sourced,
# and statically on the text besides.

printf '\nthe ambient-shell contract\n'

# Comments are stripped first: the block *documents* having no `exit`, and a
# check that reads its own documentation as a violation is worse than none.
sed 's/[[:space:]]*#.*$//' "$PREFLIGHT" >"$TMP/code.sh"

if grep -qE '(^|[^_[:alnum:]])exit([^_[:alnum:]]|$)' "$TMP/code.sh"; then
  fail 'the block never exits — it runs in a shell it does not own' \
    "$( grep -nE '(^|[^_[:alnum:]])exit([^_[:alnum:]]|$)' "$TMP/code.sh" )"
else
  pass 'the block never exits — it runs in a shell it does not own'
fi

# `echo` is refuted for a different reason: the decision-table coverage check
# reads `printf` literals, so a verdict printed with `echo` would be the one
# way to add a branch nothing documents and still go green.
if grep -qE '(^|[^_[:alnum:]])echo([^_[:alnum:]]|$)' "$TMP/code.sh"; then
  fail 'verdicts are printed with printf, never echo (coverage reads printf)' \
    "$( grep -nE '(^|[^_[:alnum:]])echo([^_[:alnum:]]|$)' "$TMP/code.sh" )"
else
  pass 'verdicts are printed with printf, never echo (coverage reads printf)'
fi

# Every name the block binds must be `esas_`-prefixed. `IFS=` is the one
# exception and is not one in fact: it prefixes `read`, a regular builtin, so
# POSIX does not persist it — asserted below rather than argued.
stray=$(
  { grep -oE '(^|[[:space:]]|;)[A-Za-z_][A-Za-z0-9_]*=' "$TMP/code.sh" | tr -d ' ;='
    grep -oE '(^|[[:space:]])for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$TMP/code.sh" | awk '{print $NF}'
  } | sort -u | grep -v '^esas_' | grep -v '^IFS$'
)
if [ -n "$stray" ]; then
  fail 'every variable the block binds is esas_-prefixed' "unprefixed: $( printf '%s' "$stray" | tr '\n' ' ' )"
else
  pass 'every variable the block binds is esas_-prefixed'
fi

# The dot-sourced run: same shell, caller's variables in scope. An `exit`
# anywhere in the block and `survived` never prints — which is the half of this
# no static check can make.
#
# The names planted are the ones this block used *before* it was namespaced
# (`port`, `body`, `serving`, …) — the collisions a caller would actually
# suffer. `esas_*` names are excluded on purpose: the contract is that the
# block leaves only those behind, not that it binds nothing.
work="$TMP/work"
rm -rf "$work"; mkdir -p "$work"
cp -R "$FIXTURES/board-ready/." "$work/"
cat >"$TMP/ambient.sh" <<AMBIENT
cd "$work" || exit 1
esas_ifs_before=\$IFS
for esas_name in port body serving registered line path here spaced; do
  eval "\$esas_name=CALLER"
done
ESAS_BOARD_PORT=1
. "$PREFLIGHT"
printf 'survived\n'
[ "\$IFS" = "\$esas_ifs_before" ] && printf 'ifs-intact\n'
for esas_name in port body serving registered line path here spaced; do
  eval "esas_value=\\\$\$esas_name"
  [ "\$esas_value" = CALLER ] || printf 'clobbered:%s\n' "\$esas_name"
done
AMBIENT
ambient=$( "$PREFLIGHT_SH" "$TMP/ambient.sh" 2>"$TMP/err" )
case $ambient in
  *clobbered:*)
    fail 'dot-sourced, it leaves the caller'"'"'s variables alone' \
      "$( printf '%s\n' "$ambient" | grep clobbered: | tr '\n' ' ' )" ;;
  *survived*)
    if [ -s "$TMP/err" ]; then
      fail 'dot-sourced, it degrades quietly' "stderr: $( cat "$TMP/err" )"
    else
      case $ambient in
        *ifs-intact*) pass 'dot-sourced in a live shell: survives, and clobbers nothing' ;;
        *) fail 'dot-sourced, it restores IFS' 'IFS differed after the block ran' ;;
      esac
    fi ;;
  *)
    fail 'dot-sourced in a live shell: survives, and clobbers nothing' \
      'the sourcing shell did not reach the next statement — the block exits' \
      "output: [$ambient]" ;;
esac

# ── Every verdict has a documented response ───────────────────────────────────
#
# The assertion that keeps the two halves of board mode married: the preflight
# prints facts, the table below it decides. A verdict the table does not
# mention is a branch the model has to invent on the spot.

printf '\ndecision-table coverage\n'

if [ ! -s "$PREFLIGHT" ]; then
  fail 'every verdict the preflight can print has a row in the decision table' \
    'no preflight to read verdicts from'
else
  # Several verdicts share a line (`if ... then printf ...; else printf ...; fi`),
  # so this matches per occurrence, not per line. Getting that wrong is how the
  # first draft of this check silently covered 2 of 15.
  grep -o "printf '[a-z_]*: [a-z-]*" "$PREFLIGHT" | sed "s/^printf '//" | sort -u >"$TMP/verdicts"
  found=$( wc -l <"$TMP/verdicts" | tr -d ' ' )
  table=$( awk '/^# --- esas preflight ---/{on=1} /^# --- end esas preflight ---/{on=0;next} !on{print}' "$COMMAND_MD" )
  missing=''
  while IFS= read -r literal; do
    [ -n "$literal" ] || continue
    case $table in
      *"\`$literal\`"*) ;;
      *) missing="$missing [$literal]" ;;
    esac
  done <"$TMP/verdicts"
  if [ "$found" -lt 10 ]; then
    fail 'the preflight prints its verdicts as `printf` literals this check can read' \
      "only $found found — has the printf shape changed?"
  elif [ -n "$missing" ]; then
    fail 'every verdict the preflight can print has a row in the decision table' \
      "undocumented:$missing"
  else
    pass "every verdict the preflight can print has a row in the decision table ($found of them)"
  fi
fi

# ── The command text ──────────────────────────────────────────────────────────

printf '\ncommands/design.md — board mode\n'

# Failures name the file repo-relative, not by basename: two of the three files
# pinned here are called `SKILL.md`, so a bare basename would report the needle
# as missing from a file it was never asserted against.
assert_md(){
  file=$1
  description=$2
  needle=$3
  if [ ! -f "$file" ]; then
    fail "$description" "no file at $file"
  elif grep -qF -- "$needle" "$file"; then
    pass "$description"
  else
    fail "$description" "not found in ${file#"$ROOT"/}: $needle"
  fi
}

refute_md(){
  file=$1
  description=$2
  needle=$3
  if [ ! -f "$file" ]; then
    fail "$description" "no file at $file"
  elif grep -qF -- "$needle" "$file"; then
    fail "$description" "found in ${file#"$ROOT"/}, and should not be: $needle"
  else
    pass "$description"
  fi
}

# Registration only takes effect at session start, so the one thing this
# command must never do is write the entry and carry on as though it worked.
assert_md "$COMMAND_MD" 'it names the restart as its own step' 'RESTART REQUIRED'
assert_md "$COMMAND_MD" 'it stops the command after writing the entry' \
  'Registration takes effect only at session start'
assert_md "$COMMAND_MD" 'it forbids calling the esas tools in the session that registered them' \
  'Do not call any `mcp__esas__*` tool for the rest of this session'
assert_md "$COMMAND_MD" 'it says what happens when the user does not restart' \
  'If the user does not restart'
assert_md "$COMMAND_MD" 'the .mcp.json edit merges rather than replaces' \
  'Add the one key to `mcpServers`'

# The board is a projection. Its absence costs a second screen, not the design.
assert_md "$COMMAND_MD" 'a board that is not running does not block the command' \
  'Never block the design on the board'
assert_md "$COMMAND_MD" 'it hands the user the launch line their repo uses' 'yarn esas:board'
assert_md "$COMMAND_MD" 'it names the port the board claims strictly' '3727'
assert_md "$COMMAND_MD" 'it names the endpoint that identifies a board' '/api/esas/status'

# design.json is the store's file. A hand-written one bypasses the lock, the
# ops feed and validation, and renders as a design nothing attributed.
#
# Two needles, because the rule is stated twice for two different readers and
# only one of them was pinned: the `Never create or edit …` phrasing lives in
# *Seeding*, so it kept matching after the registration-path rule beside it was
# deleted — the exact rule that stops a model with no server from writing the
# file itself.
assert_md "$COMMAND_MD" 'it forbids hand-writing the design file' \
  'Never create or edit `.esas/design.json` by hand'
assert_md "$COMMAND_MD" 'a session with no server is told not to do the store'"'"'s job itself' \
  'Never substitute for the missing server'
assert_md "$COMMAND_MD" 'it says the first write is what seeds the file' \
  'The first `propose` seeds it'
assert_md "$COMMAND_MD" 'it treats a pre-existing design layer as a question, not a given' \
  'whose session it is'
assert_md "$COMMAND_MD" 'both surfaces feed /plan' '`design.json` (structure)'

# ── The relevance gate ────────────────────────────────────────────────────────
#
# Board mode has two gates and they answer different questions. The *capability*
# gate is the preflight above — is a board possible in this checkout. The
# *relevance* gate is a judgement on the drafted decision tree — is a board
# warranted by this design. Both must say yes, and they are pinned apart because
# collapsing them is the regression: with one gate, every design run in a repo
# that happens to have a `.esas/` opens with board talk, including the ones with
# no structure in them at all.
#
# Nothing below is derived from a preflight key, deliberately — a shell block
# cannot read a decision tree, and a key would have to be printed before there
# was anything to answer about. The coverage check above is the guard on that: if
# this gate ever grows a `key: value`, that check fails, and the fix is to take
# the key back out rather than to document it.

printf '\ncommands/design.md — the relevance gate\n'

assert_md "$COMMAND_MD" 'the gate is derived from the tree, not from a flag or a work kind' \
  'armed by what the drafted decision tree names'
assert_md "$COMMAND_MD" 'it names the artifact kinds that arm it' \
  'a command, an event, an aggregate, a policy, a read model, or a coupling'
assert_md "$COMMAND_MD" 'relevance and capability are kept apart, in those words' \
  'Capability asks whether a board is possible; relevance asks whether it is warranted'
assert_md "$COMMAND_MD" 'the gate is answered before the preflight runs, never after' \
  'Relevance runs before the preflight'
assert_md "$COMMAND_MD" 'on a no there is no board output at all — not a quieter one' \
  'say nothing at all about boards'
assert_md "$COMMAND_MD" 'a design that turns structural late is not locked out by its opening' \
  'arm mid-interview at the first artifact-touching fork'

# Pinned on its own, and the load-bearing pin of this section: the gate asks for
# a judgement, and no suite here can tell a right call from a wrong one (design
# risk 4). The gate is accepted *only* because it fails safe, and it fails safe
# only while the text says which way it falls — so this needle is the whole
# mitigation, not a nicety. It is also the first sentence a well-meaning edit
# smooths away, because beside six rules that read like rules it reads like a
# hedge.
assert_md "$COMMAND_MD" 'unsure falls towards silence, stated as a rule' \
  'unsure means silent'

# Putting the gate ahead of the preflight falsified a sentence in the restart
# copy further down, so the correction is pinned here, beside its cause, rather
# than up with the other restart pins. It was true while the preflight ran first:
# the stop landed before anything had been read or asked, so nothing *had* been
# spent. Ordered behind the decision tree it is false — the grounding pass is
# gone, and under the mid-interview fallback so are the forks the user already
# answered. Refute plus assert, the same shape used on any corrected claim here:
# an unpinned correction is one a later editor restores in good faith, because
# the old sentence is shorter and reads kinder.
refute_md "$COMMAND_MD" 'the restart copy no longer claims the stop costs nothing' \
  'Nothing is lost'
assert_md "$COMMAND_MD" 'it names what the restart actually costs the user' \
  'the grounding pass, and any forks already answered'

# ── The launch offer ──────────────────────────────────────────────────────────
#
# The board is offered at the one moment it is worth looking at — when the first
# batch of questions is ready to post — and started only on a yes. Both halves
# are pinned, because this regresses in two opposite directions: moved back to
# the preflight it offers a board before the design has shown it needs one, and
# turned into an unasked spawn it takes a screen the user never asked for. The
# cost of either is the same and it is not paid here: `:3727` is claimed
# strictly, so an unwanted board squats the one port and the *next* repo's board
# is the one that will not come up.
#
# The reason this command used to give for not spawning — "a board started from a
# tool call dies with it" — is false. A `run_in_background` launch outlives the
# turn that armed it, demonstrated twice: the design's own spike, and again while
# verifying the summon watcher, where a detached watch outlived its turn and
# re-invoked an idle session. So it is deleted rather than softened, and the
# refute is what makes that stick — a rule kept alive by a reason known to be
# wrong is worse than no rule, because the next reader cannot tell which half to
# trust. Refute plus assert on the reason that replaces it, the same shape the
# restart correction above uses.

printf '\ncommands/design.md — the launch offer\n'

refute_md "$COMMAND_MD" 'the falsified reason for not spawning is gone, not softened' \
  'a board started from a tool call dies with it'
assert_md "$COMMAND_MD" 'the offer lands when there is something to look at, not at the preflight' \
  'the first batch of questions is ready to post'
assert_md "$COMMAND_MD" 'the launch is offered and waits for a yes — never taken unasked' \
  'never spawn it unasked'
assert_md "$COMMAND_MD" 'the reason that replaced the falsified one is the port, not the process tree' \
  'squats :3727'

# Already pinned on the skill below, as one of the four cross-repo contracts.
# Pinned again here for a different reason: the offer is the moment the user is
# handed a URL, and an offer that hands them the bare board sends them to a
# canvas with their questions somewhere on it.
assert_md "$COMMAND_MD" 'the offer carries the link to the open questions, not to the whole canvas' \
  '?openComments=1&author=ai'

# `repoPath` is already in this file twice — the `status` tool's return shape and
# the endpoint's — so the field name alone would pass without the row saying
# anything. The needles carry the row's own words instead.
assert_md "$COMMAND_MD" 'the other-repo verdict names which repo holds the port' \
  'Name the repo that holds it'
assert_md "$COMMAND_MD" 'and says where that name is read from' \
  'the `repoPath` in the `status:` line'

printf '\nskills/esas-design — the D5 gestures\n'

# The frontmatter description is the only part of a skill that is resident
# without the file being opened, so the rules that fire on an utterance the
# model was not expecting have to live there.
if [ ! -f "$SKILL_MD" ]; then
  fail 'the esas-design skill exists' "no file at $SKILL_MD"
else
  pass 'the esas-design skill exists'
  description=$( awk 'NR>1 && /^---/{exit} NR>1{print}' "$SKILL_MD" | sed -n '/^description:/,$p' )
  assert_in_description(){
    if printf '%s' "$description" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "not in the frontmatter description: $2"; fi
  }
  assert_in_description 'the sync trigger is resident in the frontmatter' 'look at the board'
  assert_in_description 'so is the order the gesture runs in' 'read_changes'
  assert_in_description 'so is mark_synced, which is the half that gets dropped' 'mark_synced'
  assert_in_description 'so is the do-not-assert rule (the slice gate)' 'sync first'
  assert_in_description 'so is the whole-batch retry after a refused write' 'CONFLICT_PENDING_SYNC'
fi

# The withdrawal gesture. Pinned needle by needle because the failure it exists
# to prevent was not "the model did not know how to delete" — it was the model
# knowing, being refused, and encoding the retraction in the sticky's own label
# instead of saying so. So the anti-pattern is asserted as literally as the
# gesture: a skill that describes `remove` and omits "do not rename it
# RETRACTED" has not covered this.
assert_md "$SKILL_MD" 'the body carries the withdrawal gesture' 'Scrap that, I was wrong'
assert_md "$SKILL_MD" 'it says a proposal-only element is withdrawn, not flagged removed' 'withdrawn'
assert_md "$SKILL_MD" 'it names the label workaround as the thing not to do' 'RETRACTED'
assert_md "$SKILL_MD" 'it warns the comment thread dies with the withdrawn proposal' 'The thread goes with it'
assert_md "$SKILL_MD" 'it warns a withdrawal is not undo-able from the board' 'not undo-able'
assert_md "$SKILL_MD" 'it separates withdrawing from reclassifying' 'this was never right'
assert_md "$SKILL_MD" 'a stuck refusal is reported, never routed around with another verb' \
  'never a reason to reach for a *different* verb'

assert_md "$SKILL_MD" 'the body carries the reclassify gesture' 'that rename is a correction'
assert_md "$SKILL_MD" 'it warns that a reclassify dirties a git-tracked file' '.esas.overrides.json'
assert_md "$SKILL_MD" 'it warns the diff may be reformatting, not content' 'whitespace'
assert_md "$SKILL_MD" 'it names the refusal a reclassify can hit' 'RECLASSIFY_WOULD_BE_STALE'
assert_md "$SKILL_MD" 'pulling esas mid-session means restarting the session and the board' \
  'restart the session **and** the board'
assert_md "$SKILL_MD" 'the fleet rule: board collaboration is main-checkout-only' 'main checkout'
assert_md "$SKILL_MD" 'a worktree answers ESAS_DIR_MISSING and that is correct' 'ESAS_DIR_MISSING'
assert_md "$SKILL_MD" 'the refused batch is retried whole, never probed item by item' 'never item by item'
assert_md "$SKILL_MD" 'it points at the sibling skill for the hook line' 'esas-pending'

# Scope guard, asserted rather than trusted: `comment` and `resolve` ship as
# of esas PR #1 (slice 6), so the skill must document them — an undocumented
# tool is one the model never reaches for. The command still names no tools:
# tool inventory is the skill's job, and the command defers to it.
assert_md "$SKILL_MD" 'it documents the comment tool, which now ships' '`comment`'
assert_md "$SKILL_MD" 'it documents the resolve tool, which now ships' '`resolve`'
assert_md "$SKILL_MD" 'it steers anchors away from couplings that draw no line' 'handled-by'
refute_md "$COMMAND_MD" 'the command does not promise comment/resolve either' '`comment`'

# ── The summon — how the board wakes an idle session ──────────────────────────
#
# The board can now ask a session to look *now* (esas PR #12, ADR-008): a button
# writes `.esas/.summon`, a background watcher armed by `/design` exits on it,
# and that exit re-invokes an otherwise idle session. Every rule below has a
# failure behind it that shows up as "the wake is broken" rather than as a bug in
# the half that caused it, so each is pinned as its own needle. A summary
# sentence survives a smoothed-away invariant; these do not.

printf '\nskills/esas-design — the summon gesture\n'

assert_md "$SKILL_MD" 'invariant 1: the sentinel goes before the feed is read' \
  'Delete the sentinel before `read_changes`'
assert_md "$SKILL_MD" 'invariant 2: the watch is re-armed while forks are still open' \
  'Re-arm while any anchored fork is still `resolved: false`'
assert_md "$SKILL_MD" 'invariant 3: a wake with nothing new is a normal outcome' \
  'Tolerate an empty wake'
assert_md "$SKILL_MD" 'invariant 4: nothing is proposed off a half-answered fork' \
  'Never propose from partial answers'
assert_md "$SKILL_MD" 'invariant 5: the loop bounds itself, and dies if the sync arrives another way' \
  'Self-bound the watcher, and `TaskStop` it'
assert_md "$SKILL_MD" 'invariant 6: the two ways the watch can end are told apart' \
  '`SUMMONED` or `TIMEOUT`'

# The second refusal source, and the stronger one: the wake is delivered wrapped
# in a platform banner that declares itself NOT user input and not a response to
# any pending question. It is emitted by the runtime, cannot be suppressed, and
# arrives in the same turn as the wake — so a skill that only carves out
# `esas-pending`'s rule still deadlocks here. Pinned needle-per-invariant with
# the six above rather than folded into them, because it is the sentence a
# well-meaning edit smooths away first: it reads like a caveat and is load-
# bearing.
assert_md "$SKILL_MD" 'the not-user-input banner on the wake is not a refusal' \
  'the notification is not the answer'

# The contradiction that would deadlock the whole gesture: `esas-pending` carries
# "never sync unless the user asks", and the summon arrives through a channel
# that rule has never heard of. Without this sentence the mechanism works and the
# behaviour refuses — so it is pinned in the file that carries the rule, not in
# the one that carries the gesture. The second needle keeps the carve-out narrow:
# a press is an ask, a count still is not.
assert_md "$PENDING_MD" 'the carve-out: a summon is the user asking' \
  'A summon is the user asking'
assert_md "$PENDING_MD" 'and it stays narrow — the pending count is still telemetry' \
  'it is telemetry, never a trigger'

# ── The map and the questions ─────────────────────────────────────────────────
#
# The design's third fork — "if a question is on the board, is it also asked in
# the terminal?" — is **dissolved** rather than answered: the terminal *names*
# each fork in one line of the decision tree, the board *holds* the fork itself.
# Neither surface is a copy of the other, so there is no duplication policy to
# enforce and nothing to keep in sync between two renderings of one question.
#
# The split that makes it work is which forks can go up at all: an independent
# fork is fully written before any answer arrives and batches; a dependent fork's
# *wording* does not exist until the previous answer lands, so posting it means
# posting a guess at what the user will say. That is the summon's fourth
# invariant — never propose from partial answers — applied to asking.

printf '\nskills/esas-design — the map and the questions\n'

assert_md "$SKILL_MD" 'the split itself, in the words the design gives it' \
  'the terminal carries the map, the board carries the questions'
assert_md "$SKILL_MD" 'independent forks batch to the canvas, dependent ones stay serial' \
  'Batch the independent forks to the board; serialize the dependent ones'
assert_md "$SKILL_MD" 'the duplication question is dissolved, not policed' \
  'Neither surface is a second copy of the other'

# ── skills/grill — the map half, pinned here on purpose ───────────────────────
#
# `grill` is the third skill this suite reads, and the only one that is not a
# board artifact: the decision-tree opener applies in every repo, `.esas/` or no
# `.esas/`. It is pinned *here* because the map is the terminal half of the
# board's question surface — pinning "the board holds the questions" in one file
# while leaving "the terminal holds the map" unguarded in another would pin half
# a sentence. The suite header carries the same clause, so this is a stated
# scope rather than a quiet widening.
#
# The conditionality needle is the load-bearing one for every repo that will
# never have a board: the map is unconditional, the canvas is not, and a reader
# with no `.esas/` must come away with today's flow exactly.

printf '\nskills/grill — the decision-tree map (not board-scoped; see note)\n'

assert_md "$GRILL_MD" 'the interview opens with the map, before question one' \
  'Open with the decision tree, before the first question'
assert_md "$GRILL_MD" 'the map is maintained as tracks resolve, not printed once' \
  'Keep the map current'
assert_md "$GRILL_MD" 'a map line names its fork — it is not the question again' \
  'one line per fork, never the question restated'
assert_md "$GRILL_MD" 'the board half is conditional; the map half is not' \
  'The map is unconditional; the canvas is not'

# Green the moment it is written, and asserted anyway. The map is a numbered
# list, which is the exact shape that tempts a picker, and the standing
# preference has no carve-out — so the one edit that would quietly undo it is an
# edit that adds the map and reaches for `AskUserQuestion` to render it.
assert_md "$GRILL_MD" 'the standing rule survives the map: no picker, ever' \
  'Never use `AskUserQuestion`'

# ── The four cross-repo contracts ─────────────────────────────────────────────
#
# The sentinel path, the route that raises it, the handoff link and the port are
# spelled in esas@master — `esas-store`'s `paths.ts`/`summon.ts`, the board's
# `summon-route.ts` and `query-url.ts` — and nothing links the two repos at build
# time, so a paraphrase on this side is a silent break with a full green suite on
# both. esas pins all four there; this is the other half of the pin.
#
# `3727` is already in the command, which is the point rather than a gap: this
# one is green the day it is written, because it guards drift rather than
# introducing behaviour. It is asserted here beside its three siblings so the
# four are maintained as one contract instead of four coincidences.

printf '\nthe four cross-repo contracts (spelled as esas@master spells them)\n'

assert_md "$SKILL_MD" 'the sentinel the watcher waits on' '.esas/.summon'
assert_md "$SKILL_MD" 'the route the board raises it through' '/api/esas/board/summon'
assert_md "$SKILL_MD" 'the handoff link that opens the board on the open questions' \
  '?openComments=1&author=ai'
assert_md "$COMMAND_MD" 'the port the board claims strictly' '3727'

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
