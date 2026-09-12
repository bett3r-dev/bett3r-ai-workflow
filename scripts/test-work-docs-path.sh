#!/bin/sh
# Oracle for `bin/work-docs-path` — where a work item's committed record lives.
#
# `/design` writes and commits `<root>/<id>/design.md`, and every reader of the
# design (`/plan`, `/verify-build`, the verifier, `handon`, `critique`, …) has to
# arrive at the same folder. The rule that names it is short — `docs/prs` unless
# `.claude/bett3r-ai-workflow.json` sets `workDocsRoot`; the Jira key as-is,
# `gh-<n>` for a GitHub issue, `<yyyy-mm-dd>-<slug>` with no id — and a short
# rule restated in ten command files is ten chances to drift. So it is ONE
# script, and this suite executes it instead of reviewing the prose.
#
# Every case drives the real launcher against a throwaway repo in a temp dir and
# reads the `WORK-DOCS-PATH:v1` verdict line (ADR-004), never the exit code
# alone. The malformed-input cases are the load-bearing half: a config the
# script cannot read must be a loud `outcome=error`, never a silent fall back to
# `docs/prs` — a silently defaulted root writes the design somewhere no reader
# configured for the override will ever look.
#
# Run locally:  sh scripts/test-work-docs-path.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# WDP_SH selects the interpreter that runs the `bin/work-docs-path` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
WDP="$ROOT/plugins/bett3r-ai-workflow/bin/work-docs-path"
WDP_SH=${WDP_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/work-docs-path-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fixture owns everything ambient the script reads:
#  - git's configuration (no user/system gitconfig), and GIT_CEILING_DIRECTORIES
#    so the "not a git repo" case cannot discover a repository above the temp
#    dir on whichever machine runs it;
#  - TZ, pinned although the script no longer reads the clock: a no-id work
#    item's date is fixed by `/start` and passed in, and every date below is a
#    synthesized literal. Pinning it keeps a regression that re-reads "today"
#    from depending on who runs the suite.
HOME="$TMP/home"; mkdir -p "$HOME"; export HOME
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES=$TMP TZ=UTC
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_CEILING_DIRECTORIES TZ
unset GIT_DIR GIT_WORK_TREE

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

# check <description> <actual> <expected> [context lines…]
# An EMPTY expected value is refused — an expectation computed by a step that
# never ran would otherwise be "equal" to an actual that is also empty.
check(){
  if [ -z "$3" ]; then
    d=$1; shift 3
    fail "$d" 'expected value is empty — the step that computes it did not run' "$@"
  elif [ "$2" = "$3" ]; then
    pass "$1"
  else
    d=$1 a=$2 e=$3; shift 3
    fail "$d" "expected: $e" "actual:   $a" "$@"
  fi
}

check_empty(){
  if [ -z "$2" ]; then
    pass "$1"
  else
    d=$1 a=$2; shift 2
    fail "$d" 'expected: (empty)' "actual:   $a" "$@"
  fi
}

# wdp <cwd> <args…> — run the launcher from <cwd>, stdout+stderr to $OUT, and
# keep its real exit status in $rc (never through a pipe). $LINE is the verdict.
OUT="$TMP/out"
wdp(){
  cwd=$1; shift
  ( cd "$cwd" && "$WDP_SH" "$WDP" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^WORK-DOCS-PATH:v1 outcome=[a-z]+( [A-Za-z]+=[^ ]*)*$'
}

# attr <verdict-line> <key> — one attribute's value from a verdict line.
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# new_repo <name> — an empty git repo (no commit is needed to resolve the
# top-level); sets $REPO.
new_repo(){
  REPO="$TMP/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
}

# config <json text> — write the plugin's repo config into $REPO.
config(){
  mkdir -p "$REPO/.claude"
  printf '%s\n' "$1" > "$REPO/.claude/bett3r-ai-workflow.json"
}

# expect_ok <description> <path> <id> <root> <source> <args…>
#
# POSIX sh has no `local`, and `check` assigns `d`/`a`/`e` when it fails — so
# these helpers keep their own values under x-prefixed names, or one failing
# check would rename every later assertion in the same case.
expect_ok(){
  xd=$1 xp=$2 xi=$3 xr=$4 xs=$5; shift 5
  wdp "$REPO" "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" )"
    return
  fi
  check "$xd: outcome" "$( attr "$LINE" outcome )" ok "$LINE"
  check "$xd: path"    "$( attr "$LINE" path )"    "$xp" "$LINE"
  check "$xd: id"      "$( attr "$LINE" id )"      "$xi" "$LINE"
  check "$xd: root"    "$( attr "$LINE" root )"    "$xr" "$LINE"
  check "$xd: source"  "$( attr "$LINE" source )"  "$xs" "$LINE"
  check "$xd: exit 0"  "$rc" 0
}

# expect_error <description> <reason> <args…>
expect_error(){
  xd=$1 xreason=$2; shift 2
  wdp "$REPO" "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" )"
    return
  fi
  check "$xd: outcome=error" "$( attr "$LINE" outcome )" error "$LINE"
  check "$xd: reason"        "$( attr "$LINE" reason )"  "$xreason" "$LINE"
  # An error that still names a path is a silent default wearing an error's
  # clothes: a caller reading `path=` first would write there anyway.
  check_empty "$xd: prints no path=" "$( attr "$LINE" path )" "$LINE"
  check "$xd: exit 2" "$rc" 2
}

# ---------------------------------------------------------------------------
printf 'id normalisation (default root)\n'
# ---------------------------------------------------------------------------
new_repo plain

expect_ok 'Jira key as-is'           docs/prs/TV1-2400 TV1-2400 docs/prs default --item TV1-2400
expect_ok 'GitHub issue #268'        docs/prs/gh-268   gh-268   docs/prs default --item '#268'
expect_ok 'GitHub issue as gh-268'   docs/prs/gh-268   gh-268   docs/prs default --item gh-268
expect_ok 'no id: the dated id /start recorded, as-is' \
  docs/prs/2026-09-12-add-widget 2026-09-12-add-widget docs/prs default --item 2026-09-12-add-widget

wdp "$REPO" --item TV1-2400
check 'a folder not yet written reports exists=false' "$( attr "$LINE" exists )" false "$LINE"
mkdir -p "$REPO/docs/prs/TV1-2400"
wdp "$REPO" --item TV1-2400
check 'an existing folder reports exists=true' "$( attr "$LINE" exists )" true "$LINE"

# A no-id work item's date is fixed ONCE, by `/start`, and carried in
# `.work/mode.yaml`'s `work_item:` — so the folder is a pure function of that
# value, with no directory lookup. Another folder for the same slug on another
# date is another work item (a branch name reused months later), and must never
# be picked up: a lookup that "resumes" it is exactly how an unrelated design
# gets overwritten.
mkdir -p "$REPO/docs/prs/2026-01-02-resume-me"
expect_ok 'no id: the exact dated folder, even when it exists' \
  docs/prs/2026-01-02-resume-me 2026-01-02-resume-me docs/prs default --item 2026-01-02-resume-me
check 'the dated folder that exists reports exists=true' "$( attr "$LINE" exists )" true "$LINE"
expect_ok 'no id: another date for the same slug is never reused (no lookup)' \
  docs/prs/2026-03-04-resume-me 2026-03-04-resume-me docs/prs default --item 2026-03-04-resume-me
check 'the same slug on another date reports exists=false' "$( attr "$LINE" exists )" false "$LINE"
mkdir -p "$REPO/docs/prs/2026-02-03-twice" "$REPO/docs/prs/2026-04-05-twice"
expect_ok 'two dated folders for one slug are not ambiguous: the id names one' \
  docs/prs/2026-04-05-twice 2026-04-05-twice docs/prs default --item 2026-04-05-twice

# ---------------------------------------------------------------------------
printf '\nthe workDocsRoot override\n'
# ---------------------------------------------------------------------------
new_repo override
config '{"workDocsRoot": "work-docs"}'
expect_ok 'override honoured'          work-docs/TV1-2400 TV1-2400 work-docs config --item TV1-2400
config '{"workDocsRoot": "./records/prs/"}'
expect_ok 'override normalised (./ and trailing /)' records/prs/gh-7 gh-7 records/prs config --item '#7'
config '{"somethingElse": true}'
expect_ok 'a config without the key keeps the default' docs/prs/TV1-1 TV1-1 docs/prs default --item TV1-1

# Found from a subdirectory: the repo root is git's, not the caller's cwd.
config '{"workDocsRoot": "work-docs"}'
mkdir -p "$REPO/src/deep"
wdp "$REPO/src/deep" --item TV1-2400
check 'run from a subdirectory: root is read from the repo top-level' "$( attr "$LINE" path )" work-docs/TV1-2400 "$LINE"
wdp "$TMP" --repo "$REPO" --item TV1-2400
check '--repo names the repository explicitly' "$( attr "$LINE" path )" work-docs/TV1-2400 "$LINE"

# ---------------------------------------------------------------------------
printf '\nmalformed config — loud, never a silent default\n'
# ---------------------------------------------------------------------------
new_repo badconfig
config '{"workDocsRoot": '
expect_error 'unparseable JSON'              config-unparseable       --item TV1-2400
config '["docs/prs"]'
expect_error 'config is not an object'       config-not-object        --item TV1-2400
config '{"workDocsRoot": 5}'
expect_error 'non-string root'               config-root-not-string   --item TV1-2400
config '{"workDocsRoot": ""}'
expect_error 'empty root'                    config-root-empty        --item TV1-2400
config '{"workDocsRoot": "."}'
expect_error 'root that is the repo itself'  config-root-empty        --item TV1-2400
config "{\"workDocsRoot\": \"$TMP/elsewhere\"}"
expect_error 'absolute root'                 config-root-absolute     --item TV1-2400
config '{"workDocsRoot": "../outside"}'
expect_error 'root escaping the repo'        config-root-escapes-repo --item TV1-2400
config '{"workDocsRoot": "docs/../../outside"}'
expect_error 'root escaping via a nested ..' config-root-escapes-repo --item TV1-2400
config '{"workDocsRoot": ".work/records"}'
expect_error 'root inside the gitignored .work/' config-root-in-work  --item TV1-2400
config '{"workDocsRoot": "my docs"}'
expect_error 'root with whitespace'          config-root-whitespace   --item TV1-2400

# ---------------------------------------------------------------------------
printf '\nmalformed work item and usage\n'
# ---------------------------------------------------------------------------
new_repo baditem
for bad in tv1-2400 TV1- -2400 '#' '#abc' '#12a' gh- 'TV1-2400/x' 'TV1 2400'; do
  expect_error "malformed item '$bad'" malformed-item --item "$bad"
done
# A no-id work item is `<yyyy-mm-dd>-<slug>`. Its slug half is lower-case
# letters and digits in dash-separated words.
for bad in 'Add-Widget' 'feat/widget' 'add--widget' '-add' 'add widget' ''; do
  expect_error "malformed slug in a dated id '2026-09-12-$bad'" malformed-slug --item "2026-09-12-$bad"
done
expect_error 'a date with no slug'           malformed-slug    --item 2026-09-12
# Its date half is a real calendar day in exactly that shape.
expect_error 'impossible date'               malformed-date    --item 2026-13-01-add-widget
expect_error 'impossible day'                malformed-date    --item 2026-02-30-add-widget
# The shape check is the regex, not `date.fromisoformat`, which on Python >= 3.11
# accepts the basic form. Neither is a dated id at all, so it is not one.
expect_error 'date without dashes'           malformed-item    --item 20260912-add-widget
expect_error 'date in the wrong shape'       malformed-item    --item 12/09/2026-add-widget
# An UNDATED slug is no longer a work item: the date is fixed at /start, and a
# script that invented one here (today, or a lookup) is how a reused branch
# name overwrote an unrelated design.
expect_error 'a slug with no date'           malformed-item    --item add-widget
expect_error 'no work item at all'           missing-work-item
# The retired flags are loud, never silently ignored: a caller still passing
# them is a caller still re-deriving the date.
expect_error 'the retired slug flag'         unknown-flag-slug --slug add-widget
expect_error 'the retired date flag'         unknown-flag-date --item 2026-09-12-add-widget --date 2026-09-12
expect_error 'unknown flag'                  unknown-flag-root --root x --item TV1-1
expect_error 'a flag missing its value'      missing-value-item --item
expect_error 'a stray positional argument'   unexpected-argument TV1-1

mkdir -p "$TMP/not-a-repo"
wdp "$TMP/not-a-repo" --item TV1-2400
check 'outside any git repository: error' "$( attr "$LINE" reason )" not-a-git-repo "$LINE" "$( cat "$OUT" )"
wdp "$TMP" --repo "$TMP/missing" --item TV1-2400
check '--repo naming no directory: error' "$( attr "$LINE" reason )" repo-not-a-directory "$LINE"

# ---------------------------------------------------------------------------
printf '\nownership — read from the design'\''s header, never from git history\n'
# ---------------------------------------------------------------------------
# `/design` overwrites an existing folder only when the design in it is THIS
# work item's on THIS branch. A slug is not unique over time, and git history
# cannot say who wrote a folder: a stacked child, a feature that merged an
# unmerged parent, and a branch cut from a remote the local `origin` never
# fetched all hold another work item's design in commits reachable from HEAD.
# So ownership is recorded in the artifact — a frontmatter block
# (`work_item:`, `branch:`) at the top of `<path>/design.md` — and
# `--owner-branch` makes the script report it as `owner=`.
#
# The topology cases below build the verifier's reproduced histories for real
# and assert the verdict the HEADER dictates: the script must answer the same
# whatever the history says, because it never reads it.

# header <dir> <work_item> <branch> — write a design.md carrying the header.
header(){
  mkdir -p "$1"
  printf -- '---\nwork_item: %s\nbranch: %s\n---\n\n# Design\n' "$2" "$3" > "$1/design.md"
}

# expect_owner <description> <expected owner> <args…> — outcome=ok and owner=.
expect_owner(){
  xd=$1 xo=$2; shift 2
  wdp "$REPO" "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" )"
    return
  fi
  check "$xd: outcome=ok"  "$( attr "$LINE" outcome )" ok "$LINE"
  check "$xd: owner=$xo"   "$( attr "$LINE" owner )"   "$xo" "$LINE"
  check "$xd: exit 0"      "$rc" 0
}

new_repo owner
D="$REPO/docs/prs/2026-01-02-bar"

# (a) own re-run
header "$D" 2026-01-02-bar feat/bar
expect_owner '(a) own re-run: header names this dated id and this branch' self \
  --item 2026-01-02-bar --owner-branch feat/bar
check '(a) own re-run: the folder is the dated one' "$( attr "$LINE" path )" docs/prs/2026-01-02-bar "$LINE"
check '(a) own re-run: exists=true' "$( attr "$LINE" exists )" true "$LINE"

# header-only: another branch or another work item → other
expect_owner 'same slug, header branch is another branch' other --item 2026-01-02-bar --owner-branch child
header "$D" 2026-01-02-foo feat/bar
expect_owner 'same branch, header work_item is another work item' other --item 2026-01-02-bar --owner-branch feat/bar
# Comparison is exact: a branch that only contains, prefixes or case-folds the
# header's branch is another branch.
header "$D" 2026-01-02-bar feat/bar
expect_owner 'a branch that merely starts with the header branch is not self' other --item 2026-01-02-bar --owner-branch feat/bar-2
expect_owner 'a branch that differs only in case is not self' other --item 2026-01-02-bar --owner-branch Feat/Bar

# (e) an existing folder whose design proves no owner — fail closed
rm -f "$D/design.md"
expect_owner '(e) folder exists, no design.md' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf '# Design\n\nno header here\n' > "$D/design.md"
expect_owner '(e) design.md without a header (a legacy design)' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: 2026-01-02-bar\n---\n# Design\n' > "$D/design.md"
expect_owner '(e) header missing branch' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nbranch: feat/bar\n---\n# Design\n' > "$D/design.md"
expect_owner '(e) header missing work_item' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: 2026-01-02-bar\nbranch: feat/bar\n# Design\n' > "$D/design.md"
expect_owner '(e) header never closed' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: 2026-01-02-bar\nthis is not a key\nbranch: feat/bar\n---\n' > "$D/design.md"
expect_owner '(e) header with an unparseable line' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: 2026-01-02-bar\nbranch: other\nbranch: feat/bar\n---\n' > "$D/design.md"
expect_owner '(e) header with a duplicated key (the last one matching)' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: 2026-01-02-bar\nbranch:\n---\n' > "$D/design.md"
expect_owner '(e) header with an empty branch' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '\n---\nwork_item: 2026-01-02-bar\nbranch: feat/bar\n---\n' > "$D/design.md"
expect_owner '(e) header not on the first line' unowned --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\r\nwork_item: 2026-01-02-bar\r\nbranch: feat/bar\r\n---\r\n' > "$D/design.md"
expect_owner '(e) CRLF header still parses (an editor on Windows)' self --item 2026-01-02-bar --owner-branch feat/bar
printf '\377\376---\n' > "$D/design.md"
expect_owner '(e) design.md not readable as UTF-8' unowned --item 2026-01-02-bar --owner-branch feat/bar
rm -f "$D/design.md"; mkdir -p "$D/design.md"
expect_owner '(e) design.md is a directory' unowned --item 2026-01-02-bar --owner-branch feat/bar
rmdir "$D/design.md"
# A header that CARRIES extra keys is still an owner record — only the two
# ownership keys are read. A comment after a value is not part of it (a branch
# name cannot contain whitespace, so ` #` can only start a comment).
printf -- '---\nwork_item: 2026-01-02-bar   # the dated id\nbranch: feat/bar\nnote: kept\n---\n' > "$D/design.md"
expect_owner 'extra keys and a trailing comment do not break a matching header' self --item 2026-01-02-bar --owner-branch feat/bar
printf -- '---\nwork_item: "2026-01-02-bar"\nbranch: '\''feat/bar'\''\n---\n' > "$D/design.md"
expect_owner 'quoted values are the same values' self --item 2026-01-02-bar --owner-branch feat/bar

# (f) no folder — no owner claim; a fresh write is allowed
expect_owner '(f) folder does not exist' none --item 2026-01-02-never-written --owner-branch feat/bar
check '(f) folder does not exist: exists=false' "$( attr "$LINE" exists )" false "$LINE"

# (g) a ticket folder: the SAME rule — work_item AND branch. A ticket designed
# on another branch (a stacked follow-up, a fleet lane beside an interactive
# retry) stops too; re-designing on a new branch is a hand edit of `branch:`.
header "$REPO/docs/prs/TV1-2400" TV1-2400 tv1-2400-widgets
expect_owner '(g) --item, header matches id and branch' self --item TV1-2400 --owner-branch tv1-2400-widgets
expect_owner '(g) --item, same ticket on another branch' other --item TV1-2400 --owner-branch tv1-2400-take-two
header "$REPO/docs/prs/TV1-2400" TV1-9 tv1-2400-widgets
expect_owner '(g) --item, header names another ticket' other --item TV1-2400 --owner-branch tv1-2400-widgets
# `#268` and `gh-268` name one GitHub issue, so either spelling is this issue —
# but an UNQUOTED `#268` is a YAML comment (the value is empty), so the header
# writes `gh-268` or quotes it, and the bare form fails closed.
header "$REPO/docs/prs/gh-268" '"#268"' feat/268
expect_owner '(g) --item #268, header spells it "#268"' self --item '#268' --owner-branch feat/268
expect_owner '(g) --item gh-268, header spells it "#268"' self --item gh-268 --owner-branch feat/268
header "$REPO/docs/prs/gh-268" gh-268 feat/268
expect_owner '(g) --item #268, header spells it gh-268' self --item '#268' --owner-branch feat/268
header "$REPO/docs/prs/gh-268" '#268' feat/268
expect_owner '(g) an unquoted #268 is a comment: no work_item, unowned' unowned --item '#268' --owner-branch feat/268
header "$REPO/docs/prs/TV1-7" tv1-7 feat/7
expect_owner '(g) --item, a header work_item that is not a valid key is not self' other --item TV1-7 --owner-branch feat/7

# (h) the owner field: present only when asked, never on an error
wdp "$REPO" --item 2026-01-02-bar
check_empty '(h) without --owner-branch the verdict carries no owner=' "$( attr "$LINE" owner )" "$LINE"
check '(h) without --owner-branch the verdict is unchanged for readers' "$( attr "$LINE" path )" docs/prs/2026-01-02-bar "$LINE"
expect_error '(h) --owner-branch with whitespace'  malformed-owner-branch --item 2026-01-02-bar --owner-branch 'feat bar'
check_empty  '(h) an error verdict carries no owner=' "$( attr "$LINE" owner )" "$LINE"
expect_error '(h) --owner-branch empty (a detached HEAD)' malformed-owner-branch --item 2026-01-02-bar --owner-branch ''
check_empty  '(h) detached-HEAD error carries no owner=' "$( attr "$LINE" owner )" "$LINE"
header "$D" 2026-01-02-bar feat/bar
wdp "$REPO" --item 2026-01-02-bar --owner-branch feat/bar
check '(h) the owner field parses from the verdict grammar' \
  "$( printf '%s\n' "$LINE" | grep -Ec '^WORK-DOCS-PATH:v1 outcome=ok( [A-Za-z]+=[^ ]*)* owner=(self|other|unowned|none)( [A-Za-z]+=[^ ]*)*$' )" 1 "$LINE"

# --- (b)(c)(d) the verifier's topologies, built for real ---------------------
# Each is a real history in which commits reachable from the asking HEAD wrote
# the same-slug folder, so the retired `git log "$mb"..HEAD` rule said "own".
commit_all(){ git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }

new_repo topo
git -C "$REPO" checkout -qb master
printf 'x\n' > "$REPO/README"; commit_all "$REPO" base
# parent PA writes slug `bar` and is never merged
git -C "$REPO" checkout -qb pa
header "$REPO/docs/prs/2026-01-02-bar" 2026-01-02-bar pa; commit_all "$REPO" 'docs(bar): design'
# (b) stacked child cut from PA
git -C "$REPO" checkout -qb child
expect_owner '(b) stacked child from unmerged parent, same slug' other --item 2026-01-02-bar --owner-branch child
# (c) feature branch from master that merged PA
git -C "$REPO" checkout -q master
git -C "$REPO" checkout -qb feature
printf 'f\n' > "$REPO/F"; commit_all "$REPO" feature
git -C "$REPO" -c user.name=t -c user.email=t@t merge -q --no-edit pa > /dev/null
check '(c) fixture: the merged feature holds the parent design' "$( [ -f "$REPO/docs/prs/2026-01-02-bar/design.md" ] && echo yes )" yes
expect_owner '(c) feature that merged an unmerged parent, same slug' other --item 2026-01-02-bar --owner-branch feature
# The parent itself, on its own branch, still owns it — through the same
# history the child and the feature share.
git -C "$REPO" checkout -q pa
expect_owner 'the parent on its own branch: self' self --item 2026-01-02-bar --owner-branch pa
# The opposite direction: this branch's own design already MERGED to master
# (present at the fork point, which the retired rule read as "someone else's")
# — the header still says self, and self is the answer.
git -C "$REPO" checkout -q master
git -C "$REPO" -c user.name=t -c user.email=t@t merge -q --no-edit pa > /dev/null
git -C "$REPO" checkout -q pa
expect_owner 'own design already merged to the default branch: still self' self --item 2026-01-02-bar --owner-branch pa
# No history at all: a header written and never committed decides the same.
new_repo nohistory
header "$REPO/docs/prs/2026-01-02-bar" 2026-01-02-bar feat/bar
expect_owner 'an uncommitted design in a repo with no commits: self from the header alone' self --item 2026-01-02-bar --owner-branch feat/bar

# (d) a second remote; local origin is stale; E landed upstream
UP="$TMP/upstream"
git init -q --bare "$UP"
new_repo stale
git -C "$REPO" checkout -qb master
printf 'x\n' > "$REPO/README"; commit_all "$REPO" base
git -C "$REPO" remote add origin "$UP"
git -C "$REPO" push -q origin master 2>/dev/null
git -C "$REPO" fetch -q origin
git -C "$REPO" remote add upstream "$UP"
git clone -q "$UP" "$TMP/e-author" 2>/dev/null
git -C "$TMP/e-author" checkout -q master 2>/dev/null
header "$TMP/e-author/docs/prs/2026-01-02-bar" 2026-01-02-bar e-branch
commit_all "$TMP/e-author" 'docs(bar): design (E)'
git -C "$TMP/e-author" push -q origin master 2>/dev/null
git -C "$REPO" fetch -q upstream
git -C "$REPO" checkout -qb mine upstream/master 2>/dev/null
check '(d) fixture: local origin/master is stale (lacks E)' \
  "$( git -C "$REPO" cat-file -e origin/master:docs/prs/2026-01-02-bar/design.md 2>/dev/null || echo stale )" stale
check '(d) fixture: the branch holds E'"'"'s design' "$( [ -f "$REPO/docs/prs/2026-01-02-bar/design.md" ] && echo yes )" yes
expect_owner '(d) branch cut from upstream/master past a stale origin, same slug' other --item 2026-01-02-bar --owner-branch mine

# A header written before ids were dated names a bare slug. It is not this
# dated work item: the comparison is exact, never a suffix match.
new_repo legacy
header "$REPO/docs/prs/2026-01-02-bar" bar feat/bar
expect_owner 'a header naming the undated slug is not the dated work item' other --item 2026-01-02-bar --owner-branch feat/bar

# --- a branch name reused for unrelated work --------------------------------
# `fix/flaky` is started on 2026-01-02 (/start records work_item
# 2026-01-02-flaky), designs, merges, and is deleted. Months later `fix/flaky`
# is cut again for unrelated work: /start runs on 2026-03-04 and records
# 2026-03-04-flaky. Header matching alone cannot tell the two apart — same slug
# derivation, same branch name — so the DATE fixed at /start is what does. The
# retired lookup reused the single existing `<date>-flaky` folder, whose header
# then matched: owner=self, and the old design was overwritten.
#
# start_item <yyyy-mm-dd> <branch> — the work_item /start records with no id:
# the date it ran, then the last path segment of the branch as a slug.
start_item(){
  printf '%s-%s\n' "$1" "$( printf '%s' "${2##*/}" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-*//; s/-*$//' )"
}
# design_pass <work_item> <branch> — /design Step 4 as the writer: ask for
# ownership, and write + commit only on none/self. Sets $LINE.
design_pass(){
  wdp "$REPO" --item "$1" --owner-branch "$2"
  xo=$( attr "$LINE" owner )
  case $xo in
    none|self)
      xpath=$( attr "$LINE" path )
      header "$REPO/$xpath" "$1" "$2"
      printf 'design for %s on %s\n' "$1" "$2" >> "$REPO/$xpath/design.md"
      git -C "$REPO" add -- "$xpath/design.md"
      git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm "docs($1): design" -- "$xpath/design.md" ;;
  esac
}

new_repo reuse
git -C "$REPO" checkout -qb master
printf 'x\n' > "$REPO/README"; commit_all "$REPO" base
git -C "$REPO" checkout -qb fix/flaky
first=$( start_item 2026-01-02 fix/flaky )
check 'reused branch: /start on day one records the dated id' "$first" 2026-01-02-flaky
design_pass "$first" fix/flaky
check 'reused branch: the first pass writes a fresh folder' "$( attr "$LINE" owner )" none "$LINE"
git -C "$REPO" checkout -q master
git -C "$REPO" -c user.name=t -c user.email=t@t merge -q --no-ff --no-edit fix/flaky > /dev/null
git -C "$REPO" branch -qD fix/flaky
cp "$REPO/docs/prs/2026-01-02-flaky/design.md" "$TMP/flaky-original.md"
git -C "$REPO" checkout -qb fix/flaky
second=$( start_item 2026-03-04 fix/flaky )
check 'reused branch: /start on a later day records a new dated id' "$second" 2026-03-04-flaky
check 'reused branch fixture: the old design is on the recreated branch' \
  "$( [ -f "$REPO/docs/prs/2026-01-02-flaky/design.md" ] && echo yes )" yes
design_pass "$second" fix/flaky
check 'reused branch on a later day: owner=none (a new folder, not a lookup)' "$( attr "$LINE" owner )" none "$LINE"
check 'reused branch on a later day: the new folder is the later date' "$( attr "$LINE" path )" docs/prs/2026-03-04-flaky "$LINE"
check 'reused branch on a later day: the old design.md is byte-unchanged' \
  "$( cmp -s "$TMP/flaky-original.md" "$REPO/docs/prs/2026-01-02-flaky/design.md" && echo same )" same
check 'reused branch on a later day: the new design was written beside it' \
  "$( grep -c 'design for 2026-03-04-flaky on fix/flaky' "$REPO/docs/prs/2026-03-04-flaky/design.md" 2>/dev/null )" 1

# THE ACCEPTED RESIDUAL: the same branch name deleted and recreated on the SAME
# day gets the same dated id, the header matches, and the verdict is self — an
# overwrite of the earlier same-day design. The date is the only discriminator
# and a day is its resolution; `/design` Step 4 states this beside the
# renamed-branch false stop. Asserted as the expected answer, not hidden.
git -C "$REPO" checkout -q master
git -C "$REPO" -c user.name=t -c user.email=t@t merge -q --no-ff --no-edit fix/flaky > /dev/null
git -C "$REPO" branch -qD fix/flaky
git -C "$REPO" checkout -qb fix/flaky
third=$( start_item 2026-03-04 fix/flaky )
wdp "$REPO" --item "$third" --owner-branch fix/flaky
check 'ACCEPTED RESIDUAL — same branch name recreated on the SAME day: owner=self' "$( attr "$LINE" owner )" self "$LINE"

# ---------------------------------------------------------------------------
printf '\nthe verdict line is the contract (ADR-004)\n'
# ---------------------------------------------------------------------------
new_repo wrapped
config '{"workDocsRoot": 5}'
# A wrapper that swallows the exit status — the shape of every piped or
# `|| true` call — must not turn an error into something a reader takes as a
# root. The line still says error, and still names no path.
( cd "$REPO" && "$WDP_SH" "$WDP" --item TV1-2400; true ) > "$OUT" 2>&1
rc=$?
LINE=$( verdict "$OUT" )
check 'a wrapper swallowing the exit status: exit reads 0' "$rc" 0
check 'a wrapper swallowing the exit status: the line still reads error' "$( attr "$LINE" outcome )" error "$LINE"
check_empty 'a wrapper swallowing the exit status: still no path=' "$( attr "$LINE" path )"

printf 'Traceback (most recent call last):\n' > "$TMP/crash"
check_empty 'a run that printed no verdict line parses as no verdict' "$( verdict "$TMP/crash" )"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
