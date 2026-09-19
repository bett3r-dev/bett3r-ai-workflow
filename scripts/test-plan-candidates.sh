#!/bin/sh
# Oracle for the candidate-oracle shape of .work/slices.yaml (ESAS-165): the
# verbs /plan reads and writes it through, driven for real.
#
#   AC1/AC3 — `design-map candidates <map.json>` over a seven-fork map offers
#             only the walks of decided, testable forks' chosen options, and
#             says how many forks it skipped and why.
#   AC2     — `design-map check-plan <slices.yaml>` fails an unattended plan that
#             marks a candidate confirmed, and a plan whose oracle carries an
#             unconfirmed candidate's example.
#   AC5     — `worktree-pool size` reports the same width whether or not the
#             top-level review:/candidateOracles: block trails slices:.
#   AC6     — a plan written with no map.json (no candidateOracles key) passes
#             check-plan with candidates=0.
#   oracles — the three adequacy rules: a slice with no `probe:` (reachability)
#             and a `then:` with no named/cited source for its expected value
#             (tautology) are refused; a structural scenario needs neither.
#   seams   — the unit names its seams once (fewest, highest, existing over new)
#             and every slice tests at a named one; a plan with no `seams:`, a
#             slice with no `seam:`, a slice at an undeclared seam and an
#             unjustified second seam are each refused, and two justified seams
#             pass.
#
# Every case reads the tool's own verdict line, never the exit code alone.
#
# Run locally:  sh scripts/test-plan-candidates.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# PC_SH selects the interpreter that runs the bin/ launchers
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
DM="$ROOT/plugins/bett3r-ai-workflow/bin/design-map"
POOL="$ROOT/plugins/bett3r-ai-workflow/bin/worktree-pool"
PC_SH=${PC_SH:-sh}
FIX="$ROOT/scripts/fixtures/design-map"
MAP="$FIX/plan-candidates.map.json"
PLANS="$FIX/check-plan"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/plan-candidates-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

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

# attr <verdict-line> <key> — one attribute's value from a verdict line.
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# run <launcher> <args…> — stdout+stderr to $OUT, real exit status in $rc
# (never through a pipe), and the last non-empty line in $LINE.
OUT="$TMP/out"
run(){
  xbin=$1; shift
  ( cd "$TMP" && "$PC_SH" "$xbin" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( awk 'NF{l=$0} END{print l}' "$OUT" )
}

# ---------------------------------------------------------------------------
printf 'Positive control: the launchers and fixtures are really there\n'
# ---------------------------------------------------------------------------
# Without this, a wrong bin path or fixture path would make every row below
# fail for the wrong reason — or, for a row asserting an absence, pass.
if [ -f "$DM" ] && [ -f "$POOL" ] && [ -f "$MAP" ]; then pass 'bin/design-map, bin/worktree-pool and the map fixture exist'
else fail 'bin/design-map, bin/worktree-pool and the map fixture exist' "$DM" "$POOL" "$MAP"; fi

run "$DM" validate "$MAP"
check 'the seven-fork fixture is a valid map' "$( attr "$LINE" outcome ) forks=$( attr "$LINE" forks ) exit=$rc" 'ok forks=7 exit=0' "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'AC1/AC3: candidates offers only decided, testable, walked choices\n'
# ---------------------------------------------------------------------------
run "$DM" candidates "$MAP"
check 'candidates: verdict ok, exit 0' "$( attr "$LINE" outcome ) exit=$rc" 'ok exit=0' "$( cat "$OUT" )"
check 'candidates: forks=7 candidates=5' \
      "forks=$( attr "$LINE" forks ) candidates=$( attr "$LINE" candidates )" 'forks=7 candidates=5' "$LINE"
# `nowalk` is now 0 and can only ever be 0 on an `outcome=ok` line: a decided
# fork carrying no walk is a refusal (below), not a counter. The key stays on
# the verdict — it is a machine contract `/plan` reads — and its zero is the
# proof that the refusal fired everywhere it applies rather than the census
# quietly dropping a fork.
check 'candidates: one skipped each for moot, open, untestable; nowalk can no longer happen' \
      "moot=$( attr "$LINE" skipped-moot ) open=$( attr "$LINE" skipped-open ) nowalk=$( attr "$LINE" skipped-nowalk ) untestable=$( attr "$LINE" skipped-untestable )" \
      'moot=1 open=1 nowalk=0 untestable=1' "$LINE"
grep '^{' "$OUT" > "$TMP/cands"
check 'candidates: exactly 5 JSON lines print' "$( wc -l < "$TMP/cands" | tr -d ' ' )" 5 "$( cat "$OUT" )"
check 'candidates: the lines come from the owner (2), recommendation (1), code (1) and F6 (1) forks' \
      "$( sed -n 's/.*"fork":"\([^"]*\)".*"source":"\([^"]*\)".*/\1:\2/p' "$TMP/cands" | tr '\n' ' ' )" \
      'ESAS-165-F3:owner ESAS-165-F3:owner ESAS-165-F4:recommendation ESAS-165-F5:code ESAS-165-F6:owner ' "$( cat "$TMP/cands" )"

# ---------------------------------------------------------------------------
printf 'The walk contract: a decided choice must arrive as a testable scenario\n'
# ---------------------------------------------------------------------------
# The measured defect this closes: 41%% of all classified fix rounds were
# `oracle-wrong` — the test encoded the wrong rule and went green anyway, caught
# only by the verifier, each catch re-paying a fresh executor context. The walk
# is where an oracle is born, and until now it could be born as prose.
run "$DM" candidates "$FIX/prose-walk.map.json"
check 'a decided option whose walk is prose is refused, naming fork, option and walk index' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" id ) $( attr "$LINE" option ) walk=$( attr "$LINE" walk ) exit=$rc" \
      'fail walk-unstructured ESAS-165-F6 A walk=0 exit=1' "$( cat "$OUT" )"

run "$DM" candidates "$FIX/decided-nowalk.map.json"
check 'a decided option carrying no walk at all is refused, not silently skipped' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" id ) exit=$rc" \
      'fail decided-nowalk ESAS-165-F6 exit=1' "$( cat "$OUT" )"

# The contract binds a DECIDED fork only. An open fork is the state the whole
# design-map exists to sit in — the owner has not chosen yet, so there is
# nothing to write a scenario against, and refusing here would make the map
# unusable for its actual purpose. The fixture's F2 is open and carries prose
# walks; the happy-path run above must have passed with it present.
check 'control: the open fork F2 is in the fixture and carries a prose walk' \
      "$( python3 -c 'import json,sys;m=json.load(open(sys.argv[1]));f=[x for x in m["forks"] if x["id"]=="ESAS-165-F2"][0];w=f["card"]["options"][0]["walks"][0];print(f["status"]["kind"], "given" in w)' "$MAP" )" \
      'open False' "$MAP"
# The moot id must be present in the map for its absence here to mean anything.
check 'control: the moot fork id is in the map fixture' "$( grep -c '"ESAS-165-F1"' "$MAP" )" 1
check 'candidates: no line names the moot fork' "$( grep -c 'ESAS-165-F1"' "$TMP/cands" )" 0 "$( cat "$TMP/cands" )"

# ---------------------------------------------------------------------------
printf 'AC2: check-plan refuses what an unattended plan must never carry\n'
# ---------------------------------------------------------------------------
run "$DM" check-plan "$PLANS/unattended-confirmed.yaml"
check 'unattended plan with a confirmed candidate: fail, exit 1' \
      "$( attr "$LINE" outcome ) reason=$( attr "$LINE" reason ) exit=$rc" 'fail reason=unattended-confirmed exit=1' "$( cat "$OUT" )"

run "$DM" check-plan "$PLANS/candidate-in-oracle.yaml"
check "an unconfirmed candidate's example inside an oracle: fail, exit 1" \
      "$( attr "$LINE" outcome ) reason=$( attr "$LINE" reason ) exit=$rc" 'fail reason=candidate-in-oracle exit=1' "$( cat "$OUT" )"

run "$DM" check-plan "$PLANS/conforming.yaml"
check 'a conforming unattended plan: ok, exit 0' \
      "$( attr "$LINE" outcome ) review=$( attr "$LINE" review ) exit=$rc" 'ok review=unattended exit=0' "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'Every slice arrives with a scenario, map or no map\n'
# ---------------------------------------------------------------------------
# The hole this closes is the one that was actually costing: both measured
# zero-first-pass-green runs were `review: unattended` with NO map.json, so the
# candidate pipeline above emitted nothing at all and every oracle was written
# freehand from prose. A contract enforced only inside `candidates` would have
# left exactly those runs untouched.
run "$DM" check-plan "$PLANS/slice-unscened.yaml"
check 'a slice carrying no scenarios at all is refused, naming the slice' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) exit=$rc" \
      'fail slice-unscened 1 exit=1' "$( cat "$OUT" )"

run "$DM" check-plan "$PLANS/scenario-partial.yaml"
check 'a scenario missing its `then` is refused, naming which half is absent' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" why ) exit=$rc" \
      'fail scenario-unstructured missing-then exit=1' "$( cat "$OUT" )"

# Given/When/Then cannot hold the negative half of a census ("...and no module
# outside X does Y"), which is the form `/plan` already mandates for an
# "every X must do Y" rule and the form that caught the worst defect in the
# corpus. `kind: structural` keeps prose deliberately, rather than by omission.
run "$DM" check-plan "$PLANS/scenario-structural.yaml"
check 'a structural scenario keeps prose and passes, counted like any other' \
      "$( attr "$LINE" outcome ) scenarios=$( attr "$LINE" scenarios ) exit=$rc" \
      'ok scenarios=1 exit=0' "$( cat "$OUT" )"

# Introducing `scenarios:` without this row would have made a rename the whole
# of the bypass: the unattended-never-promotes contract is about a candidate
# reaching the executor unconfirmed, and a GWT triple reaches it harder than
# the prose did.
run "$DM" check-plan "$PLANS/candidate-in-scenario.yaml"
check 'an unconfirmed candidate copied into a SCENARIO is refused, like one in an oracle' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) exit=$rc" \
      'fail candidate-in-oracle 1 exit=1' "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'The unit names its seams once, and every slice tests at a named one\n'
# ---------------------------------------------------------------------------
# Pocock's `to-spec`: "Use the highest seam possible... the fewer seams across
# the codebase, the better - the ideal number is one." `/plan` wrote a per-slice
# oracle under no pressure toward a shared seam, so eight slices invented eight
# oracle locations. His gate is a human confirm; lanes are unattended by
# construction, so the seam is named, justified and recorded instead, and these
# rows are what makes that mechanical rather than advisory.
run "$DM" check-plan "$PLANS/plan-unseamed.yaml"
check 'a plan that names no seam at all is refused' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) exit=$rc" \
      'fail plan-unseamed exit=1' "$( cat "$OUT" )"

run "$DM" check-plan "$PLANS/slice-unseamed.yaml"
check 'a slice that names no seam is refused, naming the slice' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) exit=$rc" \
      'fail slice-unseamed 1 exit=1' "$( cat "$OUT" )"

# The failure this closes: an oracle at a seam nobody agreed to. It is the shape
# of the worst defect in the corpus - the oracle sat at the unit, not at the
# composition root, so both wiring lines could be deleted with tsc clean and 738
# tests green.
run "$DM" check-plan "$PLANS/unnamed-seam.yaml"
check "a slice testing at an undeclared seam is refused, naming slice and seam" \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) $( attr "$LINE" seam ) exit=$rc" \
      'fail unnamed-seam 1 check_seams_internals exit=1' "$( cat "$OUT" )"
# A seam is named in prose, and a verdict is space-separated key=value: emitted
# raw, the name would end at its first space and every parser downstream would
# read a truncated name as the whole one.
check 'the refused seam name is squashed, not truncated at its first space' \
      "$( grep -c 'seam=check_seams_internals' "$OUT" )" 1 "$( cat "$OUT" )"

# FEWEST is pressure, not a cap: the first seam is free, every one after it owes
# a line saying why the named ones cannot hold this slice's claim. A number
# cannot be legislated - some units genuinely need two - but the cost of the
# second can be made a justification.
run "$DM" check-plan "$PLANS/seam-unjustified.yaml"
check 'a second seam with no `why:` is refused, naming the seam' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" seam ) $( attr "$LINE" why ) exit=$rc" \
      'fail seam-unstructured check_seams_unit extra-unjustified exit=1' "$( cat "$OUT" )"

# Control: without this row, the rule above would be indistinguishable from a
# hard cap of one seam, and every legitimate two-seam unit would be stuck.
run "$DM" check-plan "$PLANS/two-seams.yaml"
check 'two seams pass when the second says why the first cannot hold the claim' \
      "$( attr "$LINE" outcome ) seams=$( attr "$LINE" seams ) scenarios=$( attr "$LINE" scenarios ) exit=$rc" \
      'ok seams=2 scenarios=2 exit=0' "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'Oracle adequacy: green, at the seam, and still proving nothing\n'
# ---------------------------------------------------------------------------
# None of these is visible to RED -> GREEN: each is genuinely red before the
# code exists and green after, which is the whole of the evidence that gate
# collects. TAUTOLOGY and REACHABILITY are checkable at plan time and are
# checked here; DISCRIMINATION is a property of the RED the executor watches
# and is enforced there, deliberately not faked with a field.
run "$DM" check-plan "$PLANS/slice-unprobed.yaml"
check 'REACHABILITY: a slice with no `probe:` is refused, naming the slice' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) exit=$rc" \
      'fail slice-unprobed 1 exit=1' "$( cat "$OUT" )"

# Pocock, tdd/tests.md: "the assertion recomputes the expected value the way the
# code does... Expected values must come from an independent source of truth."
run "$DM" check-plan "$PLANS/scenario-unsourced.yaml"
check 'TAUTOLOGY: a `then:` naming no source for its expected value is refused' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" slice ) $( attr "$LINE" why ) exit=$rc" \
      'fail scenario-unsourced 1 no-expected-from exit=1' "$( cat "$OUT" )"

# The citation is the check: "the spec says so" with nothing to open is how a
# recomputation gets written down as a fact.
run "$DM" check-plan "$PLANS/scenario-uncited.yaml"
check 'TAUTOLOGY: a non-literal expected value citing nothing is refused' \
      "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" why ) exit=$rc" \
      'fail scenario-unsourced no-expected-source exit=1' "$( cat "$OUT" )"

# Control: a cited spec expectation passes, and so does a structural scenario,
# which carries no expected_from at all - its expected value IS the census it
# states, and there is nothing independent to cite. Without this row the rule
# would be indistinguishable from "every scenario must say `literal`".
run "$DM" check-plan "$PLANS/two-seams.yaml"
check 'a cited spec-sourced expectation passes, and every slice is probed' \
      "$( attr "$LINE" outcome ) probed=$( attr "$LINE" probed ) exit=$rc" \
      'ok probed=2 exit=0' "$( cat "$OUT" )"
check 'control: that fixture really carries a non-literal expectation' \
      "$( grep -c 'expected_from: spec' "$PLANS/two-seams.yaml" )" 1 "$PLANS/two-seams.yaml"

run "$DM" check-plan "$PLANS/scenario-structural.yaml"
check 'a structural scenario needs no expected_from, and still passes' \
      "$( attr "$LINE" outcome ) scenarios=$( attr "$LINE" scenarios ) probed=$( attr "$LINE" probed ) exit=$rc" \
      'ok scenarios=1 probed=1 exit=0' "$( cat "$OUT" )"
check 'control: that fixture carries no expected_from at all' \
      "$( grep -c 'expected_from' "$PLANS/scenario-structural.yaml" )" 0 "$( cat "$PLANS/scenario-structural.yaml" )"

# ---------------------------------------------------------------------------
printf 'AC5: the trailing review/candidateOracles block does not change pool width\n'
# ---------------------------------------------------------------------------
cat > "$TMP/bare.yaml" <<'Y'
ticket: ESAS-9
slices:
  - id: 1
    depends_on: []
  - id: 2
    depends_on: []
  - id: 3
    depends_on: [1, 2]
Y
cp "$TMP/bare.yaml" "$TMP/trailing.yaml"
cat >> "$TMP/trailing.yaml" <<'Y'
review: unattended
candidateOracles:
  - fork: ESAS-9-F1
    option: A
    scenario: the owner picks A
    source: owner
    example: A is applied
    slice: null
    status: unconfirmed
Y
run "$POOL" size "$TMP/bare.yaml"
bare="$( attr "$LINE" outcome ) width=$( attr "$LINE" width )"
check 'size without the block: ok width=2' "$bare" 'ok width=2' "$( cat "$OUT" )"
run "$POOL" size "$TMP/trailing.yaml"
check 'size with the trailing block: the same width' "$( attr "$LINE" outcome ) width=$( attr "$LINE" width )" "$bare" "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'AC6: a plan with no map.json passes check-plan\n'
# ---------------------------------------------------------------------------
run "$DM" check-plan "$PLANS/no-map.yaml"
check 'no candidateOracles key: ok candidates=0 review=unattended, exit 0' \
      "$( attr "$LINE" outcome ) candidates=$( attr "$LINE" candidates ) review=$( attr "$LINE" review ) exit=$rc" \
      'ok candidates=0 review=unattended exit=0' "$( cat "$OUT" )"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
