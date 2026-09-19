#!/bin/sh
payload=$( cat 2>/dev/null ); [ -n "$payload" ] || exit 0
#
# PreToolUse(Bash): in an unattended lane, refuse the git commands that discard
# or shelve the working tree.
#
# A lane is any checkout holding `.work/lane.yaml`, the brief the provisioner
# writes. The checkout a command acts on is not always the project dir: a fleet
# lane runs as a subagent of the orchestrator's session and reaches its
# worktree through `cd` or `git -C`. So the candidate checkouts are the
# payload's `cwd`, `CLAUDE_PROJECT_DIR`, and every path that follows `cd`, `-C`
# or `--work-tree` in the command (relative ones resolved against the cwd); the
# guard fires when any candidate holds the brief and the command matches.
#
# Cost in an attended session: line 2 reads the payload (one `cat`, the only
# way to learn the cwd), and a payload with no `git` in it exits on a glob
# match before any awk runs.
#
# Exit 2 blocks the tool call and hands stderr to the model; exit 0 lets it
# through. Nothing here writes to stdout: a PreToolUse hook's stdout is
# injected into the session.
#
# Blocked: `git stash` (except `create`, `list`, `show`), `git reset --hard`,
# `--merge` or `--keep`, `git checkout --`, `git checkout .`, `git checkout -f`
# or `--force`, `git switch -f`, `--force` or `--discard-changes`, `git restore`,
# `git clean -f`. The sanctioned way to inspect or snapshot uncommitted changes
# is `git stash create` followed by `git diff <object>`, which touch nothing.
#
# The command is read by path (`tool_input.command`), never by substring over
# the payload, so a description that mentions `git stash` is not a match. The
# match is on the command's own tokens, with `;`, `|`, `&`, `(`, `)`, a
# backtick and a newline as invocation separators, so a quoted string carrying
# the words is not a match; a heredoc body line that starts with `git stash`
# is, and that is the accepted boundary.

case $payload in
  ( *git* ) ;;
  ( * ) exit 0 ;;
esac

# Extracts one dotted key from the JSON payload (same technique as the sibling
# plugin's hooks): walks the document once, tracks the key path, and prints the
# first string value at `want`.
LG_SCAN='
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

# Tokenises a shell command, one token per line, respecting one level of
# quoting. Command separators outside quotes (`;`, `|`, `&`, `(`, `)`, a
# backtick, a newline) become a `;` token of their own, so `cd x && git stash`,
# `git stash;echo`, `x=`git stash`` and a second line all start a fresh
# invocation.
LG_TOKENS='
{ doc = doc $0 "\n" }
END {
  n = length( doc ); tok = ""; q = ""
  for ( i = 1; i <= n; i++ ){
    c = substr( doc, i, 1 )
    if ( q != "" ){ if ( c == q ) q = ""; else tok = tok c; continue }
    if ( c == "\"" || c == sq ){ q = c; continue }
    if ( c == "\\" ){ i++; tok = tok substr( doc, i, 1 ); continue }
    if ( index( ";|&()`\n\r", c ) > 0 ){ if ( tok != "" ){ print tok; tok = "" } ; print ";"; continue }
    if ( index( " \t", c ) > 0 ){ if ( tok != "" ){ print tok; tok = "" } ; continue }
    tok = tok c
  }
  if ( tok != "" ) print tok
}'

command_line=$( printf '%s\n' "$payload" | awk -v want=tool_input.command "$LG_SCAN" 2>/dev/null )
[ -n "$command_line" ] || exit 0

case $command_line in
  ( *git* ) ;;
  ( * ) exit 0 ;;
esac

cwd=$( printf '%s\n' "$payload" | awk -v want=cwd "$LG_SCAN" 2>/dev/null )
[ -n "$cwd" ] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

tokens=$( printf '%s\n' "$command_line" | awk -v sq="'" "$LG_TOKENS" 2>/dev/null )
[ -n "$tokens" ] || exit 0

# ── Which checkout does the command act on? ──────────────────────────────────
#
# Candidates: the cwd, the project dir, and every path after `cd`, `-C` or
# `--work-tree`. A relative path resolves against the cwd.

has_lane(){
  case $1 in
    ( /* )   d=$1 ;;
    ( '~' )  d=${HOME:-/nonexistent} ;;
    ( '~/'* ) d=${HOME:-/nonexistent}/${1#\~/} ;;
    ( * )    d=$cwd/$1 ;;
  esac
  [ -f "$d/.work/lane.yaml" ]
}

lane=0
for d in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
  [ -n "$d" ] && [ -f "$d/.work/lane.yaml" ] && lane=1
done

if [ "$lane" -eq 0 ]; then
  expect=0
  while IFS= read -r tok; do
    if [ "$expect" -eq 1 ]; then
      expect=0
      case $tok in
        ( ';' | -* ) ;;
        ( * ) has_lane "$tok" && lane=1 ;;
      esac
    else
      case $tok in
        ( cd | -C | --work-tree ) expect=1 ;;
        ( --work-tree=* ) has_lane "${tok#--work-tree=}" && lane=1 ;;
      esac
    fi
    [ "$lane" -eq 1 ] && break
  done <<LG_CANDIDATES
$tokens
LG_CANDIDATES
fi

[ "$lane" -eq 1 ] || exit 0

# ── Does the command discard or shelve the tree? ─────────────────────────────
#
# `state` is where we are inside one git invocation:
#   idle    outside any invocation, waiting for a `git` token
#   git     after `git`, reading global options until the subcommand
#   gitarg  the argument of a global option that takes one (`-C <path>`)
#   sub     inside the subcommand's arguments
# `stash_pending` marks a `git stash` whose verb has not been seen yet: it is
# allowed only if the very next token is `create`, `list` or `show`.
state=idle
sub=''
hit=''
stash_pending=0

settle_stash(){
  if [ "$stash_pending" -eq 1 ]; then hit='git stash'; fi
  stash_pending=0
}

while IFS= read -r tok; do
  if [ "$tok" = ';' ]; then
    settle_stash
    [ -n "$hit" ] && break
    state=idle; sub=''
    continue
  fi
  case $state in
    idle )
      case $tok in
        ( git | */git ) state=git ;;
      esac
      ;;
    git )
      case $tok in
        ( -C | -c | --git-dir | --work-tree | --namespace ) state=gitarg ;;
        ( -* ) ;;
        ( * )
          sub=$tok; state=sub
          case $sub in
            ( stash )   stash_pending=1 ;;
            ( restore ) hit='git restore' ;;
          esac
          ;;
      esac
      ;;
    gitarg ) state=git ;;
    sub )
      case $sub in
        ( stash )
          if [ "$stash_pending" -eq 1 ]; then
            case $tok in
              ( create | list | show ) stash_pending=0 ;;
              ( * ) hit='git stash' ;;
            esac
          fi
          ;;
        ( reset )
          case $tok in
            ( --hard | --merge | --keep ) hit="git reset $tok" ;;
          esac
          ;;
        ( checkout )
          case $tok in
            ( -- )            hit='git checkout --' ;;
            ( . )             hit='git checkout .' ;;
            ( -f | --force )  hit="git checkout $tok" ;;
            ( -[a-zA-Z]*f* )  hit='git checkout -f' ;;
          esac
          ;;
        ( switch )
          case $tok in
            ( -f | --force | --discard-changes ) hit="git switch $tok" ;;
            ( -[a-zA-Z]*f* )                     hit='git switch -f' ;;
          esac
          ;;
        ( clean )
          case $tok in
            ( --force ) hit='git clean -f' ;;
            ( --* ) ;;
            ( -*f* ) hit='git clean -f' ;;
          esac
          ;;
      esac
      ;;
  esac
  [ -n "$hit" ] && break
done <<LG_TOKEN_LIST
$tokens
LG_TOKEN_LIST

settle_stash

[ -n "$hit" ] || exit 0

printf 'lane-git-guard: blocked `%s`: this checkout is an unattended lane (.work/lane.yaml) and the working tree is neither discarded nor shelved; to inspect or snapshot uncommitted changes use `git stash create` and `git diff <object>`, which touch nothing.\n' "$hit" >&2
exit 2
