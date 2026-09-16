#!/bin/sh
# Oracle for `bin/design-map render` — map.json to the page the owner answers on.
#
# The page tells the owner that a fork left unanswered is taken on its
# recommendation, so a fork that never reaches the page is accepted without
# anyone seeing it, and nothing downstream can tell it from an agreed one
# (concern C1). The render therefore refuses unless the payload holds exactly
# the forks the caller says it should (`--expect`, mandatory) AND the page it
# emitted embeds every one of them. A map payload also never carries a bare
# `actor` key (concern C2): the map's who-level is `mapActor`, so it can never
# be joined to an op's ActorId by accident.
#
# Every case drives the real launcher against the fixtures in
# scripts/fixtures/design-map/ and reads the `DESIGN-MAP:v1` verdict line
# (ADR-004), never the exit code alone.
#
# Run locally:  sh scripts/test-design-map.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# DM_SH selects the interpreter that runs the `bin/design-map` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
DM="$ROOT/plugins/bett3r-ai-workflow/bin/design-map"
DM_SH=${DM_SH:-sh}
FIX="$ROOT/scripts/fixtures/design-map"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/design-map-test.XXXXXX" ) || exit 1
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
  ( cd "$TMP" && "$DM_SH" "$DM" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^DESIGN-MAP:v1 outcome=[a-z]+( [A-Za-z]+=[^ ]*)*$'
}

# attr <verdict-line> <key> — one attribute's value from a verdict line.
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# expect_error <description> <reason> <args…> — POSIX sh has no `local`, so the
# helper keeps its values under x-prefixed names (`check` assigns d/a/e).
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

# page_absent <description> <path>
page_absent(){
  if [ -e "$2" ]; then fail "$1" "a page was left behind: $2"; else pass "$1"; fi
}

# ---------------------------------------------------------------------------
printf 'C1: the payload fork count must match --expect\n'
# ---------------------------------------------------------------------------
PAGE="$TMP/c1/map.page.html"
mkdir -p "$TMP/c1"

expect_error '11 forks, --expect 12' count-mismatch \
  render "$FIX/impact-map-11-forks.json" --expect 12 --out "$PAGE"
check '11 forks, --expect 12: names the expected count' "$( attr "$LINE" expected )" 12 "$LINE"
check '11 forks, --expect 12: names the payload count'  "$( attr "$LINE" payload )"  11 "$LINE"
page_absent '11 forks, --expect 12: no page left behind' "$PAGE"

# A page from an earlier render is exactly what would be published by mistake
# after a refusal, so a refusal removes it too — recognised by the generator
# marker every rendered page carries, and nothing without it.
dm render "$FIX/impact-map-11-forks.json" --expect 11 --out "$PAGE"
check 'a stale page at --out: made by a real render' "$( attr "$LINE" outcome )" ok "$LINE"
dm render "$FIX/impact-map-11-forks.json" --expect 12 --out "$PAGE"
check 'a stale page at --out: still refused' "$( attr "$LINE" outcome )" error "$LINE"
page_absent 'a stale page at --out: removed by the refusal' "$PAGE"

OTHER="$TMP/c1/notes.html"
printf 'not a design-map page\n' > "$OTHER"
dm render "$FIX/impact-map-11-forks.json" --expect 12 --out "$OTHER"
check 'a non-design-map file at --out: still refused' "$( attr "$LINE" outcome )" error "$LINE"
check 'a non-design-map file at --out: survives the refusal' "$( cat "$OTHER" 2>&1 )" 'not a design-map page'

# --out naming the map itself: refused, and the map is neither deleted (count
# mismatch) nor overwritten with HTML (matching count).
cp "$FIX/impact-map-11-forks.json" "$TMP/c1/victim.json"
for n in 12 11; do
  expect_error "--out is the map, --expect $n" out-is-map \
    render "$TMP/c1/victim.json" --expect "$n" --out "$TMP/c1/victim.json"
  if cmp -s "$FIX/impact-map-11-forks.json" "$TMP/c1/victim.json"; then
    pass "--out is the map, --expect $n: the map is intact"
  else
    fail "--out is the map, --expect $n: the map was deleted or overwritten"
  fi
done
( cd "$TMP/c1" && "$DM_SH" "$DM" render victim.json --expect 11 --out ./victim.json ) > "$OUT" 2>&1
check '--out is the map by another spelling: refused' "$( attr "$( verdict "$OUT" )" reason )" out-is-map

dm render "$FIX/impact-map-11-forks.json" --expect 11 --out "$PAGE"
check '11 forks, --expect 11: outcome=ok'            "$( attr "$LINE" outcome )"  ok "$LINE" "$( cat "$OUT" )"
check '11 forks, --expect 11: names the expected count' "$( attr "$LINE" expected )" 11 "$LINE"
check '11 forks, --expect 11: names the payload count'  "$( attr "$LINE" payload )"  11 "$LINE"
check '11 forks, --expect 11: names the rendered count' "$( attr "$LINE" rendered )" 11 "$LINE"
check '11 forks, --expect 11: names the page'           "$( attr "$LINE" page )"     "$PAGE" "$LINE"
check '11 forks, --expect 11: exit 0'                   "$rc" 0

# The page is read independently of the renderer's own count: one fork card per
# fork id, each id once.
if [ -f "$PAGE" ]; then
  cards=$( grep -o 'data-fork-id="F[0-9]*"' "$PAGE" | sort -u | wc -l | tr -d ' ' )
  check 'the page draws a card for each of the 11 forks' "$cards" 11
  check 'the page carries the generator marker a refusal recognises' \
    "$( grep -c '<meta name="generator" content="design-map">' "$PAGE" | tr -d ' ' )" 1
  check 'the page writes answers/<forkId> in the prototype shape' \
    "$( grep -c 'db.doc("answers/" + id).set(doc)' "$PAGE" | tr -d ' ' )" 1
  check 'the page saves {pick, comment, updatedAt}' \
    "$( grep -c 'const doc = { pick: prev.pick || null, comment: prev.comment || "", ...patch, updatedAt: new Date().toISOString() };' "$PAGE" | tr -d ' ' )" 1
  check 'the page degrades to read-only when claude.use("db") is null' \
    "$( grep -c 'if (!db) {' "$PAGE" | tr -d ' ' )" 1
else
  fail 'the page exists after an ok render' "$PAGE"
fi

# The page gate over a page on disk. A hand-made page with one card removed is
# what a drop while drawing looks like; the renderer's own output never is.
python3 - "$PAGE" "$TMP/c1/dropped.html" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
cut, n = re.subn(r'<article class="fork" data-fork-id="F7">.*?</article>', "", text, flags=re.S)
assert n == 1
open(sys.argv[2], "w", encoding="utf-8").write(cut)
PY
expect_error 'a page missing one card' page-missing-forks \
  check-page "$FIX/impact-map-11-forks.json" "$TMP/c1/dropped.html" --expect 11
check 'a page missing one card: names the expected count' "$( attr "$LINE" expected )" 11 "$LINE"
check 'a page missing one card: names the payload count'  "$( attr "$LINE" payload )"  11 "$LINE"
check 'a page missing one card: names the rendered count' "$( attr "$LINE" rendered )" 10 "$LINE"
dm check-page "$FIX/impact-map-11-forks.json" "$PAGE" --expect 11
check 'the rendered page passes the page gate' "$( attr "$LINE" outcome )" ok "$LINE"
check 'the rendered page passes the page gate: rendered=11' "$( attr "$LINE" rendered )" 11 "$LINE"

# render's own page gate, over the real render(): the module is imported and its
# page() made to drop one card — a drawing bug the shipped renderer never has, so
# it is injected from here rather than switched on in production. A real page
# from the ok render above sits at --out first; the refusal must remove it.
cp "$PAGE" "$TMP/c1/gate.html"
GATE=$( python3 - "$ROOT/plugins/bett3r-ai-workflow/scripts/design-map.py" \
  "$FIX/impact-map-11-forks.json" "$TMP/c1/gate.html" <<'PY' 2>&1
import importlib.util, os, re, sys
spec = importlib.util.spec_from_file_location("design_map", sys.argv[1])
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)
real_page = dm.page
dm.page = lambda payload: re.sub(r'<article class="fork" data-fork-id="F7">.*?</article>', "", real_page(payload), flags=re.S)
try:
    dm.render([sys.argv[2]], {"expect": "11", "out": sys.argv[3]})
    print("no-refusal")
except dm.Refusal as r:
    a = r.attrs
    print(f"reason={r.reason} expected={a.get('expected')} payload={a.get('payload')} rendered={a.get('rendered')} left={os.path.exists(sys.argv[3])}")
PY
)
check 'render drops a card while drawing: refused' "$GATE" \
  'reason=page-missing-forks expected=11 payload=11 rendered=10 left=False'

expect_error 'missing --expect' missing-expect \
  render "$FIX/impact-map-11-forks.json" --out "$TMP/c1/no-expect.html"
page_absent 'missing --expect: no page' "$TMP/c1/no-expect.html"
expect_error 'a non-integer --expect' malformed-expect \
  render "$FIX/impact-map-11-forks.json" --expect eleven --out "$TMP/c1/bad-expect.html"

# ---------------------------------------------------------------------------
printf 'C2: a bare `actor` key anywhere is refused\n'
# ---------------------------------------------------------------------------
expect_error 'bare actor nested inside a fork option' bare-actor \
  render "$FIX/bare-actor.json" --expect 3 --out "$TMP/c2.html"
check 'bare actor: names where it is' "$( attr "$LINE" at )" /forks/1/options/0/actor "$LINE"
page_absent 'bare actor: no page' "$TMP/c2.html"

# The committed schema names the who-level `mapActor` and carries a version.
SCHEMA="$ROOT/plugins/bett3r-ai-workflow/skills/design-map/map.schema.json"
check 'the committed schema requires schemaVersion' \
  "$( python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("schemaVersion" in s["required"])' "$SCHEMA" 2>&1 )" True
check 'the committed schema defines mapActors, and no property named actor' \
  "$( python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
def names(v):
    if isinstance(v, dict):
        for k, c in v.items():
            if k == "properties":
                yield from c
            yield from names(c)
    elif isinstance(v, list):
        for c in v:
            yield from names(c)
n = set(names(s))
print("mapActors" in n and "actor" not in n)' "$SCHEMA" 2>&1 )" True

# ---------------------------------------------------------------------------
printf 'F1: both layouts; the impact-map levels are required only under impactMap\n'
# ---------------------------------------------------------------------------
dm render "$FIX/decision-tree-no-goal.json" --expect 3 --out "$TMP/tree.html"
check 'decisionTree with no goal: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'decisionTree with no goal: rendered=3' "$( attr "$LINE" rendered )" 3 "$LINE"

expect_error 'impactMap with no goal' schema-invalid \
  render "$FIX/impact-map-no-goal.json" --expect 11 --out "$TMP/nogoal.html"
check 'impactMap with no goal: names the missing level' "$( attr "$LINE" at )" /goal "$LINE"
page_absent 'impactMap with no goal: no page' "$TMP/nogoal.html"

# An id pattern anchored with `$` matches only at the end, as in JSON Schema:
# a trailing newline in a fork id is refused.
python3 - "$FIX/decision-tree-no-goal.json" "$TMP/newline-id.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["forks"][0]["id"] = "F1\n"
json.dump(m, open(sys.argv[2], "w"))
PY
expect_error 'a fork id with a trailing newline' schema-invalid \
  render "$TMP/newline-id.json" --expect 3 --out "$TMP/nl.html"

# ---------------------------------------------------------------------------
printf 'the verdict line, not the exit code\n'
# ---------------------------------------------------------------------------
expect_error 'an unreadable map path' map-unreadable \
  render "$TMP/does-not-exist.json" --expect 1 --out "$TMP/x.html"
expect_error 'an unknown verb' unknown-verb draw "$FIX/decision-tree-no-goal.json"

( cd "$TMP" && "$DM_SH" "$DM" render "$FIX/impact-map-11-forks.json" --expect 12 --out "$TMP/w.html"; true ) > "$OUT" 2>&1
rc=$?
LINE=$( verdict "$OUT" )
check 'a wrapper swallowing the exit status: exit reads 0' "$rc" 0
check 'a wrapper swallowing the exit status: the line still reads error' "$( attr "$LINE" outcome )" error "$LINE"

printf 'Traceback (most recent call last):\n' > "$TMP/crash"
check 'a run that printed no verdict line parses as no verdict' "$( verdict "$TMP/crash" || printf none )" none

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
