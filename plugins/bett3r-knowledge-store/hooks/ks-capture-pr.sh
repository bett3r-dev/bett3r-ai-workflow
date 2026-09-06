#!/bin/sh
[ -x "${CLAUDE_PROJECT_DIR:-.}/.knowledge-store/capture" ] || exit 0
#
# PostToolUse(Bash) — capture a PR that was just opened, and kick extraction.
#
# Line 2, the sentinel and the exit-0 discipline are the sibling hook's; read
# `ks-capture-teardown.sh` for why they are written that way. The scanner below
# is duplicated from it **on purpose**: each hook is a single file with no
# sibling to resolve at runtime, so neither can fail by not finding the other
# after a packaging change. The oracle drives both independently, so drift
# between the two copies is a red suite rather than a silent divergence.
#
# ## Three consumers, one event
#
# ESAS-85 (capture the PR body), ESAS-87 (kick extraction) and ESAS-92 (export
# freshness) all attach here. None of them is named in this file: the hook
# reports *what happened* to `.knowledge-store/capture` and the store decides
# who cares. That is the coupling invariant — the store adapts to the flow,
# never the reverse — applied one level down, so adding a fourth consumer never
# touches this plugin.
#
# ## Why this one does not block
#
# `PostToolUse` fires **after** the tool returned, so the PR already exists:
# there is nothing left to protect by waiting, and nothing this hook can do can
# un-create it. The only thing waiting would buy is a stall in front of the
# user at the end of every `/verify-build`. So the capture is detached and this
# process returns immediately.
#
# The contrast with the teardown hook is the whole of the design decision:
# **blocking at teardown, non-blocking at PR create.** Teardown is irreversible
# and racing it loses data; this is neither.
#
# Because it is detached it cannot be loud in front of the user, so failures go
# to `.knowledge-store/capture.log`. A dropped PR capture is recoverable — the
# PR is still there and the natural key is the PR URL, so the next run captures
# it — which is exactly why it is allowed to be the quiet half.

root=${CLAUDE_PROJECT_DIR:-.}
capture=$root/.knowledge-store/capture
log=$root/.knowledge-store/capture.log

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

case $command_line in
  ( *' pr '* | pr\ * | *' pr' ) ;;
  ( * ) exit 0 ;;
esac

tokens=$( printf '%s\n' "$command_line" | awk -v sq="'" "$KS_TOKENS" 2>/dev/null )
[ -n "$tokens" ] || exit 0

# `gh pr create`, three adjacent tokens. `gh pr view`, `gh pr edit` and
# `gh pr merge` are not this event — and `gh pr merge` in particular is the one
# the original ticket text reached for, which is why it is named here as a
# non-match rather than left to be inferred: nothing in the flow runs it, and a
# matcher pointed at it would have fired never.
p2=''
p1=''
matched=no
while IFS= read -r tok; do
  if [ "$p2" = gh ] && [ "$p1" = pr ] && [ "$tok" = create ]; then
    matched=yes
    break
  fi
  p2=$p1
  p1=$tok
done <<KS_TOKEN_LIST
$tokens
KS_TOKEN_LIST

[ "$matched" = yes ] || exit 0

# ── The natural key ──────────────────────────────────────────────────────────
#
# The PR URL `gh pr create` prints on stdout. It is the best key available: the
# store, not this hook, fetches the body — which keeps the hook thin and means
# the three consumers can each read whatever they need without this file ever
# learning what a PR body is.
#
# No URL means `gh pr create` did not create a PR (it failed, or it was a
# `--dry-run`). There is nothing to capture and nothing to enqueue, so this is
# a silent exit rather than a capture under a guessed key.
stdout_text=$( printf '%s\n' "$payload" | awk -v want=tool_response.stdout "$KS_SCAN" 2>/dev/null )
url=$( printf '%s\n' "$stdout_text" \
       | tr ' \t' '\n\n' \
       | sed -n 's|^\(https://[^ ]*/pull/[0-9][0-9]*\)$|\1|p' \
       | head -1 )
[ -n "$url" ] || exit 0

cwd=$( printf '%s\n' "$payload" | awk -v want=cwd "$KS_SCAN" 2>/dev/null )

# Detached. `>/dev/null 2>&1 </dev/null` on the subshell as well as the child,
# so nothing this ever prints can land in front of the user after the hook has
# already returned.
{
  if ! "$capture" pr-create "$url" "$cwd" >>"$log" 2>&1; then
    printf 'knowledge-store: pr-create capture failed for %s\n' "$url" >>"$log" 2>/dev/null
  fi
} >/dev/null 2>&1 </dev/null &

exit 0
