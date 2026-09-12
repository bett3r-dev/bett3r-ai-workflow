#!/bin/sh
# Oracle for `bin/worktree-pool` — the git mechanics of /build's parallel slices.
#
# /build runs independent slices concurrently, each in its own worktree from a
# reusable pool, and lands each green commit on the task branch by cherry-pick.
# The judgment around that (what is ready, dependency order, when to escalate)
# is prose in commands/build.md; the mechanics are a script precisely so they
# can be executed here instead of reviewed. Every case below drives the real
# script against a throwaway git repository in a temp dir.
#
# The install/build commands are STUBS that append the working directory to a
# log outside the worktree. That is what lets the reset case prove they ran
# *unconditionally* — on a tree where nothing changed — rather than inferring it
# from a green exit. The log lives outside the worktree so the stub itself never
# leaves an untracked file for the dirty checks to trip on.
#
# Every subcommand is read by its verdict line (ADR-004), never by its exit
# code, and the final section wraps a conflicting land in a shell that swallows
# the exit status to show the line still says `conflict`.
#
# Run locally:  sh scripts/test-worktree-pool.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# POOL_SH selects the interpreter that runs the `bin/worktree-pool` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
POOL="$ROOT/plugins/bett3r-ai-workflow/bin/worktree-pool"
POOL_SH=${POOL_SH:-sh}

# `cd -P` so every path compared below is the one git itself reports: on macOS
# the temp dir is a symlink (/var → /private/var) and git prints the realpath.
TMP=$( mktemp -d "${TMPDIR:-/tmp}/worktree-pool-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fixture owns git's ambient configuration: no user or system gitconfig
# (a global `init.defaultBranch`, hooks path or signing rule would change what
# the repo looks like), and an identity set here so commits never depend on who
# runs the suite.
HOME="$TMP/home"; mkdir -p "$HOME"; export HOME
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=pool-test GIT_AUTHOR_EMAIL=pool@test GIT_COMMITTER_NAME=pool-test GIT_COMMITTER_EMAIL=pool@test
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE WORKTREE_POOL_INSTALL WORKTREE_POOL_BUILD

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
#
# An EMPTY expected value is refused: most expectations here are shas or
# attributes computed from an earlier step, and when that step never ran both
# sides are empty and "equal". That is how two of these checks (the land's
# `source=` and the dependent reset's `tip=`) went green against a script that
# did not exist. Assert emptiness with `check_empty`.
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

# check_empty <description> <actual> [context lines…]
check_empty(){
  if [ -z "$2" ]; then
    pass "$1"
  else
    d=$1 a=$2; shift 2
    fail "$d" 'expected: (empty)' "actual:   $a" "$@"
  fi
}

# pool <outfile> <args…> — run the launcher, stdout+stderr to a file, and keep
# its real exit status in $rc (never through a pipe).
pool(){
  out=$1; shift
  ( cd "$CWD" && "$POOL_SH" "$POOL" "$@" ) > "$out" 2>&1
  rc=$?
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^WORKTREE-POOL:v1 cmd=[a-z]+ outcome=[a-z-]+( [A-Za-z]+=[^ ]*)*$'
}

# attr <verdict-line> <key> — one attribute's value from a verdict line.
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

INSTALL_LOG="$TMP/install.log"
BUILD_LOG="$TMP/build.log"
STUB_INSTALL="pwd -P >> '$INSTALL_LOG'"
STUB_BUILD="pwd -P >> '$BUILD_LOG'"

g(){ git -C "$REPO" "$@"; }

# A task repo on branch `task`, with node_modules/ ignored — the shape of every
# host repo the pool will ever serve.
new_repo(){
  REPO="$TMP/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" checkout -q -b task
  printf 'node_modules/\n' > "$REPO/.gitignore"
  printf 'base\n' > "$REPO/base.txt"
  printf 'shared\n' > "$REPO/shared.txt"
  g add -A && g commit -q -m base
  CWD=$REPO
}

# commit_in <worktree> <file> <content> <message> — a worker's slice commit.
commit_in(){
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A && git -C "$1" commit -q -m "$4"
  git -C "$1" rev-parse HEAD
}

# ---------------------------------------------------------------------------
printf '\nsize — the pool is min(DAG width, --max-parallel, --pool-max); width 1 is no pool\n\n'
# ---------------------------------------------------------------------------
CWD=$TMP

# Width 1: a chain. Nothing is ever ready alongside anything else.
cat > "$TMP/w1.yaml" <<'Y'
ticket: T-1
slices:
  - id: 1
    name: "a"
    passes: false
    depends_on: []
  - id: 2
    passes: false
    depends_on: [1]
  - id: 3
    passes: false
    depends_on: [2]
Y
# Width 2: two roots, then a join. Block-style depends_on on purpose.
cat > "$TMP/w2.yaml" <<'Y'
slices:
  - id: 1
    depends_on: []
  - id: 2
    depends_on: []
  - id: 3
    depends_on:
      - 1
      - 2
Y
# Width 3: three roots.
cat > "$TMP/w3.yaml" <<'Y'
slices:
  - id: 1
    depends_on: []
  - id: 2
    depends_on: []
  - id: 3
    depends_on: []
  - id: 4
    depends_on: [1, 2, 3]
Y
# Width 6: six roots.
{ printf 'slices:\n'; for i in 1 2 3 4 5 6; do printf '  - id: %s\n    depends_on: []\n' "$i"; done; } > "$TMP/w6.yaml"

for case in 'w1.yaml|1|0' 'w2.yaml|2|2' 'w3.yaml|3|3'; do
  f=${case%%|*}; rest=${case#*|}; w=${rest%|*}; p=${rest#*|}
  pool "$TMP/out" size "$TMP/$f"
  v=$( verdict "$TMP/out" )
  check "size: width-$w DAG → pool $p (verdict line)" \
        "$( attr "$v" outcome ) width=$( attr "$v" width ) pool=$( attr "$v" pool )" \
        "ok width=$w pool=$p" "$( cat "$TMP/out" )"
done

pool "$TMP/out" size "$TMP/w6.yaml" --pool-max 4
v=$( verdict "$TMP/out" )
check 'size: --pool-max 4 caps a width-6 DAG to 4' "$( attr "$v" width )/$( attr "$v" pool )" '6/4' "$( cat "$TMP/out" )"

pool "$TMP/out" size "$TMP/w6.yaml" --max-parallel 5
v=$( verdict "$TMP/out" )
check 'size: no --pool-max → only --max-parallel caps (width 6, --max-parallel 5 → 5)' "$( attr "$v" pool )" '5' "$( cat "$TMP/out" )"

pool "$TMP/out" size "$TMP/w6.yaml"
v=$( verdict "$TMP/out" )
check 'size: neither cap → the pool is the width' "$( attr "$v" pool )" '6' "$( cat "$TMP/out" )"

pool "$TMP/out" size "$TMP/w6.yaml" --max-parallel 1
v=$( verdict "$TMP/out" )
check 'size: a cap of 1 is no pool, not a pool of one' "$( attr "$v" pool )" '0' "$( cat "$TMP/out" )"

# A slice already `passes: true` is done: its dependants are ready now.
cat > "$TMP/resume.yaml" <<'Y'
slices:
  - id: 1
    passes: true
    depends_on: []
  - id: 2
    passes: false
    depends_on: [1]
  - id: 3
    passes: false
    depends_on: [1]
Y
pool "$TMP/out" size "$TMP/resume.yaml"
v=$( verdict "$TMP/out" )
check 'size: passed slices are satisfied dependencies, not pool members' "$( attr "$v" width )/$( attr "$v" pool )" '2/2' "$( cat "$TMP/out" )"

# A passed slice is not a pool member. Two passed roots under one pending join:
# counted as pending they would be a width-2 antichain; satisfied, the plan is
# one slice wide and gets no pool.
cat > "$TMP/passed-roots.yaml" <<'Y'
slices:
  - id: 1
    passes: true
    depends_on: []
  - id: 2
    passes: true
    depends_on: []
  - id: 3
    passes: false
    depends_on: [1, 2]
Y
pool "$TMP/out" size "$TMP/passed-roots.yaml"
v=$( verdict "$TMP/out" )
check 'size: passed slices never count toward the width' "$( attr "$v" width )/$( attr "$v" pool )" '1/0' "$( cat "$TMP/out" )"

# Width is the largest set of slices that can be ready AT ONCE, not the largest
# topological wave. Waves here are {1,2,4} {3,5,7} {6} — 3 — but once 1, 2 and 3
# land, 4, 5, 6 and 7 are all ready together.
cat > "$TMP/antichain.yaml" <<'Y'
slices:
  - id: 1
    depends_on: []
  - id: 2
    depends_on: []
  - id: 3
    depends_on: [1]
  - id: 4
    depends_on: []
  - id: 5
    depends_on: [2]
  - id: 6
    depends_on: [3]
  - id: 7
    depends_on: [1]
Y
pool "$TMP/out" size "$TMP/antichain.yaml"
v=$( verdict "$TMP/out" )
check 'size: width is the largest set ready at once (4), not the largest wave (3)' "$( attr "$v" width )" '4' "$( cat "$TMP/out" )"

# --only: a targeted /build sizes the slices it will run, not the whole plan.
pool "$TMP/out" size "$TMP/w3.yaml" --only 3
v=$( verdict "$TMP/out" )
check 'size --only: one targeted slice of a width-3 plan is no pool' "$( attr "$v" outcome ) $( attr "$v" width )/$( attr "$v" pool )" 'ok 1/0' "$( cat "$TMP/out" )"
pool "$TMP/out" size "$TMP/w3.yaml" --only 1,2
v=$( verdict "$TMP/out" )
check 'size --only: two independent targets size a pool of 2' "$( attr "$v" width )/$( attr "$v" pool )" '2/2' "$( cat "$TMP/out" )"
pool "$TMP/out" size "$TMP/w3.yaml" --only 4
v=$( verdict "$TMP/out" )
check 'size --only: a target whose pending dependency is outside the set is an error' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'error reason=unmet-dependency-outside-only' "$( cat "$TMP/out" )"
pool "$TMP/out" size "$TMP/w3.yaml" --only 9
v=$( verdict "$TMP/out" )
check 'size --only: an id the plan does not have is an error' "$( attr "$v" outcome )" 'error' "$( cat "$TMP/out" )"

# Fail loud: a cycle has no width, and a guess would size a pool for a plan that cannot run.
printf 'slices:\n  - id: 1\n    depends_on: [2]\n  - id: 2\n    depends_on: [1]\n' > "$TMP/cycle.yaml"
pool "$TMP/out" size "$TMP/cycle.yaml"
v=$( verdict "$TMP/out" )
check 'size: a dependency cycle is an error verdict, not a width' "$( attr "$v" outcome )" 'error' "$( cat "$TMP/out" )"

# ---------------------------------------------------------------------------
printf '\nprovision + reset — detached at the tip, untracked gone, node_modules kept, install+build always\n\n'
# ---------------------------------------------------------------------------
new_repo repo-a
TIP=$( g rev-parse task )

pool "$TMP/out" provision 2 --root "$TMP/pool-a"
v=$( verdict "$TMP/out" )
check 'provision: verdict provisioned n=2' "$( attr "$v" outcome ) n=$( attr "$v" n )" 'provisioned n=2' "$( cat "$TMP/out" )"
WT1="$TMP/pool-a/wt-1"; WT2="$TMP/pool-a/wt-2"
check 'provision: both worktrees registered with the repo' \
      "$( g worktree list --porcelain | grep -c "^worktree $TMP/pool-a/wt-" )" '2'
check 'provision: the main checkout stays on the task branch' "$( g symbolic-ref --short HEAD )" 'task'

# Resume: provisioning again over the same root reuses the registered trees.
pool "$TMP/out" provision 2 --root "$TMP/pool-a"
v=$( verdict "$TMP/out" )
check 'provision: a second provision over the same root is provisioned, not failed' "$( attr "$v" outcome )" 'provisioned' "$( cat "$TMP/out" )"
check 'provision: it reports both trees as reused' "$( grep -c '^reused ' "$TMP/out" )" '2'
check 'provision: and adds no third worktree' "$( g worktree list --porcelain | grep -c "^worktree $TMP/pool-a/wt-" )" '2'

# But never reuse a tree that holds work. A slice that escalated at the gate
# leaves only files, teardown refuses to remove them — and a re-run /build must
# not then "reuse" that tree, because the provisioner's reset would clean it.
printf 'wip\n' > "$WT1/escalated.ts"
pool "$TMP/out" provision 2 --root "$TMP/pool-a"
v=$( verdict "$TMP/out" )
check 'provision: refuses to reuse a worktree holding untracked work' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=reused-worktree-holds-work' "$( cat "$TMP/out" )"
check 'provision: the refusal names the worktree' "$( attr "$v" path )" "$WT1"
check 'provision: and the untracked work survives' "$( cat "$WT1/escalated.ts" 2>/dev/null )" 'wip'
rm -f "$WT1/escalated.ts"

# A plain directory where a worktree should go is somebody else's, never overwritten.
mkdir -p "$TMP/pool-x/wt-1" && printf 'mine\n' > "$TMP/pool-x/wt-1/keep.txt"
pool "$TMP/out" provision 1 --root "$TMP/pool-x"
v=$( verdict "$TMP/out" )
check 'provision: refuses a path that exists and is not a worktree' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=path-exists-not-a-worktree' "$( cat "$TMP/out" )"
check 'provision: and leaves what was there' "$( cat "$TMP/pool-x/wt-1/keep.txt" 2>/dev/null )" 'mine'

# Dirty the worktree the way a finished slice leaves it: a stray untracked file,
# and an ignored node_modules/ that must survive (it is the expensive part).
mkdir -p "$WT1/node_modules/dep" && printf 'x\n' > "$WT1/node_modules/dep/index.js"
printf 'junk\n' > "$WT1/stray.txt"
: > "$INSTALL_LOG"; : > "$BUILD_LOG"

pool "$TMP/out" reset "$WT1" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
v=$( verdict "$TMP/out" )
check 'reset: verdict reset' "$( attr "$v" outcome )" 'reset' "$( cat "$TMP/out" )"
check 'reset: the worktree is detached' \
      "$( [ -d "$WT1/.git" ] || [ -f "$WT1/.git" ] || { printf no-worktree; exit; }; git -C "$WT1" symbolic-ref -q HEAD || printf detached )" 'detached'
check 'reset: HEAD is the task-branch tip' "$( git -C "$WT1" rev-parse HEAD )" "$TIP"
check 'reset: the verdict names the tip it took' "$( attr "$v" tip )" "$TIP"
check 'reset: the stray untracked file is gone' "$( [ -e "$WT1/stray.txt" ] && printf present || printf gone )" 'gone'
check 'reset: the ignored node_modules/ survives' "$( cat "$WT1/node_modules/dep/index.js" 2>/dev/null )" 'x'
check 'reset: install ran, in the worktree, with nothing changed' "$( cat "$INSTALL_LOG" )" "$WT1"
check 'reset: build ran, in the worktree, with nothing changed' "$( cat "$BUILD_LOG" )" "$WT1"

# Unconditional means the SECOND reset on an identical tree runs them again.
pool "$TMP/out" reset "$WT1" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
check 'reset: a repeat reset on an unchanged tree installs and builds again' \
      "$( wc -l < "$INSTALL_LOG" | tr -d ' ' )/$( wc -l < "$BUILD_LOG" | tr -d ' ' )" '2/2' "$( cat "$TMP/out" )"

# The commands are the host repo's, so the script has none of its own.
pool "$TMP/out" reset "$WT1" task
v=$( verdict "$TMP/out" )
check 'reset: without --install/--build it refuses to guess a package manager' "$( attr "$v" outcome )" 'error' "$( cat "$TMP/out" )"

# A failing build is a verdict, not a silent ready tree.
pool "$TMP/out" reset "$WT1" task --install "$STUB_INSTALL" --build 'exit 3'
v=$( verdict "$TMP/out" )
check 'reset: a failing build reports failed step=build' "$( attr "$v" outcome ) step=$( attr "$v" step )" 'failed step=build' "$( cat "$TMP/out" )"

# A tracked edit is work the switch would discard.
printf 'edited\n' > "$WT1/base.txt"
pool "$TMP/out" reset "$WT1" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
v=$( verdict "$TMP/out" )
check 'reset: refuses a worktree with tracked modifications' "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=dirty' "$( cat "$TMP/out" )"
check 'reset: and the tracked edit survives the refusal' "$( cat "$WT1/base.txt" )" 'edited'
printf 'base\n' > "$WT1/base.txt"

# ---------------------------------------------------------------------------
printf '\nland — cherry-picked onto the task branch in the order given; a conflict leaves it untouched\n\n'
# ---------------------------------------------------------------------------
pool "$TMP/out" reset "$WT2" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
S1=$( commit_in "$WT1" s1.txt one 'slice 1' )
S2=$( commit_in "$WT2" s2.txt two 'slice 2' )
TIP0=$( g rev-parse task )

# The worker names the worktree and the sha; a sha that is not that worktree's
# is a wrong report, and landing it would land the wrong slice.
pool "$TMP/out" land "$WT1" "$S2" --base "$TIP0"
v=$( verdict "$TMP/out" )
check 'land: refuses a sha that is not in the named worktree' "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=sha-not-in-worktree' "$( cat "$TMP/out" )"
check 'land: the refused land moved nothing' "$( g rev-parse task )" "$TIP0"

# Tracked edits in the main checkout would be swept into the cherry-pick.
printf 'main edit\n' > "$REPO/base.txt"
pool "$TMP/out" land "$WT1" "$S1" --base "$TIP0"
v=$( verdict "$TMP/out" )
check 'land: refuses while the main checkout has tracked modifications' "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=main-checkout-dirty' "$( cat "$TMP/out" )"
check 'land: the dirty-main refusal moved nothing' "$( g rev-parse task )" "$TIP0"
printf 'base\n' > "$REPO/base.txt"

# Untracked files in the main checkout (the orchestrator's scratch) are accepted.
printf 'scratch\n' > "$REPO/notes.tmp"

pool "$TMP/out" land "$WT1" "$S1" --base "$TIP0"
v=$( verdict "$TMP/out" )
L1=$( attr "$v" sha )
check 'land: slice 1 verdict landed' "$( attr "$v" outcome )" 'landed' "$( cat "$TMP/out" )"
check 'land: a first land of a real commit after base is already=false' "$( attr "$v" already )" 'false' "$( cat "$TMP/out" )"
check 'land: the verdict sha is the task-branch tip (the LANDED sha, not the worker sha)' "$L1" "$( g rev-parse task )"
check 'land: the verdict names the worker commit it came from' "$( attr "$v" source )" "$S1"

pool "$TMP/out" land "$WT2" "$S2" --base "$TIP0"
v=$( verdict "$TMP/out" )
L2=$( attr "$v" sha )
check 'land: slice 2 verdict landed' "$( attr "$v" outcome )" 'landed' "$( cat "$TMP/out" )"
check 'land: the branch holds both, in the order landed' "$( g log --format=%s -n 2 task | tr '\n' ',' )" 'slice 2,slice 1,'
check 'land: slice 2 was applied on top of slice 1' "$( g rev-parse "$L2^" )" "$L1"
check 'land: both files are on the branch' "$( g show task:s1.txt )+$( g show task:s2.txt )" 'one+two'
check 'land: an untracked file in the main checkout did not stop the lands' "$( cat "$REPO/notes.tmp" )" 'scratch'
rm -f "$REPO/notes.tmp"

# Resume: a crash between the land and `passes: true` re-lands the same sha.
# That must read as landed, naming the commit already on the branch — slice 2's
# landed sha differs from its worker sha, so this is the patch-equivalence path.
TIP2=$( g rev-parse task )
pool "$TMP/out" land "$WT2" "$S2" --base "$TIP0"
v=$( verdict "$TMP/out" )
check 'land: re-landing an already-landed sha is landed already=true' \
      "$( attr "$v" outcome ) already=$( attr "$v" already )" 'landed already=true' "$( cat "$TMP/out" )"
check 'land: the re-land names the equivalent commit on the branch' "$( attr "$v" sha )" "$L2"
check 'land: the re-land moved nothing' "$( g rev-parse task )" "$TIP2"
pool "$TMP/out" land "$WT1" "$S1" --base "$TIP0"
v=$( verdict "$TMP/out" )
check 'land: re-landing slice 1 names its landed sha' "$( attr "$v" outcome ) $( attr "$v" sha )" "landed $L1" "$( cat "$TMP/out" )"

# A dependent slice: its worktree reset takes the tip AFTER the parent landed.
pool "$TMP/out" reset "$WT1" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
v=$( verdict "$TMP/out" )
check "a dependent slice's reset takes the tip after its parent landed" "$( attr "$v" tip )" "$L2" "$( cat "$TMP/out" )"
check "the parent's file is present in the dependent's worktree" "$( cat "$WT1/s2.txt" 2>/dev/null )" 'two'

# A worker that never committed: its HEAD is still the reset tip. Landing that
# (or anything older) must not read as already landed — it would mark an
# unbuilt slice passed. --base is the reset tip; only a sha strictly after it lands.
printf 'wip\n' > "$WT1/uncommitted.ts"
pool "$TMP/out" land "$WT1" "$L2" --base "$L2"
v=$( verdict "$TMP/out" )
check 'land: refuses a sha equal to the reset base (the worker never committed)' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=sha-not-after-base' "$( cat "$TMP/out" )"
check 'land: the equal-to-base refusal moved nothing' "$( g rev-parse task )" "$L2"
pool "$TMP/out" land "$WT1" "$L1" --base "$L2"
v=$( verdict "$TMP/out" )
check 'land: refuses a sha that is an ancestor of the reset base' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=sha-not-after-base' "$( cat "$TMP/out" )"
check 'land: the ancestor refusal moved nothing' "$( g rev-parse task )" "$L2"
pool "$TMP/out" land "$WT1" "$L2"
v=$( verdict "$TMP/out" )
check 'land: without --base it is a usage error, never a guess' "$( attr "$v" outcome )" 'error' "$( cat "$TMP/out" )"
rm -f "$WT1/uncommitted.ts"

# Conflict: two workers edit the same line from the same tip.
pool "$TMP/out" reset "$WT2" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
C1=$( commit_in "$WT1" shared.txt 'from worker one' 'slice 3' )
C2=$( commit_in "$WT2" shared.txt 'from worker two' 'slice 4' )
pool "$TMP/out" land "$WT1" "$C1" --base "$L2"
BEFORE=$( g rev-parse task )
pool "$TMP/out" land "$WT2" "$C2" --base "$L2"
LAND_RC=$rc
v=$( verdict "$TMP/out" )
check 'land: a conflicting commit reports conflict' "$( attr "$v" outcome )" 'conflict' "$( cat "$TMP/out" )"
check 'land: the conflict verdict names the path' "$( attr "$v" paths )" 'shared.txt'
check 'land: the task-branch tip is unchanged' "$( g rev-parse task )" "$BEFORE"
check 'land: the cherry-pick was aborted (no CHERRY_PICK_HEAD)' \
      "$( g rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null && printf in-progress || printf aborted )" 'aborted'
check_empty 'land: the main checkout is left clean' "$( g status --porcelain )"
check 'land: a conflict also exits non-zero (cross-check, not the contract)' "$( [ "$LAND_RC" -ne 0 ] && printf nonzero || printf zero )" 'nonzero'

# ---------------------------------------------------------------------------
printf '\nteardown — refuses while a worktree holds an unlanded commit\n\n'
# ---------------------------------------------------------------------------
pool "$TMP/out" teardown --root "$TMP/pool-a"
v=$( verdict "$TMP/out" )
check 'teardown: refused while wt-2 holds the unlanded conflicting commit' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=unlanded' "$( cat "$TMP/out" )"
check 'teardown: the refusal names the worktree' "$( attr "$v" worktrees )" "$WT2"
check 'teardown: nothing was removed on refusal' "$( g worktree list --porcelain | grep -c "^worktree $TMP/pool-a/wt-" )" '2'

# The same tree must not be reused by a re-run either: its commit is work too.
pool "$TMP/out" provision 2 --root "$TMP/pool-a"
v=$( verdict "$TMP/out" )
check 'provision: refuses to reuse a worktree holding an unlanded commit' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=reused-worktree-holds-work' "$( cat "$TMP/out" )"
check 'provision: the unlanded refusal names that worktree' "$( attr "$v" path )" "$WT2"

# The reset that would discard it refuses too: the unlanded commit is real work.
pool "$TMP/out" reset "$WT2" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
v=$( verdict "$TMP/out" )
check 'reset: refuses a worktree holding an unlanded commit' "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=unlanded' "$( cat "$TMP/out" )"

# The success half, on a fresh repo whose one worker commit CAN land: refused
# before the land, removed after it.
new_repo repo-b
BB=$( g rev-parse task )
pool "$TMP/out" provision 1 --root "$TMP/pool-b"
WTB="$TMP/pool-b/wt-1"
pool "$TMP/out" reset "$WTB" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
SB=$( commit_in "$WTB" b.txt bee 'slice b' )
pool "$TMP/out" teardown --root "$TMP/pool-b"
v=$( verdict "$TMP/out" )
check 'teardown: refused before the commit landed' "$( attr "$v" outcome )" 'refused' "$( cat "$TMP/out" )"
pool "$TMP/out" land "$WTB" "$SB" --base "$BB"
check 'teardown: (precondition) the pool worktree is registered before teardown' \
      "$( g worktree list --porcelain | grep -c "^worktree $TMP/pool-b/" )" '1'
pool "$TMP/out" teardown --root "$TMP/pool-b"
v=$( verdict "$TMP/out" )
check 'teardown: succeeds once every commit landed' "$( attr "$v" outcome ) n=$( attr "$v" n )" 'removed n=1' "$( cat "$TMP/out" )"
check 'teardown: the worktree is no longer registered' "$( g worktree list --porcelain | grep -c "^worktree $TMP/pool-b/" )" '0'
check 'teardown: the pool directory is gone' "$( [ -e "$TMP/pool-b" ] && printf present || printf gone )" 'gone'
check 'teardown: the landed commit is still on the branch' "$( g show task:b.txt )" 'bee'

# A slice that escalated at the gate has NO commit — only files. A new-files-only
# slice is untracked through and through, and it must survive teardown too.
new_repo repo-d
pool "$TMP/out" provision 1 --root "$TMP/pool-d"
WTD="$TMP/pool-d/wt-1"
pool "$TMP/out" reset "$WTD" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
mkdir -p "$WTD/src" && printf 'export const f = 1\n' > "$WTD/src/feature.ts"
pool "$TMP/out" teardown --root "$TMP/pool-d"
v=$( verdict "$TMP/out" )
check 'teardown: refuses a worktree holding only untracked files' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=dirty' "$( cat "$TMP/out" )"
check 'teardown: the untracked-only refusal names the worktree' "$( attr "$v" worktrees )" "$WTD"
check 'teardown: the escalated slice'\''s new file survives' "$( cat "$WTD/src/feature.ts" 2>/dev/null )" 'export const f = 1'
rm -rf "$WTD/src"
printf 'edited\n' > "$WTD/base.txt"
pool "$TMP/out" teardown --root "$TMP/pool-d"
v=$( verdict "$TMP/out" )
check 'teardown: refuses a worktree with tracked modifications' \
      "$( attr "$v" outcome ) reason=$( attr "$v" reason )" 'refused reason=dirty' "$( cat "$TMP/out" )"
printf 'base\n' > "$WTD/base.txt"
pool "$TMP/out" teardown --root "$TMP/pool-d"
v=$( verdict "$TMP/out" )
check 'teardown: removes it once clean' "$( attr "$v" outcome )" 'removed' "$( cat "$TMP/out" )"

# ---------------------------------------------------------------------------
printf '\nverdict lines — parse for every subcommand; a swallowed exit code cannot fake a pass\n\n'
# ---------------------------------------------------------------------------
new_repo repo-c
BC=$( g rev-parse task )
pool "$TMP/out" provision 2 --root "$TMP/pool-c"
check 'provision prints a parseable verdict line' "$( verdict "$TMP/out" >/dev/null && printf ok )" 'ok' "$( cat "$TMP/out" )"
WC1="$TMP/pool-c/wt-1"; WC2="$TMP/pool-c/wt-2"
pool "$TMP/out" reset "$WC1" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
check 'reset prints a parseable verdict line' "$( verdict "$TMP/out" >/dev/null && printf ok )" 'ok' "$( cat "$TMP/out" )"
pool "$TMP/out" reset "$WC2" task --install "$STUB_INSTALL" --build "$STUB_BUILD"
X1=$( commit_in "$WC1" shared.txt 'x one' 'x1' )
X2=$( commit_in "$WC2" shared.txt 'x two' 'x2' )
pool "$TMP/out" land "$WC1" "$X1" --base "$BC"
check 'land prints a parseable verdict line' "$( verdict "$TMP/out" >/dev/null && printf ok )" 'ok' "$( cat "$TMP/out" )"
pool "$TMP/out" teardown --root "$TMP/pool-c"
check 'teardown prints a parseable verdict line' "$( verdict "$TMP/out" >/dev/null && printf ok )" 'ok' "$( cat "$TMP/out" )"
pool "$TMP/out" size "$TMP/w2.yaml"
check 'size prints a parseable verdict line' "$( verdict "$TMP/out" >/dev/null && printf ok )" 'ok' "$( cat "$TMP/out" )"

# The wrapper: exit status forced to 0, as `… | tail` or `cmd; echo done` would.
( cd "$REPO" && "$POOL_SH" -c '"$1" land "$2" "$3" --base "$4"; exit 0' wrap "$POOL" "$WC2" "$X2" "$BC" ) > "$TMP/wrapped" 2>&1
WRAP_RC=$?
v=$( verdict "$TMP/wrapped" )
check 'wrapper: the wrapper really did swallow the exit code' "$WRAP_RC" '0'
check 'wrapper: the verdict line still reads conflict' "$( attr "$v" outcome )" 'conflict' "$( cat "$TMP/wrapped" )"
case "$( attr "$v" outcome )" in
  landed) fail 'wrapper: a reader of the line does not see a landing' 'outcome=landed under a swallowed conflict' ;;
  *) pass 'wrapper: a reader of the line does not see a landing' ;;
esac

# And no verdict at all is never a pass: output from something that is not the
# pool (here, a crash before any line) yields no parseable line.
printf 'Traceback (most recent call last):\n' > "$TMP/crash"
check_empty 'a run that printed no verdict line parses as no verdict' "$( verdict "$TMP/crash" )"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
