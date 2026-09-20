#!/bin/sh
# Oracle for `bin/fleet-loop` — the driver that re-invokes one fresh
# orchestrator tick per wave (GH-429-F2).
#
# /start-multi yields at a wave boundary with a `FLEET-STEP:v1 … waves=k/N`
# line, and something outside every context has to decide whether to tick
# again. That decision is the whole of this script: `k < N` ticks again, `k = N`
# ends the run, and `k` unchanged across two consecutive ticks stops with
# `blocked-on=fleet-no-progress` — the guard `agents/unit-lane.md:62-72` already
# specifies one level down for /build's slice yield.
#
# The tick command is a STUB here: a shell snippet that appends its invocation
# number to a log outside the run dir and prints a scripted verdict line. The
# log is what proves *how many times* the driver ticked, which is the only way
# to tell "ended because k = N" from "ended because it stopped early" — an exit
# status cannot distinguish them.
#
# Every case reads the driver's own decision from its output, never from the
# exit status alone, and the no-verdict case exists because ADR-004 makes the
# line's ABSENCE the `infra` signal: a tick that was OOM-killed mid-wave exits 0
# from the shell's point of view and must never read as a wave that advanced.
#
# Run locally:  sh scripts/test-fleet-loop.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# FLEET_SH selects the interpreter that runs the `bin/fleet-loop` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
LOOP="$PLUGIN/bin/fleet-loop"
FLEET_SH=${FLEET_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/fleet-loop-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fixture owns anything ambient the driver might read: a stub tick inherits
# this environment, and a stray FLEET_* from the caller's shell would change
# what the driver decides without changing this file.
unset FLEET_LOOP_TICK FLEET_LOOP_RUN
HOME="$TMP/home"; mkdir -p "$HOME"; export HOME

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
# An empty expected value is refused for the same reason it is in
# scripts/test-worktree-pool.sh: most expectations here are counts read back
# from a file the driver was supposed to cause, and when the driver never ran
# both sides are empty and "equal".
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

# says <description> <file> <literal> — the driver's output carries this text.
says(){
  if grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    d=$1 f=$2 l=$3
    fail "$d" "expected output to contain: $l" 'actual output:' "$( cat "$f" )"
  fi
}

# says_not <description> <file> <literal>
says_not(){
  if grep -qF -- "$3" "$2"; then
    d=$1 f=$2 l=$3
    fail "$d" "expected output NOT to contain: $l" 'actual output:' "$( cat "$f" )"
  else
    pass "$1"
  fi
}

# The version the driver must agree with: the manifest of the plugin the
# launcher itself belongs to. Read from the manifest, not written here, so this
# suite does not need editing on every version bump.
VERSION=$( sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
           "$PLUGIN/.claude-plugin/plugin.json" | head -n 1 )

# new_run <name> — a RESUMED run's dir: a run.yaml as a tick before this one left
# it, carrying no `pluginVersion`. Nothing here synthesizes that key, and that is
# deliberate: the only producer of it is the orchestrator's step 0, so a fixture
# that wrote it itself would pin the driver against a file shape no producer
# emits — which is exactly what hid the defect this slice fixes. The stub tick
# writes it, the way the contract says the orchestrator does (see STUB below).
new_run(){
  RUN="$TMP/$1"
  mkdir -p "$RUN"
  { printf 'runId: multi-A-B\n'
    printf 'integrationBranch: int/multi-A-B\n'
    printf 'units:\n  - { id: A, wave: 0 }\n'
  } > "$RUN/run.yaml"
  STUB_RUN=$RUN
}

# new_fresh_run <name> — a FRESH run: the dir exists, `run.yaml` does NOT. This
# is the real t0 state, because the orchestrator creates run.yaml in its own step
# 0, during tick 1. The driver must be able to start here.
new_fresh_run(){
  RUN="$TMP/$1"
  mkdir -p "$RUN"
  rm -f "$RUN/run.yaml"
  STUB_RUN=$RUN
}

# The stub tick: one shell snippet for every case, scripted by a file of verdict
# lines. Invocation n prints line n (or the last line, repeated, when the script
# is shorter than the run). It logs every invocation to a file OUTSIDE the run
# dir so the count survives anything the driver does to the run dir.
#
# It also does the one thing the orchestrator's step 0 does that this driver
# depends on: it records `pluginVersion` in run.yaml from "its own loaded
# manifest" — every tick, resume included, creating run.yaml when the run is
# fresh. That is the contract in commands/start-multi.md step 0, and the stub
# standing in for the orchestrator has to honour it or the fixture is testing a
# file shape nothing produces. `$VERSIONS` line n overrides what tick n records
# (`none` = records nothing, a DRIFTED orchestrator).
TICK_LOG="$TMP/ticks.log"
SCRIPTED="$TMP/scripted"
VERSIONS="$TMP/versions"
STUB_RUN=""
cat > "$TMP/stub-tick.sh" <<'STUB'
n=$( wc -l < "$TICK_LOG" | tr -d ' ' )
n=$(( n + 1 ))
printf 'tick\n' >> "$TICK_LOG"
total=$( wc -l < "$SCRIPTED" | tr -d ' ' )
[ "$n" -gt "$total" ] && n=$total
# Step 0, as start-multi.md specifies it: rewrite pluginVersion whole, every tick.
v=$( sed -n "${n}p" "$VERSIONS" )
[ -n "$v" ] || v=$STUB_VERSION
if [ "$v" != none ]; then
  [ -f "$STUB_RUN/run.yaml" ] || {
    printf 'runId: multi-A-B\nintegrationBranch: int/multi-A-B\nunits:\n  - { id: A, wave: 0 }\n' \
      > "$STUB_RUN/run.yaml"
  }
  grep -v '^pluginVersion:' "$STUB_RUN/run.yaml" > "$STUB_SCRATCH"
  { printf 'runId: multi-A-B\n'; printf 'pluginVersion: %s\n' "$v"
    grep -v '^runId:' "$STUB_SCRATCH"; } > "$STUB_RUN/run.yaml"
fi
printf 'orchestrator prose: reconciled units, pushed branches\n'
sed -n "${n}p" "$SCRIPTED"
STUB
STUB_SCRATCH="$TMP/runyaml.scratch"
STUB_VERSION=$VERSION
export TICK_LOG SCRIPTED VERSIONS STUB_RUN STUB_SCRATCH STUB_VERSION
STUB_TICK="sh '$TMP/stub-tick.sh'"

# arm <line…> — reset the invocation log and script one output per tick. Also
# resets the recorded-version script, so every case records the REAL version
# unless it says otherwise: the version guard then stays out of the way of the
# wave-count cases, which is the only reason they can be read as being about k.
arm(){
  : > "$TICK_LOG"
  : > "$SCRIPTED"
  : > "$VERSIONS"
  STUB_VERSION=$VERSION
  for l in "$@"; do printf '%s\n' "$l" >> "$SCRIPTED"; done
}

# records <version-per-tick…> — what the stub orchestrator writes on each tick.
records(){ : > "$VERSIONS"; for v in "$@"; do printf '%s\n' "$v" >> "$VERSIONS"; done; }

ticks(){ wc -l < "$TICK_LOG" | tr -d ' '; }

# loop <outfile> <args…> — run the launcher, stdout+stderr to a file, real exit
# status in $rc (never through a pipe).
loop(){
  out=$1; shift
  "$FLEET_SH" "$LOOP" "$@" > "$out" 2>&1
  rc=$?
}

# ---------------------------------------------------------------------------
printf '\nk advanced — a short wave count ticks again, and k = N ends the run\n\n'
# ---------------------------------------------------------------------------
new_run run-a
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7' \
    'FLEET-STEP:v1 outcome=success waves=3/3 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a 3-wave run invoked the tick command exactly three times' "$( ticks )" '3' "$( cat "$TMP/out" )"
check 'and exited 0' "$rc" '0' "$( cat "$TMP/out" )"
says 'the driver reports the run terminal at waves=3/3' "$TMP/out" 'waves=3/3'
says_not 'k = N did not tick a fourth time (no no-progress stop either)' "$TMP/out" 'fleet-no-progress'

# A run already at its last wave ends after one tick: the terminal test is
# `k = N`, not "at least two ticks".
new_run run-a1
arm 'FLEET-STEP:v1 outcome=success waves=3/3 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a run that reaches k = N on the first tick ends there' "$( ticks )" '1' "$( cat "$TMP/out" )"
check 'and exits 0' "$rc" '0' "$( cat "$TMP/out" )"

# ---------------------------------------------------------------------------
printf '\nk did not advance — the no-progress guard, one level up from build-no-progress\n\n'
# ---------------------------------------------------------------------------
new_run run-b
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a wave that does not advance stops after the SECOND tick — no third' "$( ticks )" '2' "$( cat "$TMP/out" )"
says 'the stop names blocked-on=fleet-no-progress' "$TMP/out" 'blocked-on=fleet-no-progress'
says 'and quotes both verdict lines, as unit-lane requires' "$TMP/out" 'waves=1/3'
check 'a no-progress stop is non-zero (cross-check, not the contract)' \
      "$( [ "$rc" -ne 0 ] && printf nonzero || printf zero )" 'nonzero' "$( cat "$TMP/out" )"

# The guard compares k, not the whole line: a tick that advances the unit count
# while the wave stands still is still no progress at the wave boundary.
new_run run-b1
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=1/3 units=4/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'k unchanged with units= advancing is still no progress' "$( ticks )" '2' "$( cat "$TMP/out" )"
says 'and it says so' "$TMP/out" 'blocked-on=fleet-no-progress'

# A k that oscillates advances at every comparison, so the no-progress guard
# never fires on it: N waves bound the ticks a healthy run needs, and the cap is
# the termination floor under the guard, not a substitute for it.
new_run run-b2
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=4/7' \
    'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'an oscillating k is capped at N ticks, not looped forever' "$( ticks )" '3' "$( cat "$TMP/out" )"
says 'and the cap stop names itself' "$TMP/out" 'blocked-on=fleet-tick-cap'

# ---------------------------------------------------------------------------
printf '\nno verdict line — infra by absence (ADR-004), never a silent success\n\n'
# ---------------------------------------------------------------------------
new_run run-c
arm 'I finished the wave, everything looks good.' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a tick that printed no verdict line does not tick again' "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'and reports infra by the line'\''s absence' "$TMP/out" 'outcome=infra'
check 'an infra stop is non-zero' "$( [ "$rc" -ne 0 ] && printf nonzero || printf zero )" 'nonzero' "$( cat "$TMP/out" )"
says_not 'an infra tick is never reported as a wave that advanced' "$TMP/out" 'terminal'

# The parse rule is the shipped one: a verdict line that is not the LAST line is
# no verdict (lane-step-parse.py's last-line-only clause), so it is infra too.
new_run run-c1
# Its own stub: this case needs TWO lines out of one tick, which the scripted
# one-line-per-tick stub above cannot express.
cat > "$TMP/stub-trailing-prose.sh" <<'STUB'
printf 'tick\n' >> "$TICK_LOG"
# Step 0's write, as the scripted stub does it: an orchestrator that honours its
# contract and still prints an unparseable transcript is the case under test.
grep -v '^pluginVersion:' "$STUB_RUN/run.yaml" > "$STUB_SCRATCH"
{ printf 'pluginVersion: %s\n' "$STUB_VERSION"; cat "$STUB_SCRATCH"; } > "$STUB_RUN/run.yaml"
printf 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7\n'
printf 'and one more thought afterwards\n'
STUB
: > "$TICK_LOG"
loop "$TMP/out" --run "$RUN" --tick "sh '$TMP/stub-trailing-prose.sh'"
check 'a verdict line followed by prose is no verdict, so one tick only' "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'and it reads as infra, through the shipped parser' "$TMP/out" 'outcome=infra'

# A tick whose outcome is not success is not the driver's to retry: the run's
# own rules apply, and the driver stops.
new_run run-c2
arm 'FLEET-STEP:v1 outcome=failed waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a non-success outcome stops the driver after one tick' "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'and the stop names the outcome it read' "$TMP/out" 'outcome=failed'

# ---------------------------------------------------------------------------
printf '\nplugin version — the driver refuses a run recorded against another version (risk 4)\n\n'
# ---------------------------------------------------------------------------
# The check is AFTER a tick, never before one, and the structural reason is the
# whole shape of this section: nothing has loaded the plugin at t0, and on a fresh
# run `run.yaml` does not exist yet, so the driver cannot know the version from
# outside. Only the orchestrator can — it IS the loaded plugin.
new_run run-d
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7'
records 0.1.0
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a version mismatch refuses AFTER the first tick, and ticks no second time' \
      "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'the refusal names the version it resolved' "$TMP/out" "resolved=$VERSION"
says 'and the version the tick recorded' "$TMP/out" 'recorded=0.1.0'
check 'a refusal is non-zero' "$( [ "$rc" -ne 0 ] && printf nonzero || printf zero )" 'nonzero' "$( cat "$TMP/out" )"

# The positive control for that guard: the matching version ticks on, and the
# resolved version is printed every tick, not only on refusal.
new_run run-d1
arm 'FLEET-STEP:v1 outcome=success waves=1/2 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/2 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'the matching version ticks through to the end' "$( ticks )" '2' "$( cat "$TMP/out" )"
check 'and exits 0' "$rc" '0' "$( cat "$TMP/out" )"
says 'and each tick prints the resolved plugin version' "$TMP/out" "resolved=$VERSION"

# THE PERMISSIVE ARM. A resumed run that predates the key records no
# pluginVersion until its next tick's step 0 writes one, and a refusal here is
# what would make the driver refuse every real run: nothing can be compared
# before anything has loaded the plugin. So tick 1 proceeds, says so, and the
# guard is live from tick 2 — absent-then-self-heal, with no backfill, because a
# guessed value would make recorded == resolved and turn the guard into a false
# pass.
new_run run-d2
arm 'FLEET-STEP:v1 outcome=success waves=1/2 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/2 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a run.yaml with no pluginVersion at t0 still ticks (nothing to compare yet)' \
      "$( ticks )" '2' "$( cat "$TMP/out" )"
check 'and the run reaches its end' "$rc" '0' "$( cat "$TMP/out" )"
says 'and the driver says it proceeded rather than compared' "$TMP/out" 'records no pluginVersion yet'
says_not 'the permissive arm is not a refusal' "$TMP/out" 'refused'

# A FRESH run: no run.yaml on disk at all, which is the real t0 — the
# orchestrator creates it in step 0, during tick 1. USAGE here would mean the
# driver could never start a fresh run.
new_fresh_run run-d3
arm 'FLEET-STEP:v1 outcome=success waves=1/2 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/2 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a run dir with no run.yaml at t0 is a FRESH run, and the driver starts it' \
      "$( ticks )" '2' "$( cat "$TMP/out" )"
check 'and it is not a usage error' "$rc" '0' "$( cat "$TMP/out" )"
check 'tick 1 created run.yaml, as step 0 does' \
      "$( [ -f "$RUN/run.yaml" ] && printf present || printf absent )" 'present' "$( cat "$TMP/out" )"

# Absent AFTER a tick is a different fact from absent before one: step 0 records
# it on every tick, resume included, so a tick that left it absent is contract
# drift, not a cold start.
new_run run-d4
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7'
records none none
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a tick that recorded no pluginVersion refuses, and ticks no second time' \
      "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'and names the field the orchestrator owed' "$TMP/out" 'still records no pluginVersion'

# A --run that names a path which does not EXIST is operator error, not contract
# drift: a typo or the wrong working directory ticks a whole orchestrator and
# then blames the orchestrator for a file it was never given a dir to write. The
# fresh-run case above is why this cannot be checked before tick 1 — absent
# run.yaml inside an existing dir is legitimate — so the two are told apart here,
# by the dir, after the tick.
new_run run-d6
RUN="$TMP/run-d6/does-not-exist"
STUB_RUN=$RUN
export STUB_RUN
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a --run path that does not exist refuses after one tick' \
      "$( ticks )" '1' "$( cat "$TMP/out" )"
says 'and the refusal names the missing run directory' "$TMP/out" 'run directory'
says 'and points at --run rather than the orchestrator' "$TMP/out" '--run names a path'
says_not 'it is not reported as contract drift' "$TMP/out" 'still records no pluginVersion'

# The version the run records must not MOVE mid-run either: the orchestrator
# writes it from the manifest it actually loaded, so two different values across
# two ticks means two plugin versions drove one run. Reported as a change, not as
# a mismatch — which value is "wrong" is not the driver's to say.
new_run run-d5
arm 'FLEET-STEP:v1 outcome=success waves=1/3 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/3 units=5/7' \
    'FLEET-STEP:v1 outcome=success waves=3/3 units=7/7'
records "$VERSION" 0.1.0
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a pluginVersion that changes between ticks stops the driver after tick 2' \
      "$( ticks )" '2' "$( cat "$TMP/out" )"
says 'and it is reported as a mid-run change' "$TMP/out" 'pluginVersion changed mid-run'
says 'naming the value this tick recorded' "$TMP/out" 'recorded=0.1.0'
says 'and the one the previous tick recorded' "$TMP/out" "previous tick recorded=$VERSION"

# ---------------------------------------------------------------------------
printf '\nusage — no guessing: a missing --tick or --run is an error, never a default\n\n'
# ---------------------------------------------------------------------------
new_run run-e
arm 'FLEET-STEP:v1 outcome=success waves=1/1 units=7/7'
loop "$TMP/out" --run "$RUN"
check 'without --tick it refuses to guess how to invoke the orchestrator' \
      "$( [ "$rc" -ne 0 ] && printf nonzero || printf zero )" 'nonzero' "$( cat "$TMP/out" )"
check 'and ticked nothing' "$( ticks )" '0' "$( cat "$TMP/out" )"
arm 'FLEET-STEP:v1 outcome=success waves=1/1 units=7/7'
loop "$TMP/out" --tick "$STUB_TICK"
check 'without --run there is no run.yaml to read the recorded version back from, so it refuses' \
      "$( [ "$rc" -ne 0 ] && printf nonzero || printf zero )" 'nonzero' "$( cat "$TMP/out" )"
check 'and ticks nothing' "$( ticks )" '0' "$( cat "$TMP/out" )"

# ---------------------------------------------------------------------------
printf '\nthe driver is a script, not an agent — and holds no state file\n\n'
# ---------------------------------------------------------------------------
check 'the agent census is 11: a driver is a script, never an agent' \
      "$( ls "$PLUGIN"/agents/*.md | wc -l | tr -d ' ' )" '11'
check 'no agent is named for the driver' \
      "$( ls "$PLUGIN"/agents/ | grep -c fleet )" '0'
# The negative half: every file this plugin ships whose name is fleet-loop lives
# under bin/ or scripts/ — no other directory gains an entrypoint.
check 'every fleet-loop file the plugin ships is under bin/ or scripts/' \
      "$( find "$PLUGIN" -name 'fleet-loop*' | sed "s#^$PLUGIN/##" | sed 's#/[^/]*$##' | sort -u | tr '\n' ',' )" \
      'bin,scripts,'
# No state file: the driver's only memory is the previous tick's waves=k/N, so a
# full run must leave the run dir exactly as it found it.
new_run run-f
BEFORE=$( find "$RUN" | sort | tr '\n' ',' )
arm 'FLEET-STEP:v1 outcome=success waves=1/2 units=2/7' \
    'FLEET-STEP:v1 outcome=success waves=2/2 units=7/7'
loop "$TMP/out" --run "$RUN" --tick "$STUB_TICK"
check 'a completed run left no state file behind in the run dir' \
      "$( find "$RUN" | sort | tr '\n' ',' )" "$BEFORE" "$( cat "$TMP/out" )"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
