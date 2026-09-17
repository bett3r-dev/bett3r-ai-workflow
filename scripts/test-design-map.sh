#!/bin/sh
# Oracle for `bin/design-map` — `validate` (a map.json against the v2 structure
# and the esas vocabulary copy), `render` (map.json to the page the owner
# answers on) and `apply-answers` (the saved answers back into fork statuses, F3).
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
#
# ESAS_CHECKOUT, when set, names an esas checkout: the vocabulary copy
# skills/design-map/map.schema.json is compared byte for byte with its
# packages/esas-schema/schema/map.schema.json (and with serialiseMapSchema()
# when packages/esas-schema/build/esm/index.js exists). Unset, that case prints
# `SKIP reason=no-esas-checkout` and is counted as skipped, never as passed.

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
  cards=$( grep -o 'data-fork-id="ESAS-1-F[0-9]*"' "$PAGE" | sort -u | wc -l | tr -d ' ' )
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
cut, n = re.subn(r'<article class="fork[^"]*" data-fork-id="ESAS-1-F7">.*?</article>', "", text, flags=re.S)
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
dm.page = lambda payload: re.sub(r'<article class="fork[^"]*" data-fork-id="ESAS-1-F7">.*?</article>', "", real_page(payload), flags=re.S)
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
check 'bare actor: names where it is' "$( attr "$LINE" at )" /forks/1/card/options/0/actor "$LINE"
page_absent 'bare actor: no page' "$TMP/c2.html"

# The vocabulary is esas's emitted copy; the structure is a second file whose
# enums are `$ref`s into that copy, never restated.
SKILL_DIR="$ROOT/plugins/bett3r-ai-workflow/skills/design-map"
VOCAB="$SKILL_DIR/map.schema.json"
STRUCTURE="$SKILL_DIR/map-structure.schema.json"
check 'the structure schema pins structureVersion 2' \
  "$( python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["properties"]["structureVersion"], "structureVersion" in s["required"])' "$STRUCTURE" 2>&1 )" \
  "{'const': 2} True"
check 'the vocabulary copy spells the who-level mapActor, and no schema property is named actor' \
  "$( python3 -c '
import json, sys
v = json.load(open(sys.argv[1])); s = json.load(open(sys.argv[2]))
def names(x):
    if isinstance(x, dict):
        for k, c in x.items():
            if k == "properties":
                yield from c
            yield from names(c)
    elif isinstance(x, list):
        for c in x:
            yield from names(c)
print("mapActor" in v["$defs"]["mapNodeLevel"]["enum"] and "actor" not in set(names(s)))' "$VOCAB" "$STRUCTURE" 2>&1 )" True
check 'the structure schema restates no vocabulary enum, and $refs every one of the four' \
  "$( python3 -c '
import json, sys
v = json.load(open(sys.argv[1])); s = json.load(open(sys.argv[2]))
values = {e for d in v["$defs"].values() for e in d["enum"]}
enums, refs = [], set()
def walk(x):
    if isinstance(x, dict):
        for k, c in x.items():
            if k == "enum":
                enums.extend(c)
            if k == "$ref" and c.startswith("map.schema.json#/$defs/"):
                refs.add(c.rsplit("/", 1)[1])
            walk(c)
    elif isinstance(x, list):
        for c in x:
            walk(c)
walk(s)
print(sorted(set(enums) & values), sorted(refs) == sorted(v["$defs"]))' "$VOCAB" "$STRUCTURE" 2>&1 )" '[] True'

# ---------------------------------------------------------------------------
printf 'AC1: the vocabulary copy is byte-identical to esas'"'"'s emitted schema\n'
# ---------------------------------------------------------------------------
# stale <copy> <reference> — prints fresh or stale. The planted-byte probe runs
# the same function, so a comparison that cannot fail is caught here.
stale(){
  if cmp -s "$1" "$2"; then printf fresh; else printf stale; fi
}
skipped=0
if [ -n "${ESAS_CHECKOUT:-}" ]; then
  EMITTED="$ESAS_CHECKOUT/packages/esas-schema/schema/map.schema.json"
  if [ -f "$EMITTED" ]; then
    check 'the copy equals $ESAS_CHECKOUT packages/esas-schema/schema/map.schema.json' \
      "$( stale "$VOCAB" "$EMITTED" )" fresh "$EMITTED"
  else
    fail 'ESAS_CHECKOUT holds the emitted map.schema.json' "no file at $EMITTED"
  fi
  cp "$VOCAB" "$TMP/planted.json"
  python3 - "$TMP/planted.json" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
i = b.index(b"decided"); b[i] = ord("D")
open(p, "wb").write(bytes(b))
PY
  check 'one planted byte in a temp copy is detected as stale' "$( stale "$TMP/planted.json" "$EMITTED" )" stale
  BUILT="$ESAS_CHECKOUT/packages/esas-schema/build/esm/index.js"
  if [ -f "$BUILT" ]; then
    # Serialise to stdout only: the package's emit script writes into the checkout.
    if node --input-type=module -e 'const m = await import(process.argv[1]); process.stdout.write(m.serialiseMapSchema());' \
        "file://$BUILT" > "$TMP/serialised.json" 2> "$TMP/serialise.err"; then
      check 'the copy equals serialiseMapSchema() from build/esm' "$( stale "$VOCAB" "$TMP/serialised.json" )" fresh
    else
      fail 'serialiseMapSchema() from build/esm runs' "$( cat "$TMP/serialise.err" )"
    fi
  else
    printf '  - no %s: the serialiser comparison is not run; the committed emit output was compared\n' "$BUILT"
  fi
else
  skipped=$(( skipped + 1 ))
  printf '  \033[33m!! SKIP reason=no-esas-checkout\033[0m the vocabulary copy was NOT compared with esas (set ESAS_CHECKOUT); this is not a pass\n'
fi

# ---------------------------------------------------------------------------
printf 'AC2: the v2 structure; every refusal leaves the map byte-identical\n'
# ---------------------------------------------------------------------------
mkdir -p "$TMP/v2"
# variant <name> <python statements over m> — a mutated copy of the decision
# fixture at $TMP/v2/<name>.json; the statements come from this file only.
variant(){
  python3 - "$FIX/decision-3-forks.json" "$TMP/v2/$1.json" "$2" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
exec(sys.argv[3])
with open(sys.argv[2], "w") as fh:
    json.dump(m, fh, indent=2)
PY
}
# refuse_validate <description> <reason> <map> — refused by validate, byte-identical after.
refuse_validate(){
  zd=$1 zreason=$2 zmap=$3
  cp "$zmap" "$TMP/v2/before.json"
  expect_error "$zd" "$zreason" validate "$zmap"
  if cmp -s "$TMP/v2/before.json" "$zmap"; then pass "$zd: the map is byte-identical"; else fail "$zd: the map changed"; fi
}

dm validate "$FIX/impact-map-11-forks.json"
check 'validate a grounded impact map: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'validate: verb=validate' "$( attr "$LINE" verb )" validate "$LINE"
check 'validate: forks=11' "$( attr "$LINE" forks )" 11 "$LINE"
check 'validate: exit 0' "$rc" 0

refuse_validate 'a 161-v1 map' schema-invalid "$FIX/v1-map.json"
check 'a 161-v1 map: names the missing structureVersion' "$( attr "$LINE" at )" /structureVersion "$LINE"

variant no-tickets 'del m["forks"][0]["tickets"]'
refuse_validate 'a fork without tickets' schema-invalid "$TMP/v2/no-tickets.json"
check 'a fork without tickets: at' "$( attr "$LINE" at )" /forks/0/tickets "$LINE"
variant empty-tickets 'm["forks"][0]["tickets"] = []'
refuse_validate 'a fork with an empty tickets list' schema-invalid "$TMP/v2/empty-tickets.json"
check 'a fork with an empty tickets list: rule=minItems' "$( attr "$LINE" rule )" minItems "$LINE"

for bad in F1 ESAS-1_F1 esas-1-F1; do
  variant "id-$bad" "m['forks'][0]['id'] = '$bad'"
  refuse_validate "fork id $bad" schema-invalid "$TMP/v2/id-$bad.json"
  check "fork id $bad: rule=pattern at the id" "$( attr "$LINE" rule ):$( attr "$LINE" at )" pattern:/forks/0/id "$LINE"
done
# An id pattern anchored with `$` matches only at the end, as in JSON Schema.
variant newline-id 'm["forks"][0]["id"] = "ESAS-1-F1\n"'
refuse_validate 'a fork id with a trailing newline' schema-invalid "$TMP/v2/newline-id.json"
variant underscore-option 'm["forks"][0]["card"]["options"][0]["id"] = "A_1"'
refuse_validate 'an option id with an underscore' schema-invalid "$TMP/v2/underscore-option.json"

variant dup-fork 'm["forks"][1]["id"] = m["forks"][0]["id"]'
refuse_validate 'a duplicate fork id' duplicate-fork-id "$TMP/v2/dup-fork.json"
check 'a duplicate fork id: names it' "$( attr "$LINE" id )" ESAS-1-F1 "$LINE"
variant dup-node 'm["nodes"] = [{"id": "G", "level": "goal", "title": "g", "parents": []}, {"id": "G", "level": "impact", "title": "i", "parents": []}]'
refuse_validate 'a duplicate node id' duplicate-node-id "$TMP/v2/dup-node.json"
check 'a duplicate node id: names it' "$( attr "$LINE" id )" G "$LINE"
variant dup-option 'm["forks"][0]["card"]["options"][1]["id"] = "A"'
refuse_validate 'a duplicate option id' duplicate-option-id "$TMP/v2/dup-option.json"
check 'a duplicate option id: names the fork and the option' \
  "$( attr "$LINE" id ):$( attr "$LINE" option )" ESAS-1-F1:A "$LINE"
variant same-option-two-forks 'pass'
dm validate "$TMP/v2/same-option-two-forks.json"
check 'the same option id on two forks: ok (unique per fork only)' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"

variant decided-no-option 'm["forks"][0]["status"] = {"kind": "decided", "source": "owner"}'
refuse_validate 'decided with no option' schema-invalid "$TMP/v2/decided-no-option.json"
check 'decided with no option: names the missing option' "$( attr "$LINE" rule ):$( attr "$LINE" at )" required:/forks/0/status/option "$LINE"
variant open-and-moot 'm["forks"][0]["status"] = {"kind": "open", "reason": "x", "option": "A"}'
refuse_validate 'a status matching no kind'"'"'s fields' schema-invalid "$TMP/v2/open-and-moot.json"
variant decided-no-source 'm["forks"][0]["status"] = {"kind": "decided", "option": "A"}'
refuse_validate 'decided with no source' schema-invalid "$TMP/v2/decided-no-source.json"
variant moot-no-reason 'm["forks"][0]["status"] = {"kind": "moot"}'
refuse_validate 'moot with no reason' schema-invalid "$TMP/v2/moot-no-reason.json"
variant open-with-option 'm["forks"][0]["status"] = {"kind": "open", "option": "A"}'
refuse_validate 'open carrying an option' schema-invalid "$TMP/v2/open-with-option.json"
variant unknown-option 'm["forks"][0]["status"] = {"kind": "decided", "source": "owner", "option": "Z"}'
refuse_validate 'decided naming no card option' unknown-option "$TMP/v2/unknown-option.json"
check 'decided naming no card option: names the fork' "$( attr "$LINE" id )" ESAS-1-F1 "$LINE"
variant rec-unknown-option 'm["forks"][0]["card"]["recommendation"]["option"] = "Z"'
refuse_validate 'a recommendation naming no card option' unknown-option "$TMP/v2/rec-unknown-option.json"
variant decided-title-only 'del m["forks"][0]["card"]; m["forks"][0]["status"] = {"kind": "decided", "source": "owner", "option": "A"}'
refuse_validate 'decided on a card-less fork' decided-title-only "$TMP/v2/decided-title-only.json"

variant closed 'm["forks"][0]["status"] = {"kind": "closed"}'
refuse_validate 'status.kind closed' schema-invalid "$TMP/v2/closed.json"
check 'status.kind closed: refused by the vocabulary enum reached through $ref' \
  "$( attr "$LINE" rule ):$( attr "$LINE" at )" enum:/forks/0/status/kind "$LINE"
variant bad-source 'm["forks"][0]["status"] = {"kind": "decided", "source": "agent", "option": "A"}'
refuse_validate 'source agent' schema-invalid "$TMP/v2/bad-source.json"
check 'source agent: the decidedSource enum' "$( attr "$LINE" rule ):$( attr "$LINE" at )" enum:/forks/0/status/source "$LINE"
variant code 'm["forks"][0]["status"] = {"kind": "decided", "source": "code", "option": "A"}'
dm validate "$TMP/v2/code.json"
check 'source code: accepted' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"

variant no-shape 'del m["shape"]'
refuse_validate 'grounded:true without shape' schema-invalid "$TMP/v2/no-shape.json"
check 'grounded:true without shape: at /shape' "$( attr "$LINE" rule ):$( attr "$LINE" at )" required:/shape "$LINE"
variant tree 'm["shape"] = "tree"'
refuse_validate "shape tree" schema-invalid "$TMP/v2/tree.json"
check 'shape tree: the mapShape enum' "$( attr "$LINE" rule ):$( attr "$LINE" at )" enum:/shape "$LINE"
variant bad-level 'm["nodes"] = [{"id": "G", "level": "stakeholder", "title": "g", "parents": []}]'
refuse_validate 'node level stakeholder' schema-invalid "$TMP/v2/bad-level.json"
check 'node level stakeholder: the mapNodeLevel enum' "$( attr "$LINE" rule ):$( attr "$LINE" at )" enum:/nodes/0/level "$LINE"
variant title 'm["title"] = "v1 kept its title"'
refuse_validate 'an unknown top-level key' schema-invalid "$TMP/v2/title.json"
check 'an unknown top-level key: rule' "$( attr "$LINE" rule )" additionalProperties "$LINE"
variant feedseq 'm["feedSeq"] = -1'
refuse_validate 'feedSeq -1' schema-invalid "$TMP/v2/feedseq.json"
check 'feedSeq -1: rule=minimum' "$( attr "$LINE" rule )" minimum "$LINE"
variant target 'm["target"] = "web"'
refuse_validate 'target web' schema-invalid "$TMP/v2/target.json"
variant testable 'm["forks"][0]["testable"] = True'
refuse_validate 'testable true' schema-invalid "$TMP/v2/testable.json"

variant dangling-anchor 'm["forks"][0]["anchor"] = "NOPE"'
refuse_validate 'an anchor naming no node' dangling-ref "$TMP/v2/dangling-anchor.json"
check 'an anchor naming no node: id and at' "$( attr "$LINE" id ):$( attr "$LINE" at )" NOPE:/forks/0/anchor "$LINE"
variant dangling-parent 'm["nodes"] = [{"id": "G", "level": "goal", "title": "g", "parents": ["X"]}]'
refuse_validate 'a parent naming no node' dangling-ref "$TMP/v2/dangling-parent.json"
check 'a parent naming no node: at' "$( attr "$LINE" at )" /nodes/0/parents/0 "$LINE"
variant dangling-rests 'm["forks"][0]["restsOn"] = ["ESAS-1-F9"]'
refuse_validate 'restsOn naming no fork' dangling-ref "$TMP/v2/dangling-rests.json"
check 'restsOn naming no fork: at' "$( attr "$LINE" at )" /forks/0/restsOn/0 "$LINE"
variant anchor-is-fork 'm["forks"][0]["anchor"] = "ESAS-1-F2"'
refuse_validate 'an anchor naming a fork, not a node' dangling-ref "$TMP/v2/anchor-is-fork.json"
variant dangling-link 'm["links"] = [{"esId": "cmd_x_y", "deliverableId": "D9"}]'
refuse_validate 'a link naming no node' dangling-ref "$TMP/v2/dangling-link.json"

# The cross-file $ref is resolved from the structure file's own directory, and
# the enum values are read from the copy as data: a vocabulary that admits
# `closed` admits it, a ref that resolves nowhere is schema-unreadable.
# Run against scratch copies, never the committed files.
REFS=$( python3 - "$ROOT/plugins/bett3r-ai-workflow/scripts/design-map.py" "$VOCAB" "$STRUCTURE" "$TMP/refs" "$TMP/v2/closed.json" "$TMP/v2/tree.json" <<'PY' 2>&1
import importlib.util, json, os, sys
script, vocab, structure, scratch, closed, tree = sys.argv[1:7]
spec = importlib.util.spec_from_file_location("design_map", script)
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)
def outcome(vocab_doc, structure_text, path=closed):
    payload = json.load(open(path))
    os.makedirs(scratch, exist_ok=True)
    for name in os.listdir(scratch):
        os.remove(os.path.join(scratch, name))
    if vocab_doc is not None:
        json.dump(vocab_doc, open(os.path.join(scratch, "map.schema.json"), "w"))
    open(os.path.join(scratch, "map-structure.schema.json"), "w").write(structure_text)
    dm.STRUCTURE_PATH = os.path.join(scratch, "map-structure.schema.json")
    try:
        dm.validate(payload)
        return "ok"
    except dm.Refusal as r:
        return r.reason + ":" + r.attrs.get("rule", "")
v = json.load(open(vocab)); s = open(structure).read()
wide = json.loads(json.dumps(v)); wide["$defs"]["mapShape"]["enum"].append("tree")
print("closed=" + outcome(v, s),
      "tree=" + outcome(v, s, tree),
      "tree-widened=" + outcome(wide, s, tree),
      "missing-def=" + outcome(v, s.replace("#/$defs/forkStatusKind", "#/$defs/noSuchDef")),
      "missing-file=" + outcome(None, s))
PY
)
check 'the $ref: enums are read from the copy as data; an unresolvable ref is schema-unreadable' \
  "$REFS" 'closed=schema-invalid:enum tree=schema-invalid:enum tree-widened=ok missing-def=schema-unreadable: missing-file=schema-unreadable:'

# ---------------------------------------------------------------------------
printf 'AC3: grounding — render refuses an ungrounded map, validate accepts it\n'
# ---------------------------------------------------------------------------
variant ungrounded 'm["grounded"] = False; del m["shape"]'
dm validate "$TMP/v2/ungrounded.json"
check 'grounded:false: validate ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'grounded:false: validate forks=3' "$( attr "$LINE" forks )" 3 "$LINE"
cp "$TMP/v2/ungrounded.json" "$TMP/v2/ungrounded.before.json"
expect_error 'grounded:false: render' not-grounded \
  render "$TMP/v2/ungrounded.json" --expect 3 --out "$TMP/v2/ungrounded.html"
page_absent 'grounded:false: no file at --out' "$TMP/v2/ungrounded.html"
dm render "$FIX/decision-3-forks.json" --expect 3 --out "$TMP/v2/stale.html"
expect_error 'grounded:false: check-page' not-grounded \
  check-page "$TMP/v2/ungrounded.json" "$TMP/v2/stale.html" --expect 3
if cmp -s "$TMP/v2/ungrounded.before.json" "$TMP/v2/ungrounded.json"; then
  pass 'grounded:false: the map is byte-identical'
else
  fail 'grounded:false: the map changed'
fi
variant empty-ungrounded 'm["grounded"] = False; del m["shape"]; m["forks"] = []'
dm render "$TMP/v2/empty-ungrounded.json" --expect 0 --out "$TMP/v2/empty.html"
check 'an ungrounded map with no forks: render ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"

# ---------------------------------------------------------------------------
printf 'F1: both shapes render; cards come from the card, a card-less fork is title-only\n'
# ---------------------------------------------------------------------------
dm render "$FIX/decision-3-forks.json" --expect 3 --out "$TMP/tree.html"
check 'decision shape: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'decision shape: rendered=3' "$( attr "$LINE" rendered )" 3 "$LINE"

# D7: owner, recommendation and code are three distinct styles, on the forks
# the 11-fork fixture holds in each (F2 owner, F4 recommendation, F5 code).
python3 - "$PAGE" > "$TMP/c1/styles.txt" <<'PY' 2>&1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
cls = {fid: c for c, fid in re.findall(r'<article class="([^"]*)" data-fork-id="([^"]*)"', text)}
print(cls["ESAS-1-F2"], "|", cls["ESAS-1-F4"], "|", cls["ESAS-1-F5"], "|", cls["ESAS-1-F6"])
rules = [r for r in ("owner", "recommendation", "code") if re.search(r"\.fork\.%s\{border-left-color:(#[0-9a-f]+)" % r, text)]
colors = {re.search(r"\.fork\.%s\{border-left-color:(#[0-9a-f]+)" % r, text).group(1) for r in rules}
print(len(rules), len(colors))
body = re.search(r'data-fork-id="ESAS-1-F6">(.*?)</article>', text, re.S).group(1)
print("data-pick" in body, "Fork 6: which option?" in body)
PY
check 'the page: owner, recommendation and code forks carry their own class' \
  "$( sed -n 1p "$TMP/c1/styles.txt" )" 'fork decided owner | fork decided recommendation | fork decided code | fork open titleonly' "$( cat "$TMP/c1/styles.txt" )"
check 'the page: three style rules with three distinct colours' "$( sed -n 2p "$TMP/c1/styles.txt" )" '3 3'
check 'the page: the card-less fork is drawn by title, with nothing to pick' "$( sed -n 3p "$TMP/c1/styles.txt" )" 'False True'
check 'the page reads the recommendation from card.recommendation.option' \
  "$( grep -c 'return f.card ? f.card.recommendation.option : null;' "$PAGE" | tr -d ' ' )" 1
dm render "$FIX/impact-map-11-forks.json" --expect 11 --out "$TMP/c1/again.html"
if cmp -s "$PAGE" "$TMP/c1/again.html"; then pass 'a re-render is byte-identical'; else fail 'a re-render differs'; fi

# ---------------------------------------------------------------------------
printf 'F3: saved answers become fork statuses; only --final takes the recommendation\n'
# ---------------------------------------------------------------------------
# answers-map.json (fork ids ESAS-1-F<n>): F1-F3 open, F4 posted as
# decided(recommendation), F5 moot, F6 decided(recommendation). answers/: F1
# picks A, F3 is a comment with no pick, F4 picks A, F5 (moot) carries a stale
# pick. F2 and F6 are unanswered.
ANS="$FIX/answers"
mkdir -p "$TMP/f3"

# forks <map> — one `id:kind:source:option` per fork, in map order, space-joined.
forks(){
  python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
print(" ".join(":".join([f["id"], f["status"]["kind"], f["status"].get("source", "-"), f["status"].get("option", "-")]) for f in m["forks"]))' "$1" 2>&1
}

cp "$FIX/answers-map.json" "$TMP/f3/map.json"
dm apply-answers "$TMP/f3/map.json" "$ANS"
check 'apply-answers: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'apply-answers: exit 0' "$rc" 0
check 'apply-answers: final=false' "$( attr "$LINE" final )" false "$LINE"
check 'apply-answers: names the map it updated' "$( attr "$LINE" map )" "$TMP/f3/map.json" "$LINE"
check 'apply-answers: picked -> decided(owner), unanswered and comment-only stay open, moot survives' \
  "$( forks "$TMP/f3/map.json" )" \
  'ESAS-1-F1:decided:owner:A ESAS-1-F2:open:-:- ESAS-1-F3:open:-:- ESAS-1-F4:decided:owner:A ESAS-1-F5:moot:-:- ESAS-1-F6:decided:recommendation:B'
check 'apply-answers: counts open'           "$( attr "$LINE" open )" 2 "$LINE"
check 'apply-answers: counts decided(owner)' "$( attr "$LINE" owner )" 2 "$LINE"
check 'apply-answers: counts decided(recommendation)' "$( attr "$LINE" recommendation )" 1 "$LINE"
check 'apply-answers: counts moot'           "$( attr "$LINE" moot )" 1 "$LINE"
check 'apply-answers: names the comment-only fork' "$( attr "$LINE" commented )" ESAS-1-F3 "$LINE"
check 'apply-answers: surfaces the comment text' \
  "$( grep -c '^comment ESAS-1-F3: Does B still hold if the store is lost?$' "$OUT" | tr -d ' ' )" 1 "$( cat "$OUT" )"
check 'apply-answers: moot keeps its reason' \
  "$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["forks"][4]["status"].get("reason"))' "$TMP/f3/map.json" 2>&1 )" \
  'Superseded by ESAS-1-F1.'

# The negative gate: without --final, no fork that was not already
# decided(recommendation) becomes one — F6 is the only one before and after.
check 'without --final: no fork is converted to decided(recommendation)' \
  "$( python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
print(",".join(f["id"] for f in m["forks"] if f["status"].get("source") == "recommendation") or "none")' "$TMP/f3/map.json" 2>&1 )" ESAS-1-F6

# A second pass without --final is a fixed point.
cp "$TMP/f3/map.json" "$TMP/f3/pass1.json"
dm apply-answers "$TMP/f3/map.json" "$ANS"
if cmp -s "$TMP/f3/pass1.json" "$TMP/f3/map.json"; then
  pass 'apply-answers twice: the second pass changes nothing'
else
  fail 'apply-answers twice: the second pass changed the map' "$( forks "$TMP/f3/map.json" )"
fi

dm apply-answers "$TMP/f3/map.json" "$ANS" --final
check 'apply-answers --final: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'apply-answers --final: final=true' "$( attr "$LINE" final )" true "$LINE"
check 'apply-answers --final: remaining open -> decided(recommendation), owner picks and moot kept' \
  "$( forks "$TMP/f3/map.json" )" \
  'ESAS-1-F1:decided:owner:A ESAS-1-F2:decided:recommendation:B ESAS-1-F3:decided:recommendation:B ESAS-1-F4:decided:owner:A ESAS-1-F5:moot:-:- ESAS-1-F6:decided:recommendation:B'
check 'apply-answers --final: open=0' "$( attr "$LINE" open )" 0 "$LINE"
check 'apply-answers --final: moot=1' "$( attr "$LINE" moot )" 1 "$LINE"

# --final straight from the author's map, in one pass, reaches the same statuses.
cp "$FIX/answers-map.json" "$TMP/f3/once.json"
dm apply-answers "$TMP/f3/once.json" "$ANS" --final
check 'apply-answers --final in one pass: same statuses' "$( forks "$TMP/f3/once.json" )" "$( forks "$TMP/f3/map.json" )"

# The folded map is still a valid map.
dm render "$TMP/f3/map.json" --expect 6 --out "$TMP/f3/page.html"
check 'the folded map renders' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"

# An empty answers dir (nothing saved yet) changes nothing.
mkdir -p "$TMP/f3/empty"
cp "$FIX/answers-map.json" "$TMP/f3/untouched.json"
dm apply-answers "$TMP/f3/untouched.json" "$TMP/f3/empty"
check 'an empty answers dir: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'an empty answers dir: open=3' "$( attr "$LINE" open )" 3 "$LINE"
check 'an empty answers dir: commented=none' "$( attr "$LINE" commented )" none "$LINE"

# Refusals never lose the author's map (D3): it is byte-identical afterwards.
# map_intact <description> <path>
map_intact(){
  if cmp -s "$FIX/answers-map.json" "$2"; then pass "$1"; else fail "$1" "$( forks "$2" )"; fi
}
refuse_answers(){
  yd=$1 yreason=$2 ydir=$3; shift 3
  cp "$FIX/answers-map.json" "$TMP/f3/author.json"
  expect_error "$yd" "$yreason" apply-answers "$TMP/f3/author.json" "$ydir" "$@"
  map_intact "$yd: the map is untouched" "$TMP/f3/author.json"
}
mkbad(){ rm -rf "$TMP/f3/bad"; mkdir -p "$TMP/f3/bad"; cp "$ANS"/*.json "$TMP/f3/bad/"; }

mkbad; printf '{"pick":"Z","comment":"","updatedAt":"x"}\n' > "$TMP/f3/bad/ESAS-1-F2.json"
refuse_answers 'a pick that is not an option id' unknown-pick "$TMP/f3/bad" --final
check 'a pick that is not an option id: names the fork' "$( attr "$LINE" id )" ESAS-1-F2 "$LINE"
mkbad; printf '{"pick":"A","comment":"","updatedAt":"x"}\n' > "$TMP/f3/bad/ESAS-1-F9.json"
refuse_answers 'an answer for a fork the map does not hold' unknown-fork "$TMP/f3/bad" --final
check 'an answer for a fork the map does not hold: names it' "$( attr "$LINE" id )" ESAS-1-F9 "$LINE"
mkbad; printf '{"pick":' > "$TMP/f3/bad/ESAS-1-F2.json"
refuse_answers 'an unparseable answer' answer-unparseable "$TMP/f3/bad"
mkbad; printf 'x\n' > "$TMP/f3/bad/ESAS-1-F2"
refuse_answers 'a file that is not <forkId>.json' answer-unexpected-file "$TMP/f3/bad"
refuse_answers 'a missing answers dir' answers-dir-missing "$TMP/f3/nope"
expect_error 'apply-answers with no answers dir' missing-answers apply-answers "$TMP/f3/author.json"

# ---------------------------------------------------------------------------
printf 'D5: apply-answers over v2 — overturns, title-only forks, moot, the map id\n'
# ---------------------------------------------------------------------------
mkdir -p "$TMP/d5"
# amap <name> <python statements over m> — a mutated copy of answers-map.json
# at $TMP/d5/<name>.json; the statements come from this file only.
amap(){
  python3 - "$FIX/answers-map.json" "$TMP/d5/$1.json" "$2" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
exec(sys.argv[3])
with open(sys.argv[2], "w") as fh:
    json.dump(m, fh, indent=2)
PY
}
# adir <name> [<forkId> <json>]… — a fresh answers dir holding exactly these answers.
adir(){
  zdir="$TMP/d5/$1"; shift
  rm -rf "$zdir"; mkdir -p "$zdir"
  while [ $# -ge 2 ]; do printf '%s\n' "$2" > "$zdir/$1.json"; shift 2; done
}
# refuse_d5 <description> <reason> <map> <answers-dir> [flags…] — refused, map byte-identical.
refuse_d5(){
  wd=$1 wreason=$2 wmap=$3 wdir=$4; shift 4
  cp "$wmap" "$TMP/d5/before.json"
  expect_error "$wd" "$wreason" apply-answers "$wmap" "$wdir" "$@"
  if cmp -s "$TMP/d5/before.json" "$wmap"; then pass "$wd: the map is byte-identical"; else fail "$wd: the map changed" "$( forks "$wmap" )"; fi
}

# F2 loses its card: a title-only (locked) fork.
amap titleonly 'del m["forks"][1]["card"]'
adir pick-titleonly ESAS-1-F2 '{"pick":"A","comment":"","updatedAt":"x"}'
refuse_d5 'a pick on a card-less fork' fork-title-only "$TMP/d5/titleonly.json" "$TMP/d5/pick-titleonly"
check 'a pick on a card-less fork: names it' "$( attr "$LINE" id )" ESAS-1-F2 "$LINE"

adir none
refuse_d5 '--final while a card-less fork is open' title-only-open "$TMP/d5/titleonly.json" "$TMP/d5/none" --final
check '--final while a card-less fork is open: names it' "$( attr "$LINE" id )" ESAS-1-F2 "$LINE"

# Without --final a card-less open fork is fine, and a comment on it is surfaced.
adir comment-titleonly ESAS-1-F2 '{"pick":null,"comment":"when does this unlock?","updatedAt":"x"}'
dm apply-answers "$TMP/d5/titleonly.json" "$TMP/d5/comment-titleonly"
check 'a comment on a card-less fork without --final: ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"

# An overturn of a code decision: F6 posted as decided(code).
amap code 'm["forks"][5]["status"] = {"kind": "decided", "source": "code", "option": "B"}'
cp "$TMP/d5/code.json" "$TMP/d5/code-kept.json"
dm apply-answers "$TMP/d5/code-kept.json" "$TMP/d5/none"
check 'apply-answers: counts decided(code)' "$( attr "$LINE" code )" 1 "$LINE" "$( cat "$OUT" )"
check 'apply-answers: otherMap=0 when no answer names another map' "$( attr "$LINE" otherMap )" 0 "$LINE"
adir overturn ESAS-1-F6 '{"pick":"A","comment":"","updatedAt":"x"}'
dm apply-answers "$TMP/d5/code.json" "$TMP/d5/overturn"
check 'a pick over decided(code): outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'a pick over decided(code) -> decided(owner) on the pick' \
  "$( forks "$TMP/d5/code.json" | tr ' ' '\n' | grep '^ESAS-1-F6:' )" 'ESAS-1-F6:decided:owner:A'
check 'a pick over decided(code): code=0' "$( attr "$LINE" code )" 0 "$LINE"

# A moot fork with a pick naming no option is left exactly as it is, no refusal.
cp "$FIX/answers-map.json" "$TMP/d5/moot.json"
adir moot-bad ESAS-1-F5 '{"pick":"Z","comment":"","updatedAt":"x"}'
dm apply-answers "$TMP/d5/moot.json" "$TMP/d5/moot-bad" --final
check 'an invalid pick on a moot fork: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'an invalid pick on a moot fork: the fork keeps its moot status' \
  "$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["forks"][4]["status"])' "$TMP/d5/moot.json" 2>&1 )" \
  "{'kind': 'moot', 'reason': 'Superseded by ESAS-1-F1.'}"

# Answers carry the map id: another map's answer is skipped and counted, never
# applied and never checked (its fork and pick may name nothing here).
amap withid 'm["mapId"] = "ESAS-1"'
adir other ESAS-1-F1 '{"pick":"A","comment":"","updatedAt":"x","map":"other"}' \
  ESAS-1-F9 '{"pick":"Z","comment":"","updatedAt":"x","map":"other"}' \
  ESAS-1-F2 '{"pick":"A","comment":"","updatedAt":"x","map":"ESAS-1"}' \
  ESAS-1-F3 '{"pick":"A","comment":"","updatedAt":"x"}'
dm apply-answers "$TMP/d5/withid.json" "$TMP/d5/other"
check "answers for map 'other': outcome=ok" "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check "answers for map 'other': otherMap=2" "$( attr "$LINE" otherMap )" 2 "$LINE"
check "an answer for map 'other' is not applied; the map's own and an unmarked one are" \
  "$( forks "$TMP/d5/withid.json" | cut -d' ' -f1-3 )" 'ESAS-1-F1:open:-:- ESAS-1-F2:decided:owner:A ESAS-1-F3:decided:owner:A'
# A map with no mapId: any answer that names a map names another one.
cp "$FIX/answers-map.json" "$TMP/d5/noid.json"
adir named ESAS-1-F1 '{"pick":"A","comment":"","updatedAt":"x","map":"ESAS-1"}'
dm apply-answers "$TMP/d5/noid.json" "$TMP/d5/named"
check 'a map with no mapId: an answer naming a map is otherMap, not applied' "$( attr "$LINE" otherMap ):$( attr "$LINE" owner )" 1:0 "$LINE" "$( cat "$OUT" )"
adir badmap ESAS-1-F1 '{"pick":"A","comment":"","updatedAt":"x","map":7}'
refuse_d5 'an answer whose map is not a string' answer-malformed "$TMP/d5/withid.json" "$TMP/d5/badmap"

# The page's writer stamps the map id when the map carries one.
dm render "$TMP/d5/withid.json" --expect 6 --out "$TMP/d5/page.html"
check 'the page: the answer writer adds map: MAP.mapId when set' \
  "$( grep -c 'if (MAP.mapId) doc.map = MAP.mapId;' "$TMP/d5/page.html" | tr -d ' ' )" 1

# ---------------------------------------------------------------------------
printf 'D6: write — a full map on stdin, validated, atomically replaced\n'
# ---------------------------------------------------------------------------
mkdir -p "$TMP/w"
# dmin <stdin-file> <args…> — dm with stdin read from a file.
dmin(){
  zin=$1; shift
  ( cd "$TMP" && "$DM_SH" "$DM" "$@" < "$zin" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
}
# canonical <in> <out> — the formatting apply-answers writes, computed independently.
canonical(){
  python3 -c '
import json, sys
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(json.load(open(sys.argv[1], encoding="utf-8")), fh, indent=2, ensure_ascii=False)
    fh.write("\n")' "$1" "$2"
}

dmin "$FIX/decision-3-forks.json" write "$TMP/w/new.json"
check 'write a valid map: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( cat "$OUT" )"
check 'write: verb=write' "$( attr "$LINE" verb )" write "$LINE"
check 'write: forks=3' "$( attr "$LINE" forks )" 3 "$LINE"
check 'write: map=<target>' "$( attr "$LINE" map )" "$TMP/w/new.json" "$LINE"
check 'write: exit 0' "$rc" 0
canonical "$FIX/decision-3-forks.json" "$TMP/w/canonical.json"
if cmp -s "$TMP/w/canonical.json" "$TMP/w/new.json"; then pass 'write: the file equals the canonical output'; else fail 'write: the file is not canonical'; fi
cp "$TMP/w/new.json" "$TMP/w/refold.json"
dm apply-answers "$TMP/w/refold.json" "$TMP/d5/none"
if cmp -s "$TMP/w/new.json" "$TMP/w/refold.json"; then pass 'write and apply-answers share one formatting'; else fail 'write and apply-answers format differently'; fi
check 'write leaves no temp file behind' "$( find "$TMP/w" -name '.design-map-*' | wc -l | tr -d ' ' )" 0

# refuse_write <description> <reason> <stdin-file> — an existing target stays
# byte-identical, and an absent one is not created.
refuse_write(){
  vd=$1 vreason=$2 vin=$3
  cp "$FIX/answers-map.json" "$TMP/w/target.json"
  dmin "$vin" write "$TMP/w/target.json"
  check "$vd: outcome=error" "$( attr "$LINE" outcome )" error "$LINE" "$( cat "$OUT" )"
  check "$vd: reason" "$( attr "$LINE" reason )" "$vreason" "$LINE"
  check "$vd: exit 2" "$rc" 2
  if cmp -s "$FIX/answers-map.json" "$TMP/w/target.json"; then pass "$vd: the target is byte-identical"; else fail "$vd: the target changed"; fi
  dmin "$vin" write "$TMP/w/absent.json"
  check "$vd (no target yet): reason" "$( attr "$LINE" reason )" "$vreason" "$LINE"
  if [ -e "$TMP/w/absent.json" ]; then fail "$vd: a target was created"; else pass "$vd: no target is created"; fi
}
refuse_write 'write a schema-invalid map' schema-invalid "$FIX/v1-map.json"
refuse_write 'write a map with a bare actor' bare-actor "$FIX/bare-actor.json"
amap dangling 'm["forks"][0]["restsOn"] = ["ESAS-1-F99"]'
refuse_write 'write a semantically invalid map' dangling-ref "$TMP/d5/dangling.json"
printf '{"structureVersion":' > "$TMP/w/trunc.json"
refuse_write 'write unparseable stdin' map-unparseable "$TMP/w/trunc.json"
dmin "$FIX/decision-3-forks.json" write
check 'write with no target: reason=missing-map' "$( attr "$LINE" reason )" missing-map "$LINE"
dmin "$FIX/decision-3-forks.json" write "$TMP/w/no-such-dir/m.json"
check 'write into a missing directory: outcome=error reason=map-dir-missing' \
  "$( attr "$LINE" outcome ):$( attr "$LINE" reason )" error:map-dir-missing "$LINE"
dmin "$FIX/decision-3-forks.json" write --map "$TMP/w/flag.json"
check 'write takes no --map flag' "$( attr "$LINE" reason )" unknown-flag-map "$LINE"

# D5: the page marks a card done only when it carries a pick; a comment-only
# answer keeps the card open, as the fold does.
check 'the page: a comment-only answer is not done' \
  "$( grep -c 'if (answers\[id\] && answers\[id\].pick) return "done";' "$TMP/f3/page.html" | tr -d ' ' )" 1

# ---------------------------------------------------------------------------
# skills/design-map/SKILL.md — presence oracle, in the style of
# scripts/test-esas-design.sh (assert_md/refute_md). This is prose, not a
# script: it catches deletion, not wrongness, as the design's own test-seams
# table says of this exact case.
# ---------------------------------------------------------------------------
printf '\nskills/design-map/SKILL.md — the F4 disarm and the two invariants\n'

SKILL_MD="$ROOT/plugins/bett3r-ai-workflow/skills/design-map/SKILL.md"

# Failures name the file repo-relative, mirroring test-esas-design.sh's own
# helper (two files across the plugin are both called SKILL.md).
assert_md(){
  file=$1
  description=$2
  needle=$3
  if [ ! -f "$file" ]; then
    fail "$description" "no file at $file"
  elif grep -qF -- "$needle" "$file"; then
    pass "$description"
  else
    fail "$description" "not found in ${file#"$ROOT"/}: $needle"
  fi
}

refute_md(){
  file=$1
  description=$2
  needle=$3
  if [ ! -f "$file" ]; then
    fail "$description" "no file at $file"
  elif grep -qF -- "$needle" "$file"; then
    fail "$description" "found in ${file#"$ROOT"/}, and should not be: $needle"
  else
    pass "$description"
  fi
}

assert_md "$SKILL_MD" 'render, with --expect as the count of the grilled tree' \
  '--expect is the count of the grilled tree'
assert_md "$SKILL_MD" 'an optional check-page before publish' \
  'check-page'
assert_md "$SKILL_MD" 'publishing declares capabilities: {db: {}}' \
  'capabilities: {db: {}}'
assert_md "$SKILL_MD" 'readback is read_db over the answers collection' \
  'read_db'
assert_md "$SKILL_MD" 'answers materialise one file per fork, D10 layout' \
  '<answers-dir>/<forkId>.json'
assert_md "$SKILL_MD" 'apply-answers is named as the fold verb' \
  'apply-answers'
assert_md "$SKILL_MD" 'printed comments are resolved before --final (D8)' \
  'before running --final'

# The F4 disarm: a comment sent to Claude on a watched artifact arrives inside
# the platform's NOT-USER-INPUT banner, and reading it as a refusal ends the
# gesture silently while the store already holds the answer.
assert_md "$SKILL_MD" 'the banner is named as the design names it' \
  'NOT USER INPUT'
assert_md "$SKILL_MD" 'the disarm sentence itself, verbatim from the design' \
  'the notification is the doorbell'
assert_md "$SKILL_MD" 'the store is named as where the answer actually lives' \
  'the answers are in the store'
assert_md "$SKILL_MD" 'the banner-wrapped comment is read as not a refusal' \
  'is not a refusal'
refute_md "$SKILL_MD" 'the disarm is not inverted into reading the comment as a refusal' \
  'is a refusal'
# A wake may fold, never finalize: --final converts every open fork to
# decided(recommendation), erasing let-stand vs never-reached. It and any D8
# sign-off need the owner's word in the terminal.
assert_md "$SKILL_MD" 'a wake never runs --final' \
  'A wake never runs `--final`'
assert_md "$SKILL_MD" '--final and the D8 comment resolution are pinned to the terminal' \
  'given in the terminal'
assert_md "$SKILL_MD" 'the description forbids --final from a wake too' \
  'A wake never runs --final'
assert_md "$SKILL_MD" 'the read_db document id is the forkId' \
  'the `read_db` document id is the fork id'
assert_md "$SKILL_MD" 'the verdict line is read, not the exit code' \
  'verdict line on stdout, not the exit'

# Slice 4, measured 2026-09-17: the page's own comment box writes
# answers/<forkId>.comment to the db and never notified the session; the
# owner's word in the terminal is the observed trigger. The comment-mode
# thread wake stays unmeasured, and the skill must say so.
assert_md "$SKILL_MD" "the page's comment box is stated never to wake the session" \
  "The page's comment box never wakes the session."
assert_md "$SKILL_MD" 'the description carries the same never-wakes claim' \
  "the page's comment box never wakes the session"
refute_md "$SKILL_MD" 'a page comment is no longer offered as a readback trigger' \
  'or a comment on the page'
assert_md "$SKILL_MD" 'publishing tells the owner to hand back in the terminal' \
  "tell me in the terminal when you're done"
assert_md "$SKILL_MD" 'the comment-mode thread wake is marked unmeasured' \
  'This is not measured'
assert_md "$SKILL_MD" 'out_dir readback lands directly in the D10 layout' \
  'lands **directly**'

# The v2 contract: the vocabulary copy and the structure file are two files,
# the copy is never hand-edited, and validate / not-grounded are named.
assert_md "$SKILL_MD" 'the structure file is named' 'map-structure.schema.json'
assert_md "$SKILL_MD" 'the vocabulary copy is never hand-edited' 'Never hand-edit `map.schema.json`'
assert_md "$SKILL_MD" 'the validate verb is documented' 'design-map validate <map.json>'
assert_md "$SKILL_MD" 'the not-grounded refusal is named' 'reason=not-grounded'
assert_md "$SKILL_MD" 'the v2 status shape is documented' '{kind: decided, source, option}'
refute_md "$SKILL_MD" 'the v1 layout field is gone' 'impactMap'
assert_md "$SKILL_MD" 'the write verb is documented, map on stdin' 'design-map write <map.json> < draft.json'
assert_md "$SKILL_MD" 'write is named the only structural authoring path' 'the only structural authoring path'
assert_md "$SKILL_MD" 'the fork-title-only refusal is named' 'reason=fork-title-only'
assert_md "$SKILL_MD" 'the title-only-open refusal is named' 'reason=title-only-open'
assert_md "$SKILL_MD" 'otherMap is named' 'otherMap='

# Two invariants, carried over from esas-design because they are properties of
# turn-based answering rather than of any one transport.
assert_md "$SKILL_MD" 'invariant 1: a wake with nothing new is a normal outcome' \
  'Tolerate an empty wake'
assert_md "$SKILL_MD" 'invariant 1: an empty readback is not an error' \
  'is a normal outcome, not an error'
assert_md "$SKILL_MD" 'invariant 2: nothing is proposed off a half-answered fork' \
  'Never propose from partial answers'

# ---------------------------------------------------------------------------
printf 'the verdict line, not the exit code\n'
# ---------------------------------------------------------------------------
expect_error 'an unreadable map path' map-unreadable \
  render "$TMP/does-not-exist.json" --expect 1 --out "$TMP/x.html"
expect_error 'an unknown verb' unknown-verb draw "$FIX/decision-3-forks.json"

( cd "$TMP" && "$DM_SH" "$DM" render "$FIX/impact-map-11-forks.json" --expect 12 --out "$TMP/w.html"; true ) > "$OUT" 2>&1
rc=$?
LINE=$( verdict "$OUT" )
check 'a wrapper swallowing the exit status: exit reads 0' "$rc" 0
check 'a wrapper swallowing the exit status: the line still reads error' "$( attr "$LINE" outcome )" error "$LINE"

printf 'Traceback (most recent call last):\n' > "$TMP/crash"
check 'a run that printed no verdict line parses as no verdict' "$( verdict "$TMP/crash" || printf none )" none

printf '\n'
if [ "$skipped" -gt 0 ]; then
  printf '\033[33m!! %d skipped (SKIP reason=no-esas-checkout) — not counted as passed\033[0m\n' "$skipped"
fi
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
