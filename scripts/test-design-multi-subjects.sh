#!/bin/sh
# Oracle for `bin/design-multi-subjects` (ESAS-166 D2/D4/Fork 1, AC4) — the
# grouping of a design-multi run's units into subjects, and the fingerprint a
# resume compares to decide whether the grouping is re-asked.
#
# Every case drives the real launcher against scripts/fixtures/design-multi-subjects/
# and reads the `DESIGN-MULTI-SUBJECTS:v1` verdict line (ADR-004), never the
# exit code alone.
#
# Run locally:  sh scripts/test-design-multi-subjects.sh
# DMS_SH selects the interpreter that runs the launcher.

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
DMS="$ROOT/plugins/bett3r-ai-workflow/bin/design-multi-subjects"
DMS_SH=${DMS_SH:-sh}
FIX="$ROOT/scripts/fixtures/design-multi-subjects"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/design-multi-subjects-test.XXXXXX" ) || exit 1
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

# check <description> <actual> <expected> [context lines…] — an EMPTY expected
# value is refused, so a step that never ran cannot "match" an empty actual.
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

# dms <args…> — run the launcher; stdout to $OUT, stderr to $ERR, exit in $rc.
OUT="$TMP/out"
ERR="$TMP/err"
dms(){
  ( cd "$TMP" && "$DMS_SH" "$DMS" "$@" ) > "$OUT" 2> "$ERR"
  rc=$?
  LINE=$( verdict "$OUT" )
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^DESIGN-MULTI-SUBJECTS:v1 outcome=[a-z]+( [A-Za-z_-]+=[^ ]*)*$'
}

# attr <verdict-line> <key>
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# payload <file> — every line but the verdict (the JSON document).
payload(){
  sed '$d' "$1"
}

# subject <file> <id> — "basis:unit,unit" for one subject, or "absent".
subject(){
  payload "$1" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
for s in doc["subjects"]:
    if s["id"] == sys.argv[1]:
        print(s["basis"] + ":" + ",".join(s["units"])); break
else:
    print("absent")' "$2"
}

expect_error(){
  xd=$1 xreason=$2; shift 2
  dms "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" "$ERR" )"
    return
  fi
  check "$xd: outcome=error" "$( attr "$LINE" outcome )" error "$LINE"
  check "$xd: reason"        "$( attr "$LINE" reason )"  "$xreason" "$LINE"
  check "$xd: exit 2"        "$rc" 2
}

# ---------------------------------------------------------------------------
printf 'D2: units group by epic link; no parent is a singleton\n'
# ---------------------------------------------------------------------------
dms group "$FIX/units"
check 'default grouping: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$ERR" )"
check 'default grouping: exit 0' "$rc" 0
check 'default grouping: 3 subjects' "$( attr "$LINE" subjects )" 3 "$LINE"
check 'default grouping: 5 units' "$( attr "$LINE" units )" 5 "$LINE"
check 'default grouping: asked counts every subject with no prior' "$( attr "$LINE" asked )" 3 "$LINE"
check 'E1 is one epic subject of 3' "$( subject "$OUT" E1 )" 'epic:ESAS-101,ESAS-102,ESAS-103'
check 'ESAS-104 is a singleton' "$( subject "$OUT" ESAS-104 )" 'singleton:ESAS-104'
check 'ESAS-105 is a singleton' "$( subject "$OUT" ESAS-105 )" 'singleton:ESAS-105'
check 'an indented parent: header line is not an epic link' "$( subject "$OUT" E9 )" absent
check 'a column-0 parent: line in the BODY is not an epic link' "$( subject "$OUT" X )" absent
FP=$( attr "$LINE" fingerprint )
check 'the verdict fingerprint is the payload fingerprint' \
  "$( payload "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["subjectsFingerprint"])' )" "$FP"
check 'the fingerprint is a sha256 hex' "$( printf '%s' "$FP" | grep -cE '^[0-9a-f]{64}$' )" 1
payload "$OUT" > "$TMP/prior.json"
cp "$OUT" "$TMP/first-run"

# ---------------------------------------------------------------------------
printf 'determinism\n'
# ---------------------------------------------------------------------------
dms group "$FIX/units"
if cmp -s "$OUT" "$TMP/first-run"; then pass 'two runs are byte-identical'; else fail 'two runs are byte-identical' "$( diff "$TMP/first-run" "$OUT" )"; fi

# ---------------------------------------------------------------------------
printf 'Fork 1: a resume re-asks only changed subjects\n'
# ---------------------------------------------------------------------------
dms group "$FIX/units" --prior "$TMP/prior.json"
check 'identical re-run with the prior: same fingerprint' "$( attr "$LINE" fingerprint )" "$FP" "$LINE"
check 'identical re-run with the prior: asked=0' "$( attr "$LINE" asked )" 0 "$LINE"

mkdir -p "$TMP/dropped"
cp "$FIX/units/"*.ticket.md "$TMP/dropped/"
rm "$TMP/dropped/ESAS-103.ticket.md"
dms group "$TMP/dropped" --prior "$TMP/prior.json"
check 'one unit dropped from E1: asked=1' "$( attr "$LINE" asked )" 1 "$LINE"
check 'one unit dropped from E1: units=4' "$( attr "$LINE" units )" 4 "$LINE"
if [ "$( attr "$LINE" fingerprint )" != "$FP" ]; then pass 'one unit dropped: fingerprint changes'; else fail 'one unit dropped: fingerprint changes' "$LINE"; fi

mkdir -p "$TMP/reparented"
cp "$FIX/units/"*.ticket.md "$TMP/reparented/"
printf '# ESAS-104 — loose 4\nStatus: To Do\nparent: E1\n\nbody\n' > "$TMP/reparented/ESAS-104.ticket.md"
dms group "$TMP/reparented" --prior "$TMP/prior.json"
check 'a unit gains a parent (same ids): units=5' "$( attr "$LINE" units )" 5 "$LINE"
check 'a unit gains a parent: E1 now holds 4 units' "$( subject "$OUT" E1 )" 'epic:ESAS-101,ESAS-102,ESAS-103,ESAS-104'
if [ "$( attr "$LINE" fingerprint )" != "$FP" ] && [ -n "$( attr "$LINE" fingerprint )" ]; then pass 'a unit gains a parent: fingerprint changes'; else fail 'a unit gains a parent: fingerprint changes' "$LINE"; fi
if [ "$( attr "$LINE" asked )" -ge 1 ] 2>/dev/null; then pass 'a unit gains a parent: asked>=1'; else fail 'a unit gains a parent: asked>=1' "$LINE"; fi

# ---------------------------------------------------------------------------
printf 'D2: an accepted seam proposal overrides the default grouping\n'
# ---------------------------------------------------------------------------
dms group "$FIX/units" --seams "$FIX/seams.json" --prior "$TMP/prior.json"
check 'seam merge of two singletons: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$ERR" )"
check 'seam merge: 2 subjects' "$( attr "$LINE" subjects )" 2 "$LINE"
check 'seam merge: the proposal is a seam subject, units sorted' "$( subject "$OUT" S-loose )" 'seam:ESAS-104,ESAS-105'
check 'seam merge: the merged singleton is gone' "$( subject "$OUT" ESAS-104 )" absent
check 'seam merge: the epic is untouched' "$( subject "$OUT" E1 )" 'epic:ESAS-101,ESAS-102,ESAS-103'
check 'seam merge: only the new seam subject is asked' "$( attr "$LINE" asked )" 1 "$LINE"
if [ "$( attr "$LINE" fingerprint )" != "$FP" ]; then pass 'seam merge: an accepted proposal changes the fingerprint'; else fail 'seam merge: an accepted proposal changes the fingerprint' "$LINE"; fi

printf '[{"id":"S-split","units":["ESAS-103"],"basis":"seam"}]\n' > "$TMP/split.json"
dms group "$FIX/units" --seams "$TMP/split.json"
check 'seam split of an epic: the remainder keeps the epic id' "$( subject "$OUT" E1 )" 'epic:ESAS-101,ESAS-102'
check 'seam split of an epic: the split-off part' "$( subject "$OUT" S-split )" 'seam:ESAS-103'

# ---------------------------------------------------------------------------
printf 'errors\n'
# ---------------------------------------------------------------------------
expect_error 'a missing units dir' units-dir-missing group "$TMP/nope"
mkdir -p "$TMP/empty"
expect_error 'a units dir with no snapshots' no-units group "$TMP/empty"
expect_error 'an unknown verb' unknown-verb draw "$FIX/units"
printf '[{"id":"S","units":["ESAS-999"],"basis":"seam"}]\n' > "$TMP/unk.json"
expect_error 'a seam naming an unknown unit' seam-unknown-unit group "$FIX/units" --seams "$TMP/unk.json"
printf '[{"id":"A","units":["ESAS-104"],"basis":"seam"},{"id":"B","units":["ESAS-104"],"basis":"seam"}]\n' > "$TMP/ov.json"
expect_error 'a unit in two seams' seam-overlap group "$FIX/units" --seams "$TMP/ov.json"
printf '[{"id":"S","units":["ESAS-104"],"basis":"epic"}]\n' > "$TMP/basis.json"
expect_error 'a proposal whose basis is not seam' seams-malformed group "$FIX/units" --seams "$TMP/basis.json"
printf '[{"id":"E1","units":["ESAS-104"],"basis":"seam"}]\n' > "$TMP/coll.json"
expect_error 'a seam id colliding with a subject' seam-id-collision group "$FIX/units" --seams "$TMP/coll.json"
printf 'not json' > "$TMP/bad.json"
expect_error '--seams with no value' missing-flag-value-seams group "$FIX/units" --seams
expect_error '--prior with no value' missing-flag-value-prior group "$FIX/units" --prior
expect_error 'an unknown flag' unknown-flag-bogus group "$FIX/units" --bogus x
expect_error 'an unreadable seams file' seams-unreadable group "$FIX/units" --seams "$TMP/nope.json"
expect_error 'an unreadable prior file' prior-unreadable group "$FIX/units" --prior "$TMP/nope.json"
expect_error 'a malformed prior' prior-malformed group "$FIX/units" --prior "$TMP/bad.json"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
