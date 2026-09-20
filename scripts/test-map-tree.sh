#!/bin/sh
# Oracle for `bin/map-tree` — the decision text of a design.md (or ticket
# block) is a GENERATED region: a per-ticket projection of map.json, rendered
# deterministically between a `map-tree:v1` marker pair that carries two hashes.
# `src=` covers the projection, so an overturned fork reads `stale`; `out=`
# covers the body, so a hand edit inside the region reads `tampered` (ESAS-163
# D2/D3). A tampered region is never silently overwritten: `write` refuses by
# default and `--on-tamper displace` keeps the edited body verbatim under a
# dated heading (F2).
#
# Every case drives the real launcher against the fixtures in
# scripts/fixtures/map-tree/ and reads the `MAP-TREE:v1` verdict line
# (ADR-004), never the exit code alone.
#
# Run locally:  sh scripts/test-map-tree.sh
# MT_SH selects the interpreter that runs the `bin/map-tree` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
MT="$ROOT/plugins/bett3r-ai-workflow/bin/map-tree"
LINT="$ROOT/plugins/bett3r-ai-workflow/bin/resolved-marker-lint"
MT_SH=${MT_SH:-sh}
FIX="$ROOT/scripts/fixtures/map-tree"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/map-tree-test.XXXXXX" ) || exit 1
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
# value is refused, so a step that never ran cannot equal an empty actual.
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

# holds <description> <command…> — passes when the command exits 0.
holds(){
  hd=$1; shift
  if "$@" > /dev/null 2>&1; then pass "$hd"; else fail "$hd" "command failed: $*"; fi
}

# mt <args…> — run the launcher, stdout+stderr to $OUT, real exit status in $rc.
OUT="$TMP/out"
mt(){
  ( cd "$TMP" && "$MT_SH" "$MT" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
}

# verdict <file> — the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^MAP-TREE:v1 outcome=[a-z]+( [A-Za-z_-]+=[^ ]*)*$'
}

attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# expect <description> <outcome> <exit> [reason] — after an `mt` call.
expect(){
  xd=$1 xo=$2 xrc=$3 xr=$4
  if [ -z "$LINE" ]; then
    fail "$xd" 'no verdict line' "$( tail -n 5 "$OUT" )"
    return
  fi
  check "$xd: outcome=$xo" "$( attr "$LINE" outcome )" "$xo" "$LINE"
  check "$xd: exit $xrc" "$rc" "$xrc" "$LINE"
  if [ -n "$xr" ]; then check "$xd: reason=$xr" "$( attr "$LINE" reason )" "$xr" "$LINE"; fi
}

# strip_regions <file> — the file with every map-tree:v1 region removed.
strip_regions(){
  awk '/^<!-- map-tree:v1 /{skip=1} !skip{print} /^<!-- \/map-tree:v1 -->$/{skip=0}' "$1"
}

H='## Resolved decision tree'
MAP="$FIX/design.map.json"
FLIP="$FIX/design-flipped.map.json"

# ---------------------------------------------------------------------------
printf 'T1: a hand edit inside the region is tampered, refused or displaced (md)\n'
# ---------------------------------------------------------------------------
D="$TMP/t1.md"
cp "$FIX/design.md" "$D"
mt write --map "$MAP" --ticket ESAS-901 "$D" --insert-after "$H"
expect 'first write with --insert-after' written 0
check 'first write: forks=2'          "$( attr "$LINE" forks )" 2 "$LINE"
check 'first write: owner=1'          "$( attr "$LINE" owner )" 1 "$LINE"
check 'first write: recommendation=1' "$( attr "$LINE" recommendation )" 1 "$LINE"
check 'first write: code=0'           "$( attr "$LINE" code )" 0 "$LINE"
check 'first write: open=0'           "$( attr "$LINE" open )" 0 "$LINE"
check 'first write: moot=0'           "$( attr "$LINE" moot )" 0 "$LINE"
check 'first write: region follows the heading' \
  "$( awk -v h="$H" 'p && NF{print substr($0,1,17); exit} $0==h{p=1}' "$D" )" '<!-- map-tree:v1 '
check 'first write: comment marker present' \
  "$( grep -c '^<!-- map-tree:v1 ticket=ESAS-901 gen=2 src=sha256:[0-9a-f]\{64\} out=sha256:[0-9a-f]\{64\} -->$' "$D" )" 1
check 'first write: inline twin present' \
  "$( grep -c '^`map-tree:v1 ticket=ESAS-901 gen=2 src=sha256:[0-9a-f]\{64\} out=sha256:[0-9a-f]\{64\}`$' "$D" )" 1
check 'first write: other ticket fork not projected' "$( grep -c 'ESAS-902-F1' "$D" )" 0

mt check --map "$MAP" --ticket ESAS-901 "$D"
expect 'check after write' fresh 0

cp "$D" "$TMP/t1.before"
mt write --map "$MAP" --ticket ESAS-901 "$D"
expect 'rewrite of a fresh region' written 0
holds 'rewrite of a fresh region: file byte-identical' cmp "$D" "$TMP/t1.before"

sed 's/keeps design-map.py untouched/keeps design-map.py pristine/' "$D" > "$TMP/t1.edit" && cp "$TMP/t1.edit" "$D"
check 'tamper fixture: the word was edited' "$( grep -c 'pristine' "$D" )" 1
cp "$D" "$TMP/t1.tampered"
mt check --map "$MAP" --ticket ESAS-901 "$D"
expect 'check on an edited region' tampered 1
mt write --map "$MAP" --ticket ESAS-901 "$D"
expect 'write (default refuse) on an edited region' tampered 1
holds 'refused write: file byte-identical' cmp "$D" "$TMP/t1.tampered"
mt write --map "$MAP" --ticket ESAS-901 "$D" --on-tamper displace
expect 'write --on-tamper displace' displaced 0
check 'displace: heading after the end marker' \
  "$( awk '/^<!-- \/map-tree:v1 -->$/{e=1; next} e && NF{print; exit}' "$D" | sed 's/[0-9-]*)$/)/' )" \
  '### Displaced from generated section ()'
check 'displace: the edited text kept verbatim' \
  "$( awk '/^### Displaced from generated section \(/{p=1} p' "$D" | grep -c 'keeps design-map.py pristine' )" 1
check 'displace: region no longer holds the edit' \
  "$( awk '/^<!-- map-tree:v1 /{p=1} p{print} /^<!-- \/map-tree:v1 -->$/{p=0}' "$D" | grep -c pristine )" 0
mt check --map "$MAP" --ticket ESAS-901 "$D"
expect 'check after displace' fresh 0

N="$TMP/t1-noregion.md"
cp "$FIX/design.md" "$N"
mt write --map "$MAP" --ticket ESAS-901 "$N"
expect 'write with no region and no --insert-after' error 2 no-region
holds 'no-region write: file byte-identical' cmp "$N" "$FIX/design.md"
mt write --map "$MAP" --ticket ESAS-901 "$N" --insert-after '## Nowhere'
expect 'write --insert-after an absent heading' error 2 heading-not-found
holds 'heading-not-found: file byte-identical' cmp "$N" "$FIX/design.md"
mt check --map "$MAP" --ticket ESAS-901 "$N"
expect 'check with no region' error 2 no-region

mt check --map "$FLIP" --ticket ESAS-901 "$D"
expect 'check against an overturned map' stale 1

sed '/^`map-tree:v1 /s/gen=2/gen=7/' "$D" > "$TMP/twin.md"
mt check --map "$MAP" --ticket ESAS-901 "$TMP/twin.md"
expect 'twins disagree' error 2 twin-mismatch

mt check --map "$FIX/invalid.map.json" --ticket ESAS-901 "$D"
expect 'an invalid map' error 2 map-invalid
mt check --map "$MAP" --ticket ESAS-999 "$D"
expect 'a ticket with no forks' error 2 no-forks

# A region written by the PREVIOUS generation (gen=1, before the resolved_by:
# line moved the projection's shape) reads stale and is re-rendered, never
# refused as a hand edit.
G="$TMP/gen.md"
sed 's/gen=2/gen=1/; s/keeps design-map.py untouched/an older generation wrote this/' "$D" > "$G"
mt check --map "$MAP" --ticket ESAS-901 "$G"
expect 'the previous gen with a different body: re-render, not tamper' stale 1
mt write --map "$MAP" --ticket ESAS-901 "$G"
expect 'write over the previous gen' written 0
mt check --map "$MAP" --ticket ESAS-901 "$G"
expect 'check after the gen re-render' fresh 0

mt render --map "$MAP" --ticket ESAS-901
expect 'render' ok 0
check 'render: body before the verdict' "$( grep -c '^### ESAS-901-F1 — ' "$OUT" )" 1
check 'render: no markers in the body' "$( grep -c 'map-tree:v1' "$OUT" )" 0

# ---------------------------------------------------------------------------
printf 'T1 (jira): a ticket-block region is never displaced\n'
# ---------------------------------------------------------------------------
J="$TMP/t1.ticket-block.md"
cp "$FIX/ticket-block.md" "$J"
mt write --map "$MAP" --ticket ESAS-901 "$J" --dialect jira --insert-after "$H"
expect 'jira first write' written 0
mt check --map "$MAP" --ticket ESAS-901 "$J" --dialect jira
expect 'jira check after write' fresh 0
sed 's/keeps design-map.py untouched/keeps design-map.py pristine/' "$J" > "$TMP/t1j.edit" && cp "$TMP/t1j.edit" "$J"
check 'jira tamper fixture: the word was edited' "$( grep -c 'pristine' "$J" )" 1
cp "$J" "$TMP/t1j.tampered"
mt check --map "$MAP" --ticket ESAS-901 "$J" --dialect jira
expect 'jira check on an edited region' tampered 1
mt write --map "$MAP" --ticket ESAS-901 "$J" --dialect jira
expect 'jira write (default refuse) on an edited region' tampered 1
holds 'jira refused write: file byte-identical' cmp "$J" "$TMP/t1j.tampered"
mt write --map "$MAP" --ticket ESAS-901 "$J" --dialect jira --on-tamper displace
expect 'jira write --on-tamper displace' error 2 displace-not-allowed-jira
holds 'jira displace refusal: file byte-identical' cmp "$J" "$TMP/t1j.tampered"
# The refusal precedes rendering and classification: it fires on an invalid
# map and on a file with no region, where either would otherwise refuse first.
mt write --map "$FIX/invalid.map.json" --ticket ESAS-901 "$J" --dialect jira --on-tamper displace
expect 'jira displace on an invalid map: refused before validation' error 2 displace-not-allowed-jira
cp "$FIX/ticket-block.md" "$TMP/t1j-noregion.md"
mt write --map "$MAP" --ticket ESAS-901 "$TMP/t1j-noregion.md" --dialect jira --on-tamper displace
expect 'jira displace with no region: refused before classification' error 2 displace-not-allowed-jira
holds 'jira displace with no region: file byte-identical' cmp "$TMP/t1j-noregion.md" "$FIX/ticket-block.md"

# ---------------------------------------------------------------------------
printf 'T2: edits outside the region survive a regenerate\n'
# ---------------------------------------------------------------------------
D2="$TMP/t2.md"
cp "$FIX/design.md" "$D2"
mt write --map "$MAP" --ticket ESAS-901 "$D2" --insert-after "$H"
expect 'T2 setup write' written 0
sed 's/^The decision prose is hand-copied and drifts\.$/The prose drifts, edited by hand.  /; s/^- A fork attributed/- An edited risk: a fork attributed/' "$D2" > "$TMP/t2.e" && cp "$TMP/t2.e" "$D2"
check 'T2: outside edits applied' "$( grep -c 'edited' "$D2" )" 2
check 'T2: an outside line keeps trailing whitespace (a splice must not normalise it)' "$( grep -c 'by hand\.  $' "$D2" )" 1
strip_regions "$D2" > "$TMP/t2.outside.before"
mt write --map "$FLIP" --ticket ESAS-901 "$D2"
expect 'write after a flipped fork' written 0
strip_regions "$D2" > "$TMP/t2.outside.after"
holds 'out-of-region bytes identical' cmp "$TMP/t2.outside.before" "$TMP/t2.outside.after"
check 'the flipped choice is rendered' "$( grep -c '^### ESAS-901-F1 — Where the generator lives: A subcommand of design-map$' "$D2" )" 1
mt check --map "$FLIP" --ticket ESAS-901 "$D2"
expect 'check after the flip write' fresh 0

# ---------------------------------------------------------------------------
printf 'T5: a legacy v2 block without a region is left untouched\n'
# ---------------------------------------------------------------------------
L="$TMP/legacy.md"
cp "$FIX/legacy-v2-block.md" "$L"
mt write --map "$MAP" --ticket ESAS-901 "$L"
expect 'write on a legacy block' error 2 no-region
holds 'legacy block byte-identical' cmp "$L" "$FIX/legacy-v2-block.md"
holds 'resolved-marker-lint still exits 0' sh "$LINT" "$L"

# ---------------------------------------------------------------------------
printf 'T6: rendering is deterministic and src ignores key order\n'
# ---------------------------------------------------------------------------
mt render --map "$MAP" --ticket ESAS-901
cp "$OUT" "$TMP/r1"
mt render --map "$MAP" --ticket ESAS-901
holds 'two renders byte-identical' cmp "$OUT" "$TMP/r1"
python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1])), open(sys.argv[2],"w"), sort_keys=True, indent=4)' \
  "$MAP" "$TMP/reordered.map.json"
check 'reordered map differs in bytes' "$( cmp -s "$MAP" "$TMP/reordered.map.json" && echo same || echo differs )" differs
mt check --map "$TMP/reordered.map.json" --ticket ESAS-901 "$D"
expect 'check with the key-reordered map' fresh 0
R="$TMP/t6.md"
cp "$FIX/design.md" "$R"
mt write --map "$TMP/reordered.map.json" --ticket ESAS-901 "$R" --insert-after "$H"
check 'same src from the reordered map' "$( grep '^<!-- map-tree:v1 ' "$R" )" "$( grep '^<!-- map-tree:v1 ' "$TMP/t1.before" )"

# ---------------------------------------------------------------------------
printf 'T7: provenance — code, moot, open, locked\n'
# ---------------------------------------------------------------------------
mt render --map "$FIX/provenance.map.json" --ticket ESAS-903
expect 'render provenance' ok 0
check 'code=1'  "$( attr "$LINE" code )" 1 "$LINE"
check 'moot=1'  "$( attr "$LINE" moot )" 1 "$LINE"
check 'open=1'  "$( attr "$LINE" open )" 1 "$LINE"
check 'owner=0' "$( attr "$LINE" owner )" 0 "$LINE"
check 'forks=3' "$( attr "$LINE" forks )" 3 "$LINE"
check 'code fork heading names the chosen option' \
  "$( grep -c '^### ESAS-903-F1 — Settled by the code: Use the new reader$' "$OUT" )" 1
check 'code fork tagged decided(code)' "$( grep -c 'decided(code)' "$OUT" )" 1
check 'code fork lists its rejected option' \
  "$( grep -c '^- Rejected — Keep the old reader: the reader is already gone (src/reader.ts:12)$' "$OUT" )" 1
check 'moot fork renders its reason' "$( grep -c 'moot — the feature was cut' "$OUT" )" 1
check 'open fork tagged OPEN with its recommendation' "$( grep -c 'OPEN — recommended: Alpha' "$OUT" )" 1

mt render --map "$FIX/locked.map.json" --ticket ESAS-904
expect 'render locked' ok 0
check 'card-less fork renders LOCKED' "$( grep -c 'LOCKED — waits on ESAS-904-F1' "$OUT" )" 1
check 'card-less fork counts as open' "$( attr "$LINE" open )" 1 "$LINE"
check 'decided owner counted' "$( attr "$LINE" owner )" 1 "$LINE"
check 'card-less moot fork renders its reason' "$( grep -c '^moot — the branch was dropped$' "$OUT" )" 1
check 'card-less moot fork is not rendered LOCKED' "$( grep -c 'LOCKED — waits on' "$OUT" )" 1
check 'card-less moot fork counts as moot' "$( attr "$LINE" moot )" 1 "$LINE"

# ---------------------------------------------------------------------------
printf 'T3: overturning ticket A changes only A (md and jira)\n'
# ---------------------------------------------------------------------------
TT="$FIX/two-ticket.map.json"
TO="$FIX/two-ticket-overturned.map.json"
for dialect in md jira; do
  if [ "$dialect" = md ]; then base="$FIX/design.md"; else base="$FIX/ticket-block.md"; fi
  A="$TMP/t3-a.$dialect"; B="$TMP/t3-b.$dialect"
  cp "$base" "$A"; cp "$base" "$B"
  mt write --map "$TT" --ticket ESAS-911 "$A" --dialect "$dialect" --insert-after "$H"
  expect "T3 $dialect: setup write A" written 0
  mt write --map "$TT" --ticket ESAS-912 "$B" --dialect "$dialect" --insert-after "$H"
  expect "T3 $dialect: setup write B" written 0
  check "T3 $dialect: A holds only its fork" "$( grep -c 'ESAS-912-F1' "$A" )" 0
  cp "$A" "$TMP/t3-a.before"; cp "$B" "$TMP/t3-b.before"
  mt check --map "$TO" --ticket ESAS-911 "$A" --dialect "$dialect"
  expect "T3 $dialect: A after overturn" stale 1
  mt check --map "$TO" --ticket ESAS-912 "$B" --dialect "$dialect"
  expect "T3 $dialect: B after overturn" fresh 0
  mt write --map "$TO" --ticket ESAS-911 "$A" --dialect "$dialect"
  expect "T3 $dialect: write A" written 0
  check "T3 $dialect: A's file changed" "$( cmp -s "$A" "$TMP/t3-a.before" && echo same || echo changed )" changed
  mt write --map "$TO" --ticket ESAS-912 "$B" --dialect "$dialect"
  expect "T3 $dialect: write B" written 0
  holds "T3 $dialect: B's file byte-identical" cmp "$B" "$TMP/t3-b.before"
  mt check --map "$TO" --ticket ESAS-911 "$A" --dialect "$dialect"
  expect "T3 $dialect: A fresh after write" fresh 0
done
check 'T3: src is per ticket, the same across dialects' \
  "$( grep '^<!-- map-tree:v1 ' "$TMP/t3-b.jira" | sed 's/ out=.*//' )" \
  "$( grep '^<!-- map-tree:v1 ' "$TMP/t3-b.md" | sed 's/ out=.*//' )"
check 'T3: out differs between dialects' \
  "$( [ "$( grep '^<!-- map-tree:v1 ' "$TMP/t3-b.jira" )" = "$( grep '^<!-- map-tree:v1 ' "$TMP/t3-b.md" )" ] && echo same || echo differs )" differs

# ---------------------------------------------------------------------------
printf 'T8: the jira dialect is flat, table-free and code-spans paths, globs, dunders\n'
# ---------------------------------------------------------------------------
mt render --map "$TT" --ticket ESAS-911
check 'T8 control: md render carries the bare dunder' "$( grep -c '__init__' "$OUT" )" 2
mt render --map "$TT" --ticket ESAS-911 --dialect jira
expect 'T8 jira render' ok 0
cp "$OUT" "$TMP/t8.full"
sed '$d' "$OUT" > "$TMP/t8.body"
check 'T8: body is not empty' "$( [ -s "$TMP/t8.body" ] && echo non-empty )" non-empty
check 'T8: no | table rows' "$( grep -c '^[[:space:]]*|' "$TMP/t8.body" )" 0
check 'T8: no bare __x__ outside backticks' \
  "$( sed 's/`[^`]*`//g' "$TMP/t8.body" | grep -c '__[A-Za-z0-9_]*__' )" 0
check 'T8: no bare glob outside backticks' "$( sed 's/`[^`]*`//g' "$TMP/t8.body" | grep -c '\*\.md' )" 0
check 'T8: no bare path outside backticks' "$( sed 's/`[^`]*`//g' "$TMP/t8.body" | grep -c '[A-Za-z0-9_.]/[A-Za-z0-9_*]' )" 0
check 'T8: the dunder is code-spanned' "$( grep -c '`__init__`' "$TMP/t8.body" )" 2
check 'T8: the glob is code-spanned' "$( grep -c '`\*\.md`' "$TMP/t8.body" )" 1
check 'T8: the path is code-spanned' "$( grep -c '`plugins/bett3r-ai-workflow/scripts`' "$TMP/t8.body" )" 1
check 'T8: every non-blank line is a flat bullet' "$( grep -v '^$' "$TMP/t8.body" | grep -vc '^- ' )" 0
check 'T8: no headings' "$( grep -c '^#' "$TMP/t8.body" )" 0
check 'T8: no bold run across lines (even ** per line outside code)' \
  "$( sed 's/`[^`]*`//g' "$TMP/t8.body" | awk '{n=gsub(/\*\*/,"&"); if (n%2) c++} END{print c+0}' )" 0
check 'T8: decided fork keeps its rejected option' "$( grep -c '^- Rejected — A subcommand of design-map: ' "$TMP/t8.body" )" 1
mt render --map "$TT" --ticket ESAS-911 --dialect jira
holds 'T8: two jira renders byte-identical' cmp "$OUT" "$TMP/t8.full"

# Hostile text fields: newlines (F1) and pre-existing backticks (F2). The map
# is synthesized from $TT so design-map validate still accepts it.
python3 - "$TT" "$TMP/t8-edge.map.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
f = m["forks"][0]
f["title"] = "Where the hook\nreads **files**"
f["card"]["recommendation"]["why"] = "x\ny and docs/a.md"
f["card"]["options"][0]["label"] = "a`b/c`"
f["card"]["options"][0]["rejectedBecause"] = "a lone ` backtick then docs/x.md tail"
f["card"]["options"][1]["label"] = "see `docs/a.md here"
json.dump(m, open(sys.argv[2], "w"))
PY
mt render --map "$TMP/t8-edge.map.json" --ticket ESAS-911 --dialect jira
expect 'T8 edge: newline and backtick fields render' ok 0
sed '$d' "$OUT" > "$TMP/t8e.body"
check 'T8 edge: no Traceback' "$( grep -c Traceback "$OUT" )" 0
check 'T8 edge: every non-blank line is a flat bullet' "$( grep -v '^$' "$TMP/t8e.body" | grep -vc '^- ' )" 0
check 'T8 edge: newline in title collapses to one bold line' \
  "$( grep -c '^- \*\*ESAS-911-F1 — Where the hook reads `\*\*files\*\*`: ' "$TMP/t8e.body" )" 1
check 'T8 edge: newline in why collapses to a space' "$( grep -c '^- Why: x y and `docs/a.md`$' "$TMP/t8e.body" )" 1
check 'T8 edge: even ** per line outside code' \
  "$( sed 's/`[^`]*`//g' "$TMP/t8e.body" | awk '{n=gsub(/\*\*/,"&"); if (n%2) c++} END{print c+0}' )" 0
check 'T8 edge: an existing code span stays intact' "$( grep -c 'a`b/c`' "$TMP/t8e.body" )" 1
check 'T8 edge: no span wrapped around a backtick word' "$( grep -c '``a`\|`a`b' "$TMP/t8e.body" )" 0
check 'T8 edge: a lone backtick survives verbatim' "$( grep -c 'a lone ` backtick then ' "$TMP/t8e.body" )" 1
check 'T8 edge: beside a stray backtick the span is double-backtick' \
  "$( grep -c 'then `` docs/x.md `` tail ' "$TMP/t8e.body" )" 1
check 'T8 edge: a path glued to an unclosed backtick is left bare' \
  "$( grep -c '^- \*\*ESAS-911-F1 — Where the hook reads `\*\*files\*\*`: see `docs/a.md here\*\* — decided(owner)$' "$TMP/t8e.body" )" 1
check 'T8 edge: no span wrapped around a backtick-glued path' "$( grep -c '`` `docs/a.md ``' "$TMP/t8e.body" )" 0

# ---------------------------------------------------------------------------
printf 'T9: one machine-read resolved_by: line per decided fork, and only there\n'
# ---------------------------------------------------------------------------
# The census that parses these lines lives in ANOTHER repository:
# bett3r-xp-layer, ticket XL-24. Neither that ticket nor that repo's ADR-053
# s10 — which is where the five-value grammar `atom:<id> | neotoma:<entity_id>
# | human | code | recommendation` is specified — resolves here, and no
# `cross-repo <repo>@<sha>:<path>` citation (ADR-010's spelling) is given for
# them because this repo pins no sha of that tree. The in-repo record is
# `docs/adr/ADR-014-the-md-projection-carries-one-machine-read-line-per-decided-fork.md`.
# The value is status.resolvedBy verbatim where the map carries it, else it is
# minted from status.source: owner -> human, code -> code, recommendation ->
# recommendation (XL-62-F1 option A, docs/prs/XL-62/ticket-block.md).

# region_body <file> — the body between the inline twin and the inline end
# marker, i.e. exactly the bytes out= covers.
region_body(){
  awk '/^`map-tree:v1 /{p=1; next} /^`\/map-tree:v1`$/{p=0} p' "$1"
}

# section_of <file> <fork-id> — the rendered `###` section for one fork.
section_of(){
  awk -v id="$2" '/^### /{p = (index($0, "### " id " ") == 1)} p' "$1"
}

W9="$TMP/t9.md"
cp "$FIX/design.md" "$W9"
mt write --map "$MAP" --ticket ESAS-901 "$W9" --insert-after "$H"
expect 'T9 write ESAS-901' written 0
region_body "$W9" > "$TMP/t9-901.body"
check 'T9: an owner-decided fork with no resolvedBy mints human' \
  "$( grep -c '^resolved_by: human$' "$TMP/t9-901.body" )" 1
check 'T9: a recommendation-decided fork with no resolvedBy mints recommendation' \
  "$( grep -c '^resolved_by: recommendation$' "$TMP/t9-901.body" )" 1
check 'T9: ESAS-901 carries one line per decided fork (forks - open - moot)' \
  "$( grep -c '^resolved_by: ' "$TMP/t9-901.body" )" \
  "$(( $( attr "$LINE" forks ) - $( attr "$LINE" open ) - $( attr "$LINE" moot ) ))" "$LINE"

W5="$TMP/t9-905.md"
cp "$FIX/design.md" "$W5"
mt write --map "$MAP" --ticket ESAS-905 "$W5" --insert-after "$H"
expect 'T9 write ESAS-905 (all four fork kinds at once)' written 0
check 'T9: ESAS-905 forks=5'          "$( attr "$LINE" forks )" 5 "$LINE"
check 'T9: ESAS-905 owner=1'          "$( attr "$LINE" owner )" 1 "$LINE"
check 'T9: ESAS-905 code=1'           "$( attr "$LINE" code )" 1 "$LINE"
check 'T9: ESAS-905 open=2'           "$( attr "$LINE" open )" 2 "$LINE"
check 'T9: ESAS-905 moot=1'           "$( attr "$LINE" moot )" 1 "$LINE"
check 'T9: the verdict line key set is unchanged (COUNT_KEYS)' \
  "$( printf '%s\n' "$LINE" | tr ' ' '\n' | sed -n 's/=.*//p' | tr '\n' ' ' )" \
  'outcome verb ticket forks owner code recommendation open moot path ' "$LINE"
region_body "$W5" > "$TMP/t9-905.body"
check 'T9: a code-decided fork with no resolvedBy mints code' \
  "$( grep -c '^resolved_by: code$' "$TMP/t9-905.body" )" 1
check 'T9: a resolvedBy citation is emitted verbatim' \
  "$( grep -c '^resolved_by: atom:xp-0042$' "$TMP/t9-905.body" )" 1
check 'T9: the citation wins — that owner fork does not also mint human' \
  "$( grep -c '^resolved_by: human$' "$TMP/t9-905.body" )" 0
check 'T9: ESAS-905 carries one line per decided fork (forks - open - moot)' \
  "$( grep -c '^resolved_by: ' "$TMP/t9-905.body" )" 2 "$LINE"
check 'T9: no resolved_by line for the open fork' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F3 | grep -c '^resolved_by: ' )" 0
check 'T9: no resolved_by line for the moot fork' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F4 | grep -c '^resolved_by: ' )" 0
check 'T9: no resolved_by line for the LOCKED (card-less) fork' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F5 | grep -c '^resolved_by: ' )" 0
check 'T9 control: the open fork section was found' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F3 | grep -c '^OPEN — recommended: Alpha$' )" 1
check 'T9 control: the moot fork section was found' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F4 | grep -c '^moot — the feature was cut$' )" 1
check 'T9 control: the LOCKED fork section was found' \
  "$( section_of "$TMP/t9-905.body" ESAS-905-F5 | grep -c '^LOCKED — waits on ESAS-905-F1$' )" 1
check 'T9: no resolved_by line is indented (the census reads column 0 only)' \
  "$( grep -c '^[[:space:]][[:space:]]*resolved_by: ' "$TMP/t9-905.body" )" 0

# The census reads a committed design.md only, never a Jira ticket block, so
# render_jira stays out of its reach by construction.
mt render --map "$MAP" --ticket ESAS-905 --dialect jira
expect 'T9 jira render' ok 0
check 'T9: the jira dialect emits no resolved_by line' "$( grep -c 'resolved_by' "$OUT" )" 0

# Conformance: the md body is checked in, so any interior spacing or ordering
# change around the resolved_by: line is a reviewable diff. This is the only
# drift signal this repo can carry for a grammar whose reader lives in another
# repo — `packages/xp-mcp/src/resolved-by.ts` in bett3r-xp-layer, a path that
# does not resolve here by construction (ADR-014, "no coupling guard covers
# this file").
check 'T9: the conformance fixture is non-empty' \
  "$( [ -s "$FIX/resolved-by-body.md" ] && echo non-empty )" non-empty
holds 'T9: a fresh render is byte-identical to the checked-in conformance body' \
  cmp "$TMP/t9-905.body" "$FIX/resolved-by-body.md"

# ---------------------------------------------------------------------------
printf 'T10: an open fork'"'"'s typed reason is rendered inline, and only inline\n'
# ---------------------------------------------------------------------------
# An open fork carries a typed `reason` (why it could not be settled from
# grounding) and deliberately has no machine-read line; XL-62-F3
# (docs/prs/XL-62/ticket-block.md) renders it inline on the OPEN line,
# mirroring the `moot — <reason>` shape two branches above it, and nothing
# more. Presentation only: no column-0 line, no parser, no verdict-line counter.

W6="$TMP/t10.md"
cp "$FIX/design.md" "$W6"
mt write --map "$MAP" --ticket ESAS-906 "$W6" --insert-after "$H"
expect 'T10 write ESAS-906' written 0
region_body "$W6" > "$TMP/t10.body"
check 'T10: ESAS-906 forks=3' "$( attr "$LINE" forks )" 3 "$LINE"
check 'T10: ESAS-906 open=3'  "$( attr "$LINE" open )" 3 "$LINE"

check 'T10: an open fork with a recorded reason renders it inline' \
  "$( section_of "$TMP/t10.body" ESAS-906-F1 | grep -c '^OPEN — recommended: Alpha (store-unreachable)$' )" 1
check 'T10: a reason outside the documented vocabulary is rendered verbatim' \
  "$( section_of "$TMP/t10.body" ESAS-906-F2 | grep -c '^OPEN — recommended: Alpha (the atom store answered, but nothing it holds is canonical yet)$' )" 1
check 'T10: an open fork with no reason renders exactly as before' \
  "$( section_of "$TMP/t10.body" ESAS-906-F3 | grep -c '^OPEN — recommended: Alpha$' )" 1
check 'T10: no empty parentheses where there is no reason' \
  "$( grep -c 'recommended: Alpha ()' "$TMP/t10.body" )" 0
check 'T10: the reason-less fork keeps a bare OPEN line (no trailing parenthesis)' \
  "$( section_of "$TMP/t10.body" ESAS-906-F3 | grep -c '^OPEN — recommended: .*(' )" 0
check 'T10: the render did not warn or refuse on the free-text reason' \
  "$( grep -ci 'vocabulary\|unknown reason' "$OUT" )" 0

# The negative half (XL-62-F3, docs/prs/XL-62/ticket-block.md): rendered, never machine-read.
check 'T10: the reason text never appears at column 0' \
  "$( grep -c '^store-unreachable' "$TMP/t10.body" )" 0
check 'T10: no open_reason: line is emitted anywhere' \
  "$( grep -c 'open_reason' "$TMP/t10.body" )" 0
check 'T10: no resolved_by: line for an open fork with a reason' \
  "$( grep -c '^resolved_by: ' "$TMP/t10.body" )" 0
check 'T10: the verdict line key set is unchanged by the rendered reason' \
  "$( printf '%s\n' "$LINE" | tr ' ' '\n' | sed -n 's/=.*//p' | tr '\n' ' ' )" \
  'outcome verb ticket forks owner code recommendation open moot path ' "$LINE"

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
