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
check 'candidates: forks=7 candidates=4' \
      "forks=$( attr "$LINE" forks ) candidates=$( attr "$LINE" candidates )" 'forks=7 candidates=4' "$LINE"
check 'candidates: one skipped each for moot, open, nowalk, untestable' \
      "moot=$( attr "$LINE" skipped-moot ) open=$( attr "$LINE" skipped-open ) nowalk=$( attr "$LINE" skipped-nowalk ) untestable=$( attr "$LINE" skipped-untestable )" \
      'moot=1 open=1 nowalk=1 untestable=1' "$LINE"
grep '^{' "$OUT" > "$TMP/cands"
check 'candidates: exactly 4 JSON lines print' "$( wc -l < "$TMP/cands" | tr -d ' ' )" 4 "$( cat "$OUT" )"
check 'candidates: the lines come from the owner (2), recommendation (1) and code (1) forks' \
      "$( sed -n 's/.*"fork":"\([^"]*\)".*"source":"\([^"]*\)".*/\1:\2/p' "$TMP/cands" | tr '\n' ' ' )" \
      'ESAS-165-F3:owner ESAS-165-F3:owner ESAS-165-F4:recommendation ESAS-165-F5:code ' "$( cat "$TMP/cands" )"
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
