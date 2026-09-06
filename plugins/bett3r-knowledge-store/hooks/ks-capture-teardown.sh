#!/bin/sh
[ -x "${CLAUDE_PROJECT_DIR:-.}/.knowledge-store/capture" ] || exit 0
#
# PreToolUse(Bash) — capture the artifacts a `git worktree remove` is about to
# destroy.
#
# ## Line 2 is the whole program, most of the time
#
# This is a copy of the discipline in the base plugin's
# `hooks/esas-pending.sh`, and for the same reason: there is no per-directory
# matcher for hooks. A `PreToolUse` hook on `Bash` runs **before every Bash
# call in every repo where this plugin is enabled** — every fleet worktree,
# every repo that has never heard of the knowledge store. So the first thing
# that happens is one `test` against a path that does not exist, and then this
# process is gone. Everything below line 2 is for the one checkout in a session
# that is actually configured.
#
# The sentinel is deliberately an **executable**, not a config file to parse:
#
#   * one `stat`, no read, no parse, no interpreter start — the design run
#     rejected "a config-file parse at hook start" precisely because it is I/O
#     paid by every repo that gains nothing from it;
#   * it is also the seam. `.knowledge-store/capture` is a repo-local adapter
#     the store installs; this hook hardcodes no path into esas, no package
#     name and no transport. If the capture CLI moves, is renamed, or is
#     reimplemented, nothing in this plugin changes. A repo opts in by making
#     that one file executable and opts out by removing it.
#
# ## Exit 0 on every path, always
#
# `PreToolUse` reads **exit 2 as "block this tool call"**. A hook that threw
# would cancel the user's command — and the command it is most likely to cancel
# is the teardown it exists to protect, which is the one failure worse than not
# capturing at all. So: no `set -e`, no `set -u`, no unguarded read, and no
# exit status but 0. A missed capture costs artifacts; a non-zero exit costs
# the user's command and does not save them either.
#
# ## Why `git worktree remove` and not "the PR was merged"
#
# ESAS-85 names "the command that closes the PR". No such command exists in the
# flow: `/verify-build` *opens* PRs, and `gh pr merge`, `--delete-branch`,
# `git branch -d` and `git push --delete` return zero matches across the whole
# base plugin. The real destruction point is `/start-multi` step 7, "Teardown."
# Key on *artifacts are about to be destroyed*, never on *merged*.
#
# The threat model fired during this design's own run: the `.work/` census
# measured 893 files across 6 repos and 101 nine hours later, because one fleet
# worktree holding 818 files was torn down mid-run, destroying ~30
# `*.design-draft.md` / `*.open-forks.md` files with nothing capturing them.
#
# `git worktree remove` appears in **no** markdown in the base plugin — checked
# at 74d6723, zero hits across `plugins/`, `docs/` and `scripts/`. Step 7 is an
# instruction an agent executes, not a string to grep for, so the match is on
# the **runtime Bash invocation** and can only be made here, in the hook.
#
# ## What "blocking" means here, and why this one is
#
# This capture runs **synchronously**: the tool call does not proceed until it
# returns. That is the opposite of the sibling PR hook, and deliberate —
# teardown is the irreversible moment. Once `git worktree remove` returns there
# is nothing left to read, so a capture racing it is a capture that sometimes
# loses. The cost is the hook's timeout (30s in hooks.json) against a directory
# that is about to stop existing, paid once per teardown.
#
# A capture that **fails** is loud on stderr and still exits 0. That is the
# ticket's rule stated exactly: "the store being unreachable never blocks a
# teardown — capture failure is loud, but the flow continues." A store outage
# must not become an inability to clean up worktrees.

root=${CLAUDE_PROJECT_DIR:-.}
capture=$root/.knowledge-store/capture

# ── Reading the event ────────────────────────────────────────────────────────
#
# The payload arrives on stdin as one JSON object. `hooks.json`'s `matcher`
# field selects on the **tool name** and nothing else — there is no
# command-level matcher in the platform, whatever a design table may render it
# as — so the whole of the discrimination happens below.
#
# The command is extracted by path (`tool_input.command`) rather than by
# substring, because a substring search over the raw payload would also see
# `tool_input.description`, which is agent-written prose. "Run git worktree
# remove on the stale lane" in a description is not a teardown, and treating it
# as one files a capture under a natural key parsed out of English.
KS_SCAN='
function unesc( s,   o, i, c, n ){
  o = ""; n = length( s )
  for ( i = 1; i <= n; i++ ){
    c = substr( s, i, 1 )
    if ( c != "\\" ){ o = o c; continue }
    i++
    c = substr( s, i, 1 )
    if ( c == "n" ) o = o "\n"
    else if ( c == "t" ) o = o "\t"
    else if ( c == "r" ) o = o "\r"
    else if ( c == "b" || c == "f" ) o = o " "
    else if ( c == "u" ){ o = o " "; i = i + 4 }
    else o = o c
  }
  return o
}
{ doc = doc $0 "\n" }
END {
  n = length( doc ); depth = 0; instr = 0; esc = 0; found = 0
  for ( i = 1; i <= n; i++ ){
    c = substr( doc, i, 1 )
    if ( instr ){
      if ( esc ){ esc = 0; continue }
      if ( c == "\\" ){ esc = 1; continue }
      if ( c != "\"" ) continue
      instr = 0
      val = substr( doc, start, i - start )
      j = i + 1
      while ( j <= n && index( " \t\n\r", substr( doc, j, 1 )) > 0 ) j++
      if ( substr( doc, j, 1 ) == ":" ){ key[ depth ] = val; continue }
      p = ""
      for ( d = 1; d <= depth; d++ ) p = ( p == "" ? key[ d ] : p "." key[ d ] )
      if ( p == want && !found ){ found = 1; out = unesc( val ) }
      continue
    }
    if ( c == "\"" ){ instr = 1; start = i + 1; continue }
    if ( c == "{" || c == "[" ){ depth++; key[ depth ] = ( c == "[" ? "[]" : "" ); continue }
    if ( c == "}" || c == "]" ){ delete key[ depth ]; depth--; if ( depth < 0 ) break; continue }
  }
  if ( found ) printf "%s", out
}'

# Tokenises a shell command, respecting one level of quoting, one token per
# line. Adjacency of two tokens is the entire matcher, so it has to be tokens
# and not a substring: `git worktree list && echo remove` contains both words
# and is not a teardown.
KS_TOKENS='
{ doc = doc $0 "\n" }
END {
  n = length( doc ); tok = ""; q = ""
  for ( i = 1; i <= n; i++ ){
    c = substr( doc, i, 1 )
    if ( q != "" ){ if ( c == q ) q = ""; else tok = tok c; continue }
    if ( c == "\"" || c == sq ){ q = c; continue }
    if ( c == "\\" ){ i++; tok = tok substr( doc, i, 1 ); continue }
    if ( index( " \t\n\r", c ) > 0 ){ if ( tok != "" ){ print tok; tok = "" } ; continue }
    tok = tok c
  }
  if ( tok != "" ) print tok
}'

payload=$( cat 2>/dev/null )
[ -n "$payload" ] || exit 0

command_line=$( printf '%s\n' "$payload" | awk -v want=tool_input.command "$KS_SCAN" 2>/dev/null )
[ -n "$command_line" ] || exit 0

# Cheap reject before tokenising: the vast majority of Bash calls in a
# configured repo are not teardowns either.
case $command_line in
  ( *worktree* ) ;;
  ( * ) exit 0 ;;
esac

tokens=$( printf '%s\n' "$command_line" | awk -v sq="'" "$KS_TOKENS" 2>/dev/null )
[ -n "$tokens" ] || exit 0

# `worktree` immediately followed by `remove`. This accepts every spelling
# `/start-multi` can emit — `git worktree remove <p>`, `git worktree remove
# --force <p>`, `git -C <repo> worktree remove <p>`, and any of them behind a
# `cd … &&` — and rejects `worktree list`, `worktree prune` and `worktree add`.
# `git` itself is not required to be adjacent, so an absolute path or a wrapper
# still matches; nothing else in common use spells `worktree remove`.
prev=''
matched=no
seen_remove=0
target=''
while IFS= read -r tok; do
  if [ "$seen_remove" -eq 1 ] && [ -z "$target" ]; then
    case $tok in ( -* ) ;; ( * ) target=$tok ;; esac
  fi
  if [ "$prev" = worktree ] && [ "$tok" = remove ]; then
    matched=yes
    seen_remove=1
  fi
  prev=$tok
done <<KS_TOKEN_LIST
$tokens
KS_TOKEN_LIST

[ "$matched" = yes ] || exit 0

# ── The natural key ──────────────────────────────────────────────────────────
#
# The worktree path as written, plus the cwd the command runs in, because the
# path may be relative to it. These two strings are a pure function of the
# invocation: the same teardown attempted twice produces byte-identical argv,
# which is what lets the store dedup on its own natural key and makes a double
# capture free. Nothing here is time-, run- or session-derived, and that is a
# requirement rather than an accident — a key carrying a timestamp would make
# every re-run a new record and the idempotence claim false.
[ -n "$target" ] || exit 0
cwd=$( printf '%s\n' "$payload" | awk -v want=cwd "$KS_SCAN" 2>/dev/null )

out=$( "$capture" worktree-remove "$target" "$cwd" 2>&1 )
rc=$?

if [ "$rc" -ne 0 ]; then
  # Loud, because this is the last moment these files exist and they are now
  # going to be lost — but never fatal. Stderr, not stdout: stdout from a
  # PreToolUse hook is context injected into the session, and a store outage is
  # an operator problem, not something the model should start reasoning about.
  printf 'knowledge-store: capture FAILED for `%s` (exit %d) — these artifacts are about to be destroyed and are NOT captured.\n' "$target" "$rc" >&2
  if [ -n "$out" ]; then
    printf 'knowledge-store: %s\n' "$out" >&2
  fi
fi

exit 0
