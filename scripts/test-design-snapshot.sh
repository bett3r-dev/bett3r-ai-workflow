#!/bin/sh
# Oracle for the design map snapshot verdicts (ESAS-162): `design-map count`,
# the goal-signal line a PR body carries, and `design-map drift`, whether the
# committed map.json has fallen behind the map feed.
#
# Both are script verdicts, never agent prose: every case drives the real
# launcher against scripts/fixtures/design-map/ and reads the `DESIGN-MAP:v1`
# verdict line (ADR-004) together with the exit code.
#
# Run locally:  sh scripts/test-design-snapshot.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# DS_SH selects the interpreter that runs the `bin/design-map` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
DM="$ROOT/plugins/bett3r-ai-workflow/bin/design-map"
DS_SH=${DS_SH:-sh}
FIX="$ROOT/scripts/fixtures/design-map"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/design-snapshot-test.XXXXXX" ) || exit 1
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

# dm <args…> — run the launcher, stdout+stderr to $OUT, and keep its real exit
# status in $rc (never through a pipe). $LINE is the verdict.
OUT="$TMP/out"
dm(){
  ( cd "$TMP" && "$DS_SH" "$DM" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^DESIGN-MAP:v1 outcome=[a-z]+( [A-Za-z_-]+=[^ ]*)*$'
}

# attr <verdict-line> <key> — one attribute's value from a verdict line.
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# lines <file> — how many non-empty lines the run printed.
lines(){
  awk 'NF{n++} END{print n+0}' "$1"
}

# first <file> — the first line the run printed.
first(){
  sed -n 1p "$1"
}

# expect_error <description> <reason> <args…>
expect_error(){
  xd=$1 xreason=$2; shift 2
  dm "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" )"
    return
  fi
  check "$xd: outcome=error" "$( attr "$LINE" outcome )" error "$LINE"
  check "$xd: reason"        "$( attr "$LINE" reason )"  "$xreason" "$LINE"
  check "$xd: exit 2"        "$rc" 2
}

COUNT="$FIX/count-2-1-1-1-0.map.json"
COUNT_DISTINCT="$FIX/count-3-2-1-4-1.map.json"
SEQ10="$FIX/feed-seq-10.map.json"
MISSING="$TMP/no-such/map.json"

# ---------------------------------------------------------------------------
printf 'AC2: count — the goal signal\n'
# ---------------------------------------------------------------------------
dm count "$COUNT"
check 'count: outcome=ok'        "$( attr "$LINE" outcome )" ok "$( cat "$OUT" )"
check 'count: verb=count'        "$( attr "$LINE" verb )" count "$LINE"
check 'count: forks=5'           "$( attr "$LINE" forks )" 5 "$LINE"
check 'count: owner=2'           "$( attr "$LINE" owner )" 2 "$LINE"
check 'count: code=1'            "$( attr "$LINE" code )" 1 "$LINE"
check 'count: recommendation=1'  "$( attr "$LINE" recommendation )" 1 "$LINE"
check 'count: open=1'            "$( attr "$LINE" open )" 1 "$LINE"
check 'count: moot=0'            "$( attr "$LINE" moot )" 0 "$LINE"
check 'count: exit 0'            "$rc" 0
check 'count without --line: the verdict is the only line' "$( lines "$OUT" )" 1 "$( cat "$OUT" )"

dm count "$COUNT" --line
check 'count --line: the PR-body line' "$( first "$OUT" )" \
  '2 of 5 forks answered by the owner (1 by code, 1 on recommendation, 1 open, 0 moot)' "$( cat "$OUT" )"
check 'count --line: two lines, verdict last' "$( lines "$OUT" )" 2 "$( cat "$OUT" )"
check 'count --line: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE"
check 'count --line: owner=2'    "$( attr "$LINE" owner )" 2 "$LINE"

# Every slot distinct and non-zero, so a swapped or hardcoded slot cannot pass.
dm count "$COUNT_DISTINCT"
check 'count distinct: outcome=ok'        "$( attr "$LINE" outcome )" ok "$( cat "$OUT" )"
check 'count distinct: forks=11'          "$( attr "$LINE" forks )" 11 "$LINE"
check 'count distinct: owner=3'           "$( attr "$LINE" owner )" 3 "$LINE"
check 'count distinct: code=2'            "$( attr "$LINE" code )" 2 "$LINE"
check 'count distinct: recommendation=1'  "$( attr "$LINE" recommendation )" 1 "$LINE"
check 'count distinct: open=4'            "$( attr "$LINE" open )" 4 "$LINE"
check 'count distinct: moot=1'            "$( attr "$LINE" moot )" 1 "$LINE"
check 'count distinct: exit 0'            "$rc" 0

dm count "$COUNT_DISTINCT" --line
check 'count distinct --line: the PR-body line' "$( first "$OUT" )" \
  '3 of 11 forks answered by the owner (2 by code, 1 on recommendation, 4 open, 1 moot)' "$( cat "$OUT" )"

dm count "$MISSING" --line
check 'count --line, no map: map: none' "$( first "$OUT" )" 'map: none' "$( cat "$OUT" )"
check 'count --line, no map: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE"
check 'count --line, no map: map=none'   "$( attr "$LINE" map )" none "$LINE"
check 'count --line, no map: exit 0'     "$rc" 0

expect_error 'count, no map, no --line' map-not-found count "$MISSING"

dm count "$COUNT" --lane "$FIX/lane-lost.yaml" --line
check 'count --lane lost: the lost line wins over a present map' "$( first "$OUT" )" \
  'map: owner answers not carried: run dir absent' "$( cat "$OUT" )"
check 'count --lane lost: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE"
check 'count --lane lost: two lines'  "$( lines "$OUT" )" 2 "$( cat "$OUT" )"

dm count "$MISSING" --lane "$FIX/lane-lost.yaml" --line
check 'count --lane lost, no map: the lost line wins over map: none' "$( first "$OUT" )" \
  'map: owner answers not carried: run dir absent' "$( cat "$OUT" )"

dm count "$COUNT" --lane "$FIX/lane-carried.yaml" --line
check 'count --lane carried (negative control): the count line' "$( first "$OUT" )" \
  '2 of 5 forks answered by the owner (1 by code, 1 on recommendation, 1 open, 0 moot)' "$( cat "$OUT" )"

# `mapProvenance: lost` must be line-anchored: a comment quoting it is not the key.
printf 'work_item: ESAS-1\nnote: "# mapProvenance: lost is what a lost run says"\n' > "$TMP/lane-quoted.yaml"
dm count "$COUNT" --lane "$TMP/lane-quoted.yaml" --line
check 'count --lane quoting the key mid-line: not lost' "$( first "$OUT" )" \
  '2 of 5 forks answered by the owner (1 by code, 1 on recommendation, 1 open, 0 moot)' "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'AC4: drift — the committed map against the feed\n'
# ---------------------------------------------------------------------------
# drift_case <description> <outcome> <exit> <mapSeq> <feedSeq> <reason|-> <args…>
drift_case(){
  xd=$1 xo=$2 xrc=$3 xm=$4 xf=$5 xr=$6; shift 6
  dm drift "$@"
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( cat "$OUT" )"
    return
  fi
  check "$xd: outcome=$xo"  "$( attr "$LINE" outcome )" "$xo" "$LINE"
  check "$xd: exit $xrc"    "$rc" "$xrc"
  check "$xd: verb=drift"   "$( attr "$LINE" verb )" drift "$LINE"
  check "$xd: mapSeq=$xm"   "$( attr "$LINE" mapSeq )" "$xm" "$LINE"
  check "$xd: feedSeq=$xf"  "$( attr "$LINE" feedSeq )" "$xf" "$LINE"
  if [ "$xr" != - ]; then
    check "$xd: reason=$xr" "$( attr "$LINE" reason )" "$xr" "$LINE"
  else
    check "$xd: no reason" "$( attr "$LINE" reason )x" x "$LINE"
  fi
}

drift_case 'map 10, feed 10'        current 0 10   10   - "$SEQ10" --feed-seq 10
drift_case 'map 10, feed 14'        drifted 1 10   14   - "$SEQ10" --feed-seq 14
drift_case 'map 10, feed 7 (map ahead)' drifted 1 10 7  - "$SEQ10" --feed-seq 7
drift_case 'map 10, --no-feed'      skip    0 10   none no-map-feed "$SEQ10" --no-feed
drift_case 'no feedSeq, feed 10'    drifted 1 none 10   - "$COUNT" --feed-seq 10

expect_error 'drift, missing map'          map-unreadable drift "$MISSING" --feed-seq 10
expect_error 'drift, invalid map'          bare-actor     drift "$FIX/bare-actor.json" --feed-seq 10
expect_error 'drift, non-integer feed seq' bad-feed-seq   drift "$SEQ10" --feed-seq ten
expect_error 'drift, negative feed seq'    bad-feed-seq   drift "$SEQ10" --feed-seq -1
expect_error 'drift, neither flag'         missing-feed   drift "$SEQ10"
expect_error 'drift, both flags'           conflicting-feed drift "$SEQ10" --feed-seq 10 --no-feed
expect_error 'drift, no map argument'      missing-map    drift --no-feed
expect_error 'count takes no --feed-seq'   unknown-flag-feed-seq count "$COUNT" --feed-seq 1

# ---------------------------------------------------------------------------
printf 'AC3: one writer — map.json and map.html are written only through design-map\n'
# ---------------------------------------------------------------------------
# rogue_writers <dir>… — every line under the dirs (recursively) that writes a
# map.json or map.html by a shell redirect, tee, cp, mv or install, and does not
# go through design-map. A redirect's `>` opens a word (after a space, a
# backtick, `(`, `|`, `&` or `;`), so prose naming the file, an arrow (->) and a
# `<path>/map.json` placeholder are not writes.
rogue_writers(){
  grep -rnE '((^|[[:space:]`(|&;])>>?[[:space:]]*[^[:space:]>]*map\.(json|html)|(^|[^[:alnum:]_-])(tee|cp|mv|install)[[:space:]][^|;]*map\.(json|html))' "$@" 2>/dev/null \
    | grep -v 'design-map'
}

PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
for d in commands agents skills; do
  check "the single-writer scan covers $d/" "$( [ -d "$PLUGIN/$d" ] && echo yes )" yes
done
check 'no command, agent or skill writes map.json/map.html other than via design-map' \
  "$( rogue_writers "$PLUGIN/commands" "$PLUGIN/agents" "$PLUGIN/skills" )x" x \
  "$( rogue_writers "$PLUGIN/commands" "$PLUGIN/agents" "$PLUGIN/skills" )"

# Positive control, nested so the recursive traversal is pinned too.
mkdir -p "$TMP/plant/skills/deep/er"
printf 'Then save it: `cat draft > docs/prs/X/map.json`.\n' > "$TMP/plant/skills/deep/er/SKILL.md"
check 'positive control: a planted `> docs/prs/X/map.json`, two dirs deep, is caught' \
  "$( rogue_writers "$TMP/plant/skills" | grep -c 'docs/prs/X/map.json' )" 1
printf 'cp draft.json docs/prs/X/map.html\n' > "$TMP/plant/skills/cp.md"
check 'positive control: a planted cp into map.html is caught' \
  "$( rogue_writers "$TMP/plant/skills/cp.md" | grep -c 'map.html' )" 1
# Negative controls: prose naming the file, and a design-map write, are not rogue.
printf 'The committed map.json sits beside design.md -> map.html.\ngit add -- <path>/design.md <path>/map.json\ndesign-map write docs/prs/X/map.json < draft.json\ndesign-map render docs/prs/X/map.json --expect 3 --out docs/prs/X/map.html\nmv draft.json in.json && design-map write docs/prs/X/map.json < in.json\n' \
  > "$TMP/plant/ok.md"
check 'negative control: prose and design-map verbs are not writers' "$( rogue_writers "$TMP/plant/ok.md" )x" x

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
