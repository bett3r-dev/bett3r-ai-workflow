#!/bin/sh
# Oracle for `bin/scaffold-commit` — the design-end scaffold commit (ESAS-304).
#
# /design ends with the docs commit, then Step 4b: `prepare` dry-runs the
# declared scaffolder over the agreed design, classifies its blocks and writes
# the mechanical half; an agent places the topology fragments; `finish`
# re-extracts, re-runs the scaffolder, runs the declared typecheck and, only on
# green, commits the files plus <path>/scaffold.json as
# "chore(<id>): scaffold the agreed design". Red restores the tree and the docs
# commit stands.
#
# Every case drives the real launcher against a throwaway git repo whose
# .blueprint.config.json declares STUB commands written below: a scaffolder
# speaking the scaffold-core JSON shape, an extractor that reads the fixture's
# src/ back into graph.json, and a typecheck that is red when a line reads
# BROKEN. The "agent" is a few lines that place what the report's worklist[]
# names. Each case reads the `SCAFFOLD-COMMIT:v1` verdict line (ADR-004), never
# the exit code alone, and asserts on the git tree and history it left.
#
# Run locally:  sh scripts/test-scaffold-commit.sh
# SC_SH selects the interpreter that runs the `bin/scaffold-commit` launcher
# (`sh` is dash on Debian/Ubuntu, bash on macOS).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
SC="$ROOT/plugins/bett3r-ai-workflow/bin/scaffold-commit"
SC_SH=${SC_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/scaffold-commit-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fixture owns git's configuration and identity: no user/system gitconfig,
# a fixed author, and a ceiling so no repository above the temp dir is found.
HOME="$TMP/home"; mkdir -p "$HOME"; export HOME
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES=$TMP TZ=UTC
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_CEILING_DIRECTORIES TZ
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
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

# check <description> <actual> <expected> [context…] — an EMPTY expected value is
# refused, so a step that never ran cannot equal an empty actual.
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

attr(){ printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1; }

# The verdict is the last non-empty line, and only if it is a verdict line.
verdict(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^SCAFFOLD-COMMIT:v1 verb=[a-z]+ outcome=[a-z-]+( [A-Za-z]+=[^ ]*)*$'
}

# sc <args…> — run the launcher inside $REPO. Sets $rc, $LINE and $NV (how many
# verdict lines the run printed: exactly one is the contract).
OUT="$TMP/out"
sc(){
  ( cd "$REPO" && "$SC_SH" "$SC" "$@" ) > "$OUT" 2>&1
  rc=$?
  LINE=$( verdict "$OUT" )
  NV=$( grep -c '^SCAFFOLD-COMMIT:v1' "$OUT" )
}

# js <file> <python expression over `d`> — read one value out of a JSON file.
js(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }

# --- stub commands, declared by the fixture repo's .blueprint.config.json -----
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
STUB_LOG="$TMP/calls.log"; export STUB_LOG
# Every --map the scaffolder received, one run per line, in argv order.
MAP_LOG="$TMP/maps.log"; export MAP_LOG

# A scaffolder speaking the scaffold-core CLI contract (--design --graph, --map
# repeatable, --json [--write]; exit 3 when a unit is blocked). It logs the
# --map values of each run to $MAP_LOG and reads every map's scenarios, in
# order. One rule per node type:
#   event        -> a fragment for src/events.ts (topology, for the agent)
#   policy       -> a fragment for src/registry.ts (registration, for /build)
#   read-model   -> src/read-models/<slug>.ts plus a barrel line in src/index.ts,
#                   deferred while an event it projects is not in the graph
#   external-system -> blocked, code no-template
#   a node whose note is "ask" -> blocked, code decision
#   a read model whose note is "ask-when-ready" -> blocked, code decision, once
#                   nothing it projects waits (deferred until then, so placing
#                   the event it projects is what turns it into a block)
# SC_STUB_MODE=oops adds a malformed "skipped" entry (a string, not an object);
# SC_STUB_MODE=fail exits 1 before printing anything.
# A node already in the graph is satisfied. map.json scenarios: agreed ones
# become scenarioTests[] (unplaced when they have no anchor), review ones
# scenariosExcluded[].
cat > "$STUBS/scaffold.py" <<'PY'
import json, os, re, sys
argv = sys.argv[1:]
with open(os.environ["STUB_LOG"], "a") as log:
    log.write("scaffold " + " ".join(a for a in argv if a.startswith("--")) + "\n")
MODE = os.environ.get("SC_STUB_MODE", "")
if MODE == "fail":
    print("scaffold: boom", file=sys.stderr); sys.exit(1)
flags, maps, i = {}, [], 0
while i < len(argv):
    if argv[i] in ("--json", "--write"):
        flags[argv[i]] = True; i += 1
    elif argv[i] == "--map":
        maps.append(argv[i + 1]); i += 2
    else:
        flags[argv[i]] = argv[i + 1]; i += 2
with open(os.environ["MAP_LOG"], "a") as log:
    log.write(" ".join(maps) + "\n")
ABBR = {"event": "evt", "read-model": "rm", "policy": "pol", "external-system": "ext", "command": "cmd"}
def slug(s):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", s)
    return re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
def nid(n):
    return f"{slug(n['subdomain'])}_{ABBR[n['type']]}_{slug(n['label'])}"
design = json.load(open(flags["--design"]))
graph = json.load(open(flags["--graph"]))
scenarios = [s for m in maps for s in json.load(open(m)).get("scenarios", [])]
real = {n["id"] for n in graph.get("nodes", [])}
prop = design.get("propose", {})
edges = prop.get("edges", [])
out = {"files": [], "fragments": [], "appends": [], "hosted": [], "skipped": [], "deferred": [],
       "dropped": [], "held": [], "testPlan": {"suites": []}, "scenarioTests": [], "unplaced": [],
       "scenariosExcluded": [], "written": "--write" in flags}
for n in prop.get("nodes", []):
    i, t, label = nid(n), n["type"], n["label"]
    if i in real:
        out["skipped"].append({"node": i, "reason": "satisfied", "detail": "in code"}); continue
    if n.get("note") == "ask":
        out["skipped"].append({"node": i, "reason": "blocked", "detail": "needs a decision",
                               "decisions": [{"node": i, "code": "decision", "question": f"Which module owns {label}?", "needed": "module"}]})
        continue
    if t == "external-system":
        out["skipped"].append({"node": i, "reason": "blocked", "detail": "no template",
                               "decisions": [{"node": i, "code": "no-template", "question": "no template for external-system", "needed": "template"}]})
        continue
    if t == "event":
        out["fragments"].append({"file": "src/events.ts", "anchor": "end of file", "imports": [], "todo": [],
                                 "code": f"export const {label} = '{label}';", "node": i, "artifact": "event"})
    elif t == "policy":
        out["fragments"].append({"file": "src/registry.ts", "anchor": "registry list", "imports": [], "todo": ["register it"],
                                 "code": f"register({label});", "node": i, "artifact": "policy"})
    elif t == "read-model":
        waits = sorted(e["from"] for e in edges if e["to"] == i and e["from"] not in real)
        if waits:
            out["deferred"].append({"node": i, "artifact": "read-model", "waitsOn": waits, "reason": "projects an event not in code"}); continue
        if n.get("note") == "ask-when-ready":
            out["skipped"].append({"node": i, "reason": "blocked", "detail": "needs a decision",
                                   "decisions": [{"node": i, "code": "decision", "question": f"Which store backs {label}?", "needed": "store"}]})
            continue
        f = f"src/read-models/{slug(label)}.ts"
        if os.path.exists(f):
            out["skipped"].append({"node": i, "reason": "exists", "detail": f}); continue
        out["files"].append({"file": f, "content": f"// TODO(scaffold) [{i}]\nexport const {label} = {{}};\n", "node": i, "artifact": "read-model"})
        out["appends"].append({"kind": "barrel", "file": "src/index.ts", "anchor": "end", "node": i, "artifact": "read-model",
                               "code": f"export * from './read-models/{slug(label)}';"})
for s in scenarios:
    if s.get("status") == "review":
        out["scenariosExcluded"].append({"scenarioId": s["id"], "reason": "review", "review": "fork-reopened"}); continue
    entry = {"scenarioId": s["id"], "level": "unit", "testName": f"{s['id']}: {s['title']}", "presence": "absent"}
    if s.get("anchor"):
        out["scenarioTests"].append(dict(entry, outcome="planned", file="test/scenarios.test.ts"))
    else:
        out["scenarioTests"].append(dict(entry, outcome="unplaced"))
        out["unplaced"].append({"scenarioId": s["id"], "level": "unit", "reason": "no anchor"})
if "--write" in flags:
    for f in out["files"]:
        os.makedirs(os.path.dirname(f["file"]), exist_ok=True)
        with open(f["file"], "w") as fh: fh.write(f["content"])
    for a in out["appends"]:  # a barrel line is written only when no line equals it
        if a["code"] not in open(a["file"]).read().splitlines():
            with open(a["file"], "a") as fh: fh.write(a["code"] + "\n")
if MODE == "oops":
    out["skipped"].append("oops")
print(json.dumps(out, indent=2))
sys.exit(3 if any(isinstance(s, dict) and s["reason"] == "blocked" for s in out["skipped"]) else 0)
PY

# The extractor: reads src/ back into .blueprint/graph.json (events from
# src/events.ts, read models from src/read-models/*.ts), as a real one would.
cat > "$STUBS/extract.py" <<'PY'
import json, os, re
with open(os.environ["STUB_LOG"], "a") as log: log.write("extract\n")
def slug(s):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", s)
    return re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
nodes = []
for m in re.finditer(r"^export const (\w+) = '", open("src/events.ts").read(), re.M):
    nodes.append({"id": f"orders_evt_{slug(m.group(1))}", "type": "event", "label": m.group(1), "subdomain": "orders"})
if os.path.isdir("src/read-models"):
    for f in sorted(os.listdir("src/read-models")):
        nodes.append({"id": f"orders_rm_{f[:-3]}", "type": "read-model", "label": f[:-3], "subdomain": "orders"})
os.makedirs(".blueprint", exist_ok=True)
json.dump({"schemaVersion": 1, "subdomains": ["orders"], "nodes": nodes, "edges": []}, open(".blueprint/graph.json", "w"), indent=2)
PY

# Red on a line reading BROKEN, and on a barrel export of a module that does
# not exist (a dangling `export * from './x';`), as tsc would be. A red BASE is
# src/legacy.ts holding LEGACY_RED: one error per such line, coloured and
# located as tsc prints it (so a placement that shifts it down the file moves
# its location only). SC_TC_MODE=opaque prints no `error TS<n>` line for it;
# opaque-base does so only on the base (src/events.ts without OrderShipped).
cat > "$STUBS/typecheck.sh" <<'SH'
printf 'typecheck\n' >> "$STUB_LOG"
rc=0
if [ -f src/legacy.ts ] && grep -q LEGACY_RED src/legacy.ts; then
  if [ "${SC_TC_MODE:-}" = opaque ] || { [ "${SC_TC_MODE:-}" = opaque-base ] && ! grep -q OrderShipped src/events.ts; }; then
    echo 'Build failed.'; exit 1
  fi
  for n in $( grep -n LEGACY_RED src/legacy.ts | cut -d: -f1 ); do
    printf '\033[31msrc/legacy.ts(%s,7): error TS2322: Type string is not assignable to type number.\033[0m\n' "$n"
  done
  rc=2
fi
if grep -rn BROKEN src; then echo 'error TS2304: Cannot find name BROKEN'; exit 2; fi
for m in $( sed -n "s|^export \* from '\./\(.*\)';\$|\1|p" src/index.ts ); do
  [ -f "src/$m.ts" ] || { echo "src/index.ts: error TS2307: Cannot find module './$m'"; exit 2; }
done
[ "$rc" -eq 0 ] || exit "$rc"
echo 'typecheck: 0 errors'
SH

cat > "$STUBS/observe.sh" <<'SH'
printf 'observe\n' >> "$STUB_LOG"
echo 'observed: 1 read model'
SH

# The placing agent: appends every worklist[] fragment's code to its file, as
# the report hands it over. `agent broken` places it wrongly: the declaration
# lands (the extractor sees it) next to a line that does not compile.
agent(){
  python3 - "$REPO/docs/prs/ESAS-304/scaffold.json" "$REPO" "${1:-}" <<'PY'
import json, os, sys
report, repo, mode = sys.argv[1], sys.argv[2], sys.argv[3]
for f in json.load(open(report))["worklist"]:
    with open(os.path.join(repo, f["file"]), "a") as fh:
        fh.write(f["code"] + "\n" + ("BROKEN\n" if mode == "broken" else ""))
PY
}

FULL_TOOLING="\"scaffold\": \"python3 $STUBS/scaffold.py\", \"typecheck\": \"sh $STUBS/typecheck.sh\", \"extract\": \"python3 $STUBS/extract.py\""

# new_repo <name> <designTooling body> — a repo whose HEAD is the docs commit
# "docs(ESAS-304): design" over a base holding src/events.ts (OrderPlaced),
# src/index.ts and src/registry.ts. .blueprint/ is gitignored, as in a host repo.
new_repo(){
  REPO="$TMP/$1"
  mkdir -p "$REPO/src" "$REPO/docs/prs/ESAS-304"
  git -C "$REPO" init -q -b master
  printf '.blueprint/\n' > "$REPO/.gitignore"
  printf "export const OrderPlaced = 'OrderPlaced';\n" > "$REPO/src/events.ts"
  printf '// barrel\n' > "$REPO/src/index.ts"
  printf '// registry\n' > "$REPO/src/registry.ts"
  if [ -n "${NEW_REPO_LEGACY:-}" ]; then printf 'export const n: number = "LEGACY_RED";\n' > "$REPO/src/legacy.ts"; fi
  printf '{ "designTooling": { %s } }\n' "$2" > "$REPO/.blueprint.config.json"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm 'chore: base'
  printf -- '---\nwork_item: ESAS-304\nbranch: master\n---\n# design\n' > "$REPO/docs/prs/ESAS-304/design.md"
  printf '{"mapId": "ESAS-304", "scenarios": []}\n' > "$REPO/docs/prs/ESAS-304/map.json"
  printf '<html></html>\n' > "$REPO/docs/prs/ESAS-304/map.html"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm 'docs(ESAS-304): design'
  DOCS=$( git -C "$REPO" rev-parse HEAD )
  ( cd "$REPO" && python3 "$STUBS/extract.py" )
  : > "$STUB_LOG"
  : > "$MAP_LOG"
}

# design <json> — the agreed ES design, as .blueprint/design.json holds it.
design(){ printf '%s\n' "$1" > "$REPO/.blueprint/design.json"; }

# Proposed nodes, by their derived ids (orders_<abbr>_<slug>).
N_SHIPPED='{"type":"event","label":"OrderShipped","subdomain":"orders"}'
N_SHIPPED_RM='{"type":"read-model","label":"ShippedOrders","subdomain":"orders"}'
N_PLACED_RM='{"type":"read-model","label":"PlacedOrders","subdomain":"orders"}'
E_SHIPPED='{"from":"orders_evt_order-shipped","to":"orders_rm_shipped-orders","kind":"projects"}'
E_PLACED='{"from":"orders_evt_order-placed","to":"orders_rm_placed-orders","kind":"projects"}'

status(){ git -C "$REPO" status --porcelain | tr '\n' '|'; }
REPORT=docs/prs/ESAS-304/scaffold.json

# ---------------------------------------------------------------------------
printf 'skipped: a missing declaration skips loudly and runs nothing\n'
# ---------------------------------------------------------------------------
new_repo skip-typecheck "\"scaffold\": \"python3 $STUBS/scaffold.py\""
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
check 'no typecheck key: SCAFFOLD-COMMIT:v1 verb=prepare outcome=skipped' "$( attr "$LINE" verb ) $( attr "$LINE" outcome )" 'prepare skipped' "$LINE"
check 'no typecheck key: the reason names designTooling.typecheck' "$( attr "$LINE" reason )" undeclared-designTooling.typecheck "$LINE"
check 'no typecheck key: no file is written' "$( status )x" x
check 'no typecheck key: no declared command ran (no framework default)' "$( wc -l < "$STUB_LOG" | tr -d ' ' )" 0
check 'no typecheck key: exactly one verdict line' "$NV" 1
check 'no typecheck key: exit 0' "$rc" 0

new_repo skip-scaffold "\"typecheck\": \"sh $STUBS/typecheck.sh\""
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
check 'no scaffold key: outcome=skipped' "$( attr "$LINE" outcome )" skipped "$LINE"
check 'no scaffold key: the reason names designTooling.scaffold' "$( attr "$LINE" reason )" undeclared-designTooling.scaffold "$LINE"
check 'no scaffold key: no file is written, nothing ran' "$( status )|$( wc -l < "$STUB_LOG" | tr -d ' ' )" '|0'

# ---------------------------------------------------------------------------
printf '\nclean: new event plus read model, everything agreed lands in one green commit\n'
# ---------------------------------------------------------------------------
new_repo clean "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
printf 'dirty\n' > "$REPO/stray"
sc prepare --item ESAS-304
check 'prepare refuses a dirty tree' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error dirty-tree' "$LINE"
check 'the refusal ran nothing' "$( wc -l < "$STUB_LOG" | tr -d ' ' )" 0
rm "$REPO/stray"

sc prepare --item ESAS-304
check 'prepare: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"
check 'prepare: the event is the worklist (one topology fragment for the agent)' \
  "$( js "$REPO/$REPORT" "[f['node'] for f in d['worklist']]" )" "['orders_evt_order-shipped']"
check 'prepare: the read model waits on the event, so nothing is created yet' "$( attr "$LINE" created )" 0 "$LINE"
check 'prepare: the scaffolder was dry-run, then run with --write, with --map <path>/map.json' \
  "$( grep -c -- '--map' "$STUB_LOG" )|$( grep -c -- '--write' "$STUB_LOG" )" '2|1'
check 'prepare: with no --map given, both runs received exactly the default <path>/map.json' \
  "$( tr '\n' '|' < "$MAP_LOG" )" "$REPO/docs/prs/ESAS-304/map.json|$REPO/docs/prs/ESAS-304/map.json|"
check 'prepare: exactly one verdict line' "$NV" 1
agent
sc finish --item ESAS-304
check 'finish: SCAFFOLD-COMMIT:v1 verb=finish outcome=ok' "$( attr "$LINE" verb ) $( attr "$LINE" outcome )" 'finish ok' "$LINE" "$( tail -8 "$OUT" )"
check 'finish: observe absent prints "observe: none declared"' "$( grep -cx 'observe: none declared' "$OUT" )" 1
check "finish: one commit titled 'chore(ESAS-304): scaffold the agreed design'" \
  "$( git -C "$REPO" log --format=%s "$DOCS"..HEAD | tr '\n' '|' )" 'chore(ESAS-304): scaffold the agreed design|'
check 'finish: the commit holds the created files, the placed event, the barrel line and scaffold.json' \
  "$( git -C "$REPO" show --name-only --format= HEAD | sort | tr '\n' ' ' )" \
  'docs/prs/ESAS-304/scaffold.json src/events.ts src/index.ts src/read-models/shipped-orders.ts '
check 'finish: the docs commit is the scaffold commit'"'"'s parent' "$( git -C "$REPO" rev-parse HEAD~1 )" "$DOCS"
check 'finish: the tree is clean' "$( status )x" x
check 'finish: counts created=1 appended=1 placed=1' \
  "$( attr "$LINE" created ) $( attr "$LINE" appended ) $( attr "$LINE" placed )" '1 1 1' "$LINE"
check 'finish: exactly one verdict line' "$NV" 1
check 'scaffold.json: placed[] names the event in src/events.ts' \
  "$( js "$REPO/$REPORT" "[(p['node'], p['file']) for p in d['placed']]" )" "[('orders_evt_order-shipped', 'src/events.ts')]"
check 'scaffold.json: manifest[] carries the stub with its git blob' \
  "$( js "$REPO/$REPORT" "[(m['file'], m['node'], m['blob']) for m in d['manifest']]" )" \
  "[('src/read-models/shipped-orders.ts', 'orders_rm_shipped-orders', '$( git -C "$REPO" rev-parse HEAD:src/read-models/shipped-orders.ts )')]"
check 'scaffold.json: baseSha is the docs commit' "$( js "$REPO/$REPORT" "d['baseSha']" )" "$DOCS"
check 'scaffold.json: input digests of the map, design and graph' \
  "$( js "$REPO/$REPORT" "sorted(d['inputs'])" )|$( js "$REPO/$REPORT" "[m['file'] for m in d['inputs']['maps']]" )|$( js "$REPO/$REPORT" "d['inputs']['maps'][0]['digest']" )" \
  "['design', 'graph', 'maps']|['docs/prs/ESAS-304/map.json']|sha256:$( python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO/docs/prs/ESAS-304/map.json" )"
check 'scaffold.json: observe is null when none is declared' "$( js "$REPO/$REPORT" "d['observe']" )" None
check 'scaffold.json: carries the final scaffolder JSON' "$( js "$REPO/$REPORT" "sorted(d['scaffolder'])[:3]" )" "['appends', 'deferred', 'dropped']"
check 'finish ran extract, scaffold --write and typecheck, in that order' \
  "$( sed -n 's/^\([a-z]*\).*/\1/p' "$STUB_LOG" | tail -3 | tr '\n' ' ' )" 'extract scaffold typecheck '

# ---------------------------------------------------------------------------
printf '\nred after placement: caught before commit, the tree restored, the docs commit stands\n'
# ---------------------------------------------------------------------------
new_repo red "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM,$N_PLACED_RM],\"edges\":[$E_SHIPPED,$E_PLACED]}}"
sc prepare --item ESAS-304
check 'red: prepare ok and created the read model of an event already in code' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" created ) $( attr "$LINE" appended )" 'ok 1 1' "$LINE"
check 'red: before finish the tree holds new paths and a tracked edit' \
  "$( status )" ' M src/index.ts|?? docs/prs/ESAS-304/scaffold.json|?? src/read-models/|'
agent broken
sc finish --item ESAS-304
check 'red: outcome=gate-red' "$( attr "$LINE" outcome )" gate-red "$LINE" "$( tail -8 "$OUT" )"
check 'red: reason=typecheck-red' "$( attr "$LINE" reason )" typecheck-red "$LINE"
check 'red: git status --short is empty' "$( git -C "$REPO" status --short | tr '\n' '|' )x" x
check 'red: the new paths are gone' \
  "$( [ -e "$REPO/src/read-models" ] && echo present; [ -e "$REPO/$REPORT" ] && echo report; echo end )" end
check 'red: the tracked edits are restored byte for byte' \
  "$( git -C "$REPO" diff "$DOCS" --stat | wc -l | tr -d ' ' )" 0
check 'red: the docs commit is still HEAD' "$( git -C "$REPO" rev-parse HEAD )" "$DOCS"
check 'red: exactly one verdict line, exit non-zero' "$NV|$( [ "$rc" -ne 0 ] && echo nonzero )" '1|nonzero'
check 'red: the typecheck output is shown' "$( grep -c 'TS2304' "$OUT" )" 1
check 'red: on a green base, the typecheck ran again over HEAD and any red is red' \
  "$( grep -c '^typecheck$' "$STUB_LOG" )|$( grep -cx 'typecheck-base: exit 0' "$OUT" )" '2|1'

# ---------------------------------------------------------------------------
printf '\nred base: green means no typecheck error outside the base'"'"'s error set (Bar P10)\n'
# ---------------------------------------------------------------------------
# ESAS-300's kixie base is red for an environmental reason, so the bar compares
# error sets, never exit codes. HEAD here is red with one TS2322 in
# src/legacy.ts; a line put above it moves its location and nothing else.
# (set and unset by hand: POSIX sh keeps an assignment made before a function call)
NEW_REPO_LEGACY=1
new_repo redbase "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
check 'red base: the fixture base is red (positive control)' \
  "$( cd "$REPO" && sh "$STUBS/typecheck.sh" > /dev/null; echo $? )" 2
: > "$STUB_LOG"
sc prepare --item ESAS-304
check 'red base: prepare ok' "$( attr "$LINE" outcome )" ok "$LINE"
agent
printf '// shifted\n' | cat - "$REPO/src/legacy.ts" > "$TMP/legacy" && mv "$TMP/legacy" "$REPO/src/legacy.ts"
sc finish --item ESAS-304
check 'red base, only the base'"'"'s error: outcome=ok typecheck=base-red' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" typecheck )" 'ok base-red' "$LINE" "$( tail -12 "$OUT" )"
check 'red base: the typecheck ran after placement, then once over HEAD' "$( grep -c '^typecheck$' "$STUB_LOG" )" 2
check 'red base: it says no error is outside the base'"'"'s set, and names none as new' \
  "$( grep -c "none outside the base's 1" "$OUT" )|$( grep -c '^new-error:' "$OUT" )" '1|0'
check 'red base: one commit, holding every edit the base run set aside and put back' \
  "$( git -C "$REPO" log --format=%s "$DOCS"..HEAD | tr '\n' '|' )$( git -C "$REPO" show --name-only --format= HEAD | sort | tr '\n' ' ' )" \
  'chore(ESAS-304): scaffold the agreed design|docs/prs/ESAS-304/scaffold.json src/events.ts src/index.ts src/legacy.ts src/read-models/shipped-orders.ts '
check 'red base: the tree is clean' "$( status )x" x
check 'red base: scaffold.json records the typecheck against its base' \
  "$( js "$REPO/$REPORT" "sorted(d['typecheck'].items())" )" "[('baseErrors', 1), ('baseExit', 2), ('errors', 1), ('exit', 2)]"

# A re-run on the red base that deletes an untouched stub (a rename): the base
# run restores HEAD, stub included, so putting the edits back must delete it again.
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,{\"type\":\"read-model\",\"label\":\"ShippedOrderList\",\"subdomain\":\"orders\"}],\"edges\":[{\"from\":\"orders_evt_order-shipped\",\"to\":\"orders_rm_shipped-order-list\",\"kind\":\"projects\"}]}}"
RB_HEAD=$( git -C "$REPO" rev-parse HEAD )
sc prepare --item ESAS-304
check 'red base, rename re-run: prepare ok stale=1' "$( attr "$LINE" outcome ) $( attr "$LINE" stale )" 'ok 1' "$LINE"
: > "$STUB_LOG"
sc finish --item ESAS-304
check 'red base, rename re-run: finish ok typecheck=base-red, after a base run' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" typecheck ) $( grep -c '^typecheck$' "$STUB_LOG" )" 'ok base-red 2' "$LINE" "$( tail -12 "$OUT" )"
check 'red base, rename re-run: the deleted stub stays deleted (absent on disk and in the commit)' \
  "$( [ -e "$REPO/src/read-models/shipped-orders.ts" ] && echo present; git -C "$REPO" show --name-status --format= HEAD -- src/read-models | sort | tr '\t\n' ' |' )" \
  'A src/read-models/shipped-order-list.ts|D src/read-models/shipped-orders.ts|'
check 'red base, rename re-run: stale[] names the old stub' \
  "$( js "$REPO/$REPORT" "[s['file'] for s in d['stale']]" )" "['src/read-models/shipped-orders.ts']"
check 'red base, rename re-run: one new commit, tree clean' \
  "$( git -C "$REPO" rev-parse HEAD~1 )|$( status )" "$RB_HEAD|"

new_repo redbase-new "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
agent broken
sc finish --item ESAS-304
check 'red base, a NEW error outside the base set: outcome=gate-red reason=typecheck-red' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'gate-red typecheck-red' "$LINE" "$( tail -12 "$OUT" )"
check 'red base, new error: printed as new-error, the base'"'"'s own error is not' \
  "$( grep '^new-error:' "$OUT" | tr '\n' '|' )" 'new-error: error TS2304: Cannot find name BROKEN|'
check 'red base, new error: the tree is restored and the docs commit is HEAD' \
  "$( status )|$( git -C "$REPO" rev-parse HEAD )" "|$DOCS"

# A second copy of a base error is a new error: error sets are multisets, as
# ESAS-300's `comm -13` over error lines counts them.
new_repo redbase-dup "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
agent
printf 'export const m: number = "LEGACY_RED";\n' >> "$REPO/src/legacy.ts"
sc finish --item ESAS-304
check 'red base, a duplicate of a base error: outcome=gate-red reason=typecheck-red' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'gate-red typecheck-red' "$LINE" "$( tail -12 "$OUT" )"
check 'red base, duplicate: exactly the one extra copy is printed as new-error' \
  "$( grep -c '^new-error: src/legacy.ts: error TS2322' "$OUT" )" 1
check 'red base, duplicate: the tree is restored and the docs commit is HEAD' \
  "$( status )|$( git -C "$REPO" rev-parse HEAD )" "|$DOCS"

SC_TC_MODE=opaque; export SC_TC_MODE
new_repo redbase-opaque "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
agent
sc finish --item ESAS-304
check 'red base, no error line to read after placement: fail-safe gate-red typecheck-red' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'gate-red typecheck-red' "$LINE" "$( tail -8 "$OUT" )"
check 'red base, unreadable: judged by its exit code, the base never run' \
  "$( grep -c 'judged by its exit code' "$OUT" )|$( grep -c '^typecheck$' "$STUB_LOG" )" '1|1'
check 'red base, unreadable: the tree is restored' "$( status )x" x

SC_TC_MODE=opaque-base
new_repo redbase-opaque-base "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
agent
sc finish --item ESAS-304
check 'red base, no error line to read on the BASE: fail-safe gate-red typecheck-red' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( grep -c '^typecheck-base: red with no' "$OUT" )" 'gate-red typecheck-red 1' "$LINE" "$( tail -8 "$OUT" )"
check 'red base, unreadable base: the tree is restored and the docs commit is HEAD' \
  "$( status )|$( git -C "$REPO" rev-parse HEAD )" "|$DOCS"
unset SC_TC_MODE NEW_REPO_LEGACY

# ---------------------------------------------------------------------------
printf '\nasked: a block that needs a decision goes back to the grill\n'
# ---------------------------------------------------------------------------
new_repo asked "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM,{\"type\":\"command\",\"label\":\"ShipOrder\",\"subdomain\":\"orders\",\"note\":\"ask\"}],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
check 'asked: outcome=blocked reason=asked asked=1' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" asked )" 'blocked asked 1' "$LINE"
check 'asked: the question is printed for the grill' "$( grep -c '^asked: orders_cmd_ship-order Which module owns ShipOrder?' "$OUT" )" 1
check 'asked: nothing is written (dry-run only)' "$( status )x|$( grep -c -- '--write' "$STUB_LOG" )" 'x|0'
check 'asked: HEAD is still the docs commit' "$( git -C "$REPO" rev-parse HEAD )" "$DOCS"

# ---------------------------------------------------------------------------
printf '\nstill-owed: no template is reported, and the commit proceeds\n'
# ---------------------------------------------------------------------------
new_repo owed "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM,{\"type\":\"external-system\",\"label\":\"Carrier\",\"subdomain\":\"orders\"},{\"type\":\"policy\",\"label\":\"NotifyCarrier\",\"subdomain\":\"orders\"}],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
check 'still-owed: prepare ok, not blocked' "$( attr "$LINE" outcome ) $( attr "$LINE" asked )" 'ok 0' "$LINE"
check 'still-owed: a registration fragment is not on the agent worklist' "$( js "$REPO/$REPORT" "d['worklist']" )" '[]'
sc finish --item ESAS-304
check 'still-owed: finish ok, stillOwed=2' "$( attr "$LINE" outcome ) $( attr "$LINE" stillOwed )" 'ok 2' "$LINE"
check 'still-owed: scaffold.json stillOwed[] names the no-template block and the registration fragment' \
  "$( js "$REPO/$REPORT" "[(s['node'], s['reason']) for s in d['stillOwed']]" )" \
  "[('orders_ext_carrier', 'no-template'), ('orders_pol_notify-carrier', 'registration')]"
check 'still-owed: committed' "$( git -C "$REPO" log -1 --format=%s )" 'chore(ESAS-304): scaffold the agreed design'

# ---------------------------------------------------------------------------
printf '\nunchanged re-run: no diff, no commit\n'
# ---------------------------------------------------------------------------
first=$( git -C "$REPO" rev-parse HEAD )
: > "$STUB_LOG"
sc prepare --item ESAS-304
check 'unchanged re-run: prepare ok, the untouched stub deleted then re-scaffolded' "$( attr "$LINE" outcome ) $( attr "$LINE" created )" 'ok 1' "$LINE"
check 'unchanged re-run: the stub shows no diff, only the draft report differs' "$( status )" ' M docs/prs/ESAS-304/scaffold.json|'
sc finish --item ESAS-304
check 'unchanged re-run: outcome=ok reason=unchanged' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'ok unchanged' "$LINE" "$( git -C "$REPO" diff HEAD | head -20 )"
check 'unchanged re-run: no new commit' "$( git -C "$REPO" rev-parse HEAD )" "$first"
check 'unchanged re-run: the tree is clean' "$( status )x" x

# ---------------------------------------------------------------------------
printf '\nheld: an open question on a proposal holds the element out\n'
# ---------------------------------------------------------------------------
new_repo held "$FULL_TOOLING"
N_DISPUTED='{"type":"event","label":"OrderDisputed","subdomain":"orders"}'
N_NOTED='{"type":"event","label":"OrderNoted","subdomain":"orders"}'
N_AUDITED='{"type":"event","label":"OrderAudited","subdomain":"orders"}'
N_DISPUTES_RM='{"type":"read-model","label":"DisputeList","subdomain":"orders"}'
N_LOST_RM='{"type":"read-model","label":"LostOrders","subdomain":"orders"}'
E_LOST='{"from":"orders_evt_order-lost","to":"orders_rm_lost-orders","kind":"projects"}'
E_DISPUTED='{"from":"orders_evt_order-disputed","to":"orders_rm_dispute-list","kind":"projects"}'
C1='{"id":"c1","anchor":"orders_evt_order-disputed","resolved":false,"text":"is this ours?"}'
C2='{"id":"c2","anchor":"orders_evt_order-noted","resolved":false,"text":"","reaction":"thumbs-up"}'
C3='{"id":"c3","anchor":"orders_evt_order-audited","resolved":true,"text":"settled?"}'
C4='{"id":"c4","anchor":{"commentId":"c3"},"resolved":false,"text":"not quite"}'
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_DISPUTED,$N_NOTED,$N_AUDITED,$N_DISPUTES_RM,$N_LOST_RM],\"edges\":[$E_DISPUTED,$E_LOST]},\"comments\":[$C1,$C2,$C3,$C4]}"
sc prepare --item ESAS-304
check 'held: prepare ok held=3' "$( attr "$LINE" outcome ) $( attr "$LINE" held )" 'ok 3' "$LINE" "$( tail -5 "$OUT" )"
check 'held: held[] names the first node and its edge, and the node a reply rolls up to' \
  "$( js "$REPO/$REPORT" "[(h['element'], h['commentId']) for h in d['held']]" )" \
  "[('edge:orders_evt_order-disputed|orders_rm_dispute-list|projects', 'c1'), ('node:orders_evt_order-audited', 'c4'), ('node:orders_evt_order-disputed', 'c1')]"
check 'held: a node whose only comment is a reaction is not held' \
  "$( js "$REPO/$REPORT" "[h for h in d['held'] if 'order-noted' in h['element']]" )" '[]'
check 'held: the held nodes never reach the scaffolder, the reaction-only node does' \
  "$( js "$REPO/$REPORT" "[f['node'] for f in d['worklist']]" )" "['orders_evt_order-noted']"
agent
sc finish --item ESAS-304
check 'held: finish ok; a unit deferred on a node off the worklist is STILL OWED, not a placement failure' \
  "$( attr "$LINE" outcome )|$( js "$REPO/$REPORT" "[(s['node'], s['reason']) for s in d['stillOwed']]" )" \
  "ok|[('orders_rm_lost-orders', 'deferred')]" "$LINE"
check 'held: the read model whose only edge was held is scaffolded without it (the held edge never reaches the scaffolder)' \
  "$( git -C "$REPO" show --name-only --format= HEAD -- src/read-models | tr '\n' ' ' )" 'src/read-models/dispute-list.ts '
check 'held: held[] is in the committed report' "$( git -C "$REPO" show HEAD:$REPORT | grep -c 'node:orders_evt_order-disputed' )" 1

# finish --abort: restores like red.
new_repo abort "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
sc finish --item ESAS-304 --abort
check 'abort: outcome=gate-red reason=aborted' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'gate-red aborted' "$LINE"
check 'abort: the tree is clean and HEAD the docs commit' "$( status )x|$( git -C "$REPO" rev-parse HEAD )" "x|$DOCS"
check 'abort: the typecheck never ran' "$( grep -c typecheck "$STUB_LOG" )" 0
sc finish --item ESAS-304
check 'finish without a prepare: error reason=not-prepared' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error not-prepared' "$LINE"

# ---------------------------------------------------------------------------
printf '\nstubs: an untouched stub is deleted on re-run, an edited stub is never touched\n'
# ---------------------------------------------------------------------------
new_repo stubs "$FULL_TOOLING"
N_NOTED_EVT_RM='{"type":"read-model","label":"PlacedTotals","subdomain":"orders"}'
E_TOTALS='{"from":"orders_evt_order-placed","to":"orders_rm_placed-totals","kind":"projects"}'
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM,$N_NOTED_EVT_RM],\"edges\":[$E_PLACED,$E_TOTALS]}}"
sc prepare --item ESAS-304; sc finish --item ESAS-304
check 'stubs: first run commits two stubs' "$( js "$REPO/$REPORT" "len(d['manifest'])" )|$( attr "$LINE" outcome )" '2|ok' "$LINE"
printf '// hand edit\n' >> "$REPO/src/read-models/placed-totals.ts"
git -C "$REPO" commit -qam 'feat: fill placed totals'
cp "$REPO/src/read-models/placed-totals.ts" "$TMP/edited.copy"
sc prepare --item ESAS-304
check 'stubs: prepare ok edited=1' "$( attr "$LINE" outcome ) $( attr "$LINE" edited )" 'ok 1' "$LINE"
check 'stubs: the untouched stub is deleted then re-scaffolded with no diff' "$( status )" ' M docs/prs/ESAS-304/scaffold.json|'
check 'stubs: the edited stub is byte-identical' "$( cmp -s "$REPO/src/read-models/placed-totals.ts" "$TMP/edited.copy" && echo same )" same
check 'stubs: the edited stub is listed in edited[]' \
  "$( js "$REPO/$REPORT" "[e['file'] for e in d['edited']]" )" "['src/read-models/placed-totals.ts']"
sc finish --item ESAS-304
check 'stubs: finish ok and the edited stub still byte-identical' \
  "$( attr "$LINE" outcome )|$( cmp -s "$REPO/src/read-models/placed-totals.ts" "$TMP/edited.copy" && echo same )" 'ok|same' "$LINE"
check 'stubs: the edited stub keeps its original manifest blob' \
  "$( js "$REPO/$REPORT" "[m['blob'] for m in d['manifest'] if m['file'].endswith('placed-totals.ts')][0]" )" \
  "$( git -C "$REPO" rev-parse HEAD~2:src/read-models/placed-totals.ts )"

# ---------------------------------------------------------------------------
printf '\nrename: the old untouched stub is reported stale\n'
# ---------------------------------------------------------------------------
new_repo rename "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304; sc finish --item ESAS-304
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[{\"type\":\"read-model\",\"label\":\"PlacedOrderList\",\"subdomain\":\"orders\"}],\"edges\":[{\"from\":\"orders_evt_order-placed\",\"to\":\"orders_rm_placed-order-list\",\"kind\":\"projects\"}]}}"
sc prepare --item ESAS-304
check 'rename: prepare ok stale=1 created=1' "$( attr "$LINE" outcome ) $( attr "$LINE" stale ) $( attr "$LINE" created )" 'ok 1 1' "$LINE"
sc finish --item ESAS-304
check 'rename: finish ok stale=1' "$( attr "$LINE" outcome ) $( attr "$LINE" stale )" 'ok 1' "$LINE"
check 'rename: stale[] names the old stub' "$( js "$REPO/$REPORT" "[(s['file'], s['node']) for s in d['stale']]" )" \
  "[('src/read-models/placed-orders.ts', 'orders_rm_placed-orders')]"
check 'rename: the old stub is gone, the new one committed' \
  "$( git -C "$REPO" show --name-status --format= HEAD -- src/read-models | sort | tr '\t\n' ' |' )" \
  'A src/read-models/placed-order-list.ts|D src/read-models/placed-orders.ts|'
check 'rename: the stale stub'"'"'s recorded barrel line is removed, the new one appended (no dangling export)' \
  "$( git -C "$REPO" show HEAD:src/index.ts | tr '\n' '|' )" \
  "// barrel|export * from './read-models/placed-order-list';|"
check 'rename: the stale entry records the barrel line it removed' \
  "$( js "$REPO/$REPORT" "[(b['file'], b['code']) for s in d['stale'] for b in s.get('barrel', [])]" )" \
  "[('src/index.ts', \"export * from './read-models/placed-orders';\")]"

# ---------------------------------------------------------------------------
printf '\ncensus: agreed scenarios not implemented, holds on their own line\n'
# ---------------------------------------------------------------------------
new_repo census "$FULL_TOOLING"
sc census --item ESAS-304
check 'census without a report: skipped reason=no-scaffold-report' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'skipped no-scaffold-report' "$LINE"
printf '{"mapId": "ESAS-304", "scenarios": [{"id":"S1","title":"ships","status":"agreed","anchor":"x"},{"id":"S2","title":"lists","status":"agreed"},{"id":"S3","title":"audits","status":"review"}]}\n' \
  > "$REPO/docs/prs/ESAS-304/map.json"
git -C "$REPO" commit -qam 'docs(ESAS-304): design'
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304; sc finish --item ESAS-304
check 'census: the scaffold commit landed' "$( attr "$LINE" outcome )" ok "$LINE"
mkdir -p "$REPO/test"
printf '// S2: lists is covered elsewhere\nit.todo("XS1: other");\n' > "$REPO/test/other.test.ts"
git -C "$REPO" add -A; git -C "$REPO" commit -qm 'test: unrelated titles'
sc census --item ESAS-304
check 'census: a comment naming "S2: " is not an implemented test' "$( grep -cx 'not-implemented: S2 presence=absent' "$OUT" )" 1 "$( cat "$OUT" )"
check 'census: it.todo("XS1: ...") is not a pending test for S1 (the title starts at the quote)' \
  "$( grep -cx 'not-implemented: S1 presence=absent' "$OUT" )" 1 "$( cat "$OUT" )"
printf "it.todo('S1: ships');\n" > "$REPO/test/scenarios.test.ts"
git -C "$REPO" add -A; git -C "$REPO" commit -qm 'test: pending'
sc census --item ESAS-304
check 'census: outcome=blocked notImplemented=2 holds=1' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" notImplemented ) $( attr "$LINE" holds )" 'blocked 2 1' "$LINE"
check 'census: a pending test is not implemented' "$( grep -cx 'not-implemented: S1 presence=pending' "$OUT" )" 1
check 'census: an unplaced scenario with no test is not implemented' "$( grep -cx 'not-implemented: S2 presence=absent' "$OUT" )" 1
check 'census: the ESAS-296 hold is on its own line, never "not implemented"' \
  "$( grep -cx 'hold: S3 under review (fork-reopened)' "$OUT" )|$( grep -c 'not-implemented: S3' "$OUT" )" '1|0'
printf "it('S1: ships', () => {});\nit('S2: lists', () => {});\n" > "$REPO/test/scenarios.test.ts"
git -C "$REPO" commit -qam 'test: implemented'
sc census --item ESAS-304
check 'census: once both are implemented, outcome=ok notImplemented=0' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" notImplemented ) $( attr "$LINE" holds )" 'ok 0 1' "$LINE"
check 'census: exactly one verdict line' "$NV" 1

# ---------------------------------------------------------------------------
printf '\nasked at finish: placement turns a deferred unit into a block\n'
# ---------------------------------------------------------------------------
new_repo finish-asked "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,{\"type\":\"read-model\",\"label\":\"ShippedOrders\",\"subdomain\":\"orders\",\"note\":\"ask-when-ready\"}],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
check 'finish-asked: prepare ok, the read model only waits, nothing asked' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" asked )" 'ok 0' "$LINE" "$( tail -5 "$OUT" )"
agent
sc finish --item ESAS-304
check 'finish-asked: outcome=blocked reason=asked asked=1' \
  "$( attr "$LINE" verb ) $( attr "$LINE" outcome ) $( attr "$LINE" reason ) $( attr "$LINE" asked )" 'finish blocked asked 1' "$LINE" "$( tail -5 "$OUT" )"
check 'finish-asked: the question is printed for the grill' \
  "$( grep -cx 'asked: orders_rm_shipped-orders Which store backs ShippedOrders?' "$OUT" )" 1 "$( cat "$OUT" )"
check 'finish-asked: git status empty' "$( status )x" x
check 'finish-asked: HEAD is the docs commit' "$( git -C "$REPO" rev-parse HEAD )" "$DOCS"
check 'finish-asked: exactly one verdict line' "$NV" 1

# ---------------------------------------------------------------------------
printf '\nunplaced: the agent places nothing and a read model waits on the event\n'
# ---------------------------------------------------------------------------
new_repo unplaced "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304
sc finish --item ESAS-304
check 'unplaced: outcome=gate-red reason=placement-incomplete' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" \
  'gate-red placement-incomplete' "$LINE" "$( tail -5 "$OUT" )"
check 'unplaced: the waiting unit is named' \
  "$( grep -cx 'placement: orders_rm_shipped-orders still waits on orders_evt_order-shipped' "$OUT" )" 1
check 'unplaced: the tree is clean and HEAD the docs commit' "$( status )x|$( git -C "$REPO" rev-parse HEAD )" "x|$DOCS"

# ---------------------------------------------------------------------------
printf '\nnot-placed: a worklist fragment nothing waits on is STILL OWED\n'
# ---------------------------------------------------------------------------
new_repo notplaced "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED],\"edges\":[]}}"
sc prepare --item ESAS-304
sc finish --item ESAS-304
check 'not-placed: finish ok placed=0' "$( attr "$LINE" outcome ) $( attr "$LINE" placed )" 'ok 0' "$LINE"
check 'not-placed: stillOwed[] names the unplaced event and its file' \
  "$( js "$REPO/$REPORT" "[(s['node'], s['reason'], s['detail']) for s in d['stillOwed']]" )" \
  "[('orders_evt_order-shipped', 'not-placed', 'src/events.ts')]"

# ---------------------------------------------------------------------------
printf '\nobserve: a declared observe runs before the typecheck and is recorded\n'
# ---------------------------------------------------------------------------
new_repo observe "$FULL_TOOLING, \"observe\": \"sh $STUBS/observe.sh\""
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
sc finish --item ESAS-304
check 'observe: finish ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"
check 'observe: its output is shown, "none declared" is not' \
  "$( grep -cx 'observe: exit 0' "$OUT" )|$( grep -c 'observe: none declared' "$OUT" )" '1|0'
check 'observe: scaffold.json records the command and its exit' \
  "$( js "$REPO/$REPORT" "(d['observe']['command'], d['observe']['exit'])" )" "('sh $STUBS/observe.sh', 0)"
check 'observe: extract, scaffold --write, observe, typecheck, in that order' \
  "$( sed -n 's/^\([a-z]*\).*/\1/p' "$STUB_LOG" | tail -4 | tr '\n' ' ' )" 'extract scaffold observe typecheck '

# ---------------------------------------------------------------------------
printf '\nhead-moved: finish refuses when HEAD is no longer the draft'"'"'s baseSha\n'
# ---------------------------------------------------------------------------
new_repo headmoved "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
git -C "$REPO" commit -q --allow-empty -m 'chore: someone else'
moved=$( git -C "$REPO" rev-parse HEAD )
before=$( status )
sc finish --item ESAS-304
check 'head-moved: outcome=error reason=head-moved' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error head-moved' "$LINE"
check 'head-moved: nothing committed, the draft tree untouched' "$( git -C "$REPO" rev-parse HEAD )|$( status )" "$moved|$before"
check 'head-moved: exactly one verdict line' "$NV" 1

# ---------------------------------------------------------------------------
printf '\nre-run of a design that needed placement: unchanged, placed[] kept\n'
# ---------------------------------------------------------------------------
new_repo replace "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
sc prepare --item ESAS-304; agent; sc finish --item ESAS-304
check 're-run placed: the first run commits with placed=1' "$( attr "$LINE" outcome ) $( attr "$LINE" placed )" 'ok 1' "$LINE"
first=$( git -C "$REPO" rev-parse HEAD )
sc prepare --item ESAS-304
check 're-run placed: prepare ok, nothing left to place' "$( attr "$LINE" outcome )|$( js "$REPO/$REPORT" "d['worklist']" )" 'ok|[]' "$LINE"
sc finish --item ESAS-304
check 're-run placed: outcome=ok reason=unchanged' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'ok unchanged' "$LINE" \
  "$( git -C "$REPO" log --format=%s "$first"..HEAD )"
check 're-run placed: no second commit' "$( git -C "$REPO" rev-parse HEAD )" "$first"
check 're-run placed: the committed placed[] still names the event' \
  "$( git -C "$REPO" show HEAD:$REPORT | python3 -c 'import json,sys; print([p["node"] for p in json.load(sys.stdin)["placed"]])' )" \
  "['orders_evt_order-shipped']"
check 're-run placed: the tree is clean' "$( status )x" x

# ---------------------------------------------------------------------------
printf '\nrestore on a failed prepare re-run: the deleted untouched stub comes back\n'
# ---------------------------------------------------------------------------
new_repo rerun-asked "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304; sc finish --item ESAS-304
check 'rerun: the first run commits the stub' "$( attr "$LINE" outcome )|$( git -C "$REPO" ls-files src/read-models )" 'ok|src/read-models/placed-orders.ts' "$LINE"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM,{\"type\":\"command\",\"label\":\"ShipOrder\",\"subdomain\":\"orders\",\"note\":\"ask\"}],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304
check 'rerun asked: outcome=blocked reason=asked' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'blocked asked' "$LINE"
check 'rerun asked: the deleted stub is restored, git status empty' \
  "$( status )x|$( [ -f "$REPO/src/read-models/placed-orders.ts" ] && echo present )" 'x|present'
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
SC_STUB_MODE=fail; export SC_STUB_MODE
sc prepare --item ESAS-304
unset SC_STUB_MODE
check 'rerun refused: outcome=error reason=scaffold-failed' "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error scaffold-failed' "$LINE"
check 'rerun refused: the deleted stub is restored, git status empty' \
  "$( status )x|$( [ -f "$REPO/src/read-models/placed-orders.ts" ] && echo present )" 'x|present'

# ---------------------------------------------------------------------------
printf '\ncrash: an unexpected error still restores the tree and prints one verdict\n'
# ---------------------------------------------------------------------------
SC_STUB_MODE=oops; export SC_STUB_MODE
sc prepare --item ESAS-304
unset SC_STUB_MODE
check 'crash in prepare: outcome=error reason=exception' "$( attr "$LINE" verb ) $( attr "$LINE" outcome ) $( attr "$LINE" reason )" \
  'prepare error exception' "$LINE" "$( tail -5 "$OUT" )"
check 'crash in prepare: exactly one verdict line' "$NV" 1
check 'crash in prepare: the deleted stub is restored, git status empty' \
  "$( status )x|$( [ -f "$REPO/src/read-models/placed-orders.ts" ] && echo present )" 'x|present'
sc prepare --item ESAS-304
check 'crash in prepare: recovery is possible, the next prepare is ok' "$( attr "$LINE" outcome )" ok "$LINE"
sc finish --item ESAS-304 --abort

new_repo crash-finish "$FULL_TOOLING"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM,$N_PLACED_RM],\"edges\":[$E_SHIPPED,$E_PLACED]}}"
sc prepare --item ESAS-304
agent
SC_STUB_MODE=oops; export SC_STUB_MODE
sc finish --item ESAS-304
unset SC_STUB_MODE
check 'crash in finish: outcome=error reason=exception' "$( attr "$LINE" verb ) $( attr "$LINE" outcome ) $( attr "$LINE" reason )" \
  'finish error exception' "$LINE" "$( tail -5 "$OUT" )"
check 'crash in finish: exactly one verdict line' "$NV" 1
check 'crash in finish: git status empty, HEAD the docs commit' "$( status )x|$( git -C "$REPO" rev-parse HEAD )" "x|$DOCS"

# ---------------------------------------------------------------------------
printf '\nmaps: --map is repeatable and reaches the scaffolder in the order given\n'
# ---------------------------------------------------------------------------
# A fleet's step 0 passes one --map per unit projection (ESAS-297's repeatable
# --map). The two maps live under the gitignored .blueprint/, as a run dir's
# projections do, and are named against sort order (z before a), so a launcher
# that sorted, deduplicated by name or kept only the last would be caught.
sha(){ python3 -c 'import hashlib,sys; print("sha256:" + hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
new_repo maps "$FULL_TOOLING"
mkdir -p "$REPO/.blueprint/units"
printf '{"mapId": "U-2", "scenarios": [{"id":"S1","title":"ships","status":"agreed","anchor":"x"}]}\n' > "$REPO/.blueprint/units/z-first.map.json"
printf '{"mapId": "U-1", "scenarios": [{"id":"S2","title":"lists","status":"agreed","anchor":"y"}]}\n' > "$REPO/.blueprint/units/a-second.map.json"
Z=.blueprint/units/z-first.map.json A=.blueprint/units/a-second.map.json
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304 --map "$Z" --map "$A"
check 'maps: prepare with two --map is ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"
check 'maps: the dry-run and the --write run each received both maps, in the order given' \
  "$( tr '\n' '|' < "$MAP_LOG" )" "$REPO/$Z $REPO/$A|$REPO/$Z $REPO/$A|"
sc finish --item ESAS-304 --map "$Z" --map "$A"
check 'maps: finish with two --map commits' "$( attr "$LINE" outcome ) $( git -C "$REPO" log -1 --format=%s )" \
  'ok chore(ESAS-304): scaffold the agreed design' "$LINE" "$( tail -5 "$OUT" )"
check 'maps: finish'"'"'s scaffolder received both maps, in the order given' \
  "$( tail -n 1 "$MAP_LOG" )" "$REPO/$Z $REPO/$A"
check 'maps: the default <path>/map.json is not passed when --map is given' "$( grep -c 'docs/prs/ESAS-304/map.json' "$MAP_LOG" )" 0
check 'maps: scaffold.json inputs.maps[] records each map and its digest, in the order given' \
  "$( js "$REPO/$REPORT" "[(m['file'], m['digest']) for m in d['inputs']['maps']]" )" \
  "[('$Z', '$( sha "$REPO/$Z" )'), ('$A', '$( sha "$REPO/$A" )')]"
check 'maps: the scenarios of both maps reached the report' \
  "$( js "$REPO/$REPORT" "[t['scenarioId'] for t in d['scenarioTests']]" )" "['S1', 'S2']"

# A fleet passes absolute paths: inside the repo the report records them
# repo-relative, so the committed report names no checkout; outside, as given.
new_repo maps-abs "$FULL_TOOLING"
mkdir -p "$REPO/.blueprint/units" "$TMP/outside"
printf '{"mapId": "U-1", "scenarios": []}\n' > "$REPO/.blueprint/units/u.map.json"
printf '{"mapId": "U-2", "scenarios": []}\n' > "$TMP/outside/o.map.json"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304 --map "$REPO/.blueprint/units/u.map.json" --map "$TMP/outside/o.map.json"
sc finish --item ESAS-304 --map "$REPO/.blueprint/units/u.map.json" --map "$TMP/outside/o.map.json"
check 'maps-abs: finish ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"
check 'maps-abs: the scaffolder still received the paths as given' \
  "$( tail -n 1 "$MAP_LOG" )" "$REPO/.blueprint/units/u.map.json $TMP/outside/o.map.json"
check 'maps-abs: inputs.maps[] records the in-repo map repo-relative, the outside one as given, each with its digest' \
  "$( js "$REPO/$REPORT" "[(m['file'], m['digest']) for m in d['inputs']['maps']]" )" \
  "[('.blueprint/units/u.map.json', '$( sha "$REPO/.blueprint/units/u.map.json" )'), ('$TMP/outside/o.map.json', '$( sha "$TMP/outside/o.map.json" )')]"

new_repo maps-missing "$FULL_TOOLING"
mkdir -p "$REPO/.blueprint/units"
printf '{"mapId": "U-2", "scenarios": []}\n' > "$REPO/.blueprint/units/z-first.map.json"
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_PLACED_RM],\"edges\":[$E_PLACED]}}"
sc prepare --item ESAS-304 --map "$Z" --map .blueprint/units/nope.map.json
check 'maps: one named map absent refuses: outcome=error reason=map-missing' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error map-missing' "$LINE"
check 'maps: the absent map is named' "$( grep -cx 'map-missing: .blueprint/units/nope.map.json' "$OUT" )" 1 "$( cat "$OUT" )"
check 'maps: the refusal ran nothing and wrote nothing' "$( wc -l < "$STUB_LOG" | tr -d ' ' )|$( status )" '0|'
git -C "$REPO" rm -q docs/prs/ESAS-304/map.json && git -C "$REPO" commit -qm 'docs: drop the map'
sc prepare --item ESAS-304
check 'maps: no --map and no <path>/map.json still refuses: reason=map-missing' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'error map-missing' "$LINE"
check 'maps: the absent default is named, and nothing ran' \
  "$( grep -cx 'map-missing: docs/prs/ESAS-304/map.json' "$OUT" )|$( wc -l < "$STUB_LOG" | tr -d ' ' )" '1|0' "$( cat "$OUT" )"
check 'maps: exactly one verdict line' "$NV" 1

# ---------------------------------------------------------------------------
printf '\nno design layer: a checkout without .blueprint/ skips loudly; a named --design that is absent is still an error\n'
# ---------------------------------------------------------------------------
# A lane worktree, or a fresh clone, holds no .blueprint/ (it is gitignored):
# with no --design named, there is nothing agreed to scaffold, which is a skip.
new_repo no-layer "$FULL_TOOLING"
rm -rf "$REPO/.blueprint"
sc prepare --item ESAS-304
check 'no-layer: no --design and no .blueprint/design.json: outcome=skipped reason=no-design-layer' \
  "$( attr "$LINE" verb ) $( attr "$LINE" outcome ) $( attr "$LINE" reason )" 'prepare skipped no-design-layer' "$LINE" "$( cat "$OUT" )"
check 'no-layer: the skip names the default it looked for' \
  "$( grep -cx 'no-design-layer: .blueprint/design.json' "$OUT" )" 1 "$( cat "$OUT" )"
check 'no-layer: exit 0, nothing ran, nothing written, one verdict line' \
  "$rc|$( wc -l < "$STUB_LOG" | tr -d ' ' )|$( status )|$NV" '0|0||1'
sc prepare --item ESAS-304 --design .work/design-snapshot/design.json
check 'no-layer: a named --design that is absent is still outcome=error reason=design-missing' \
  "$( attr "$LINE" outcome ) $( attr "$LINE" reason ) $rc" 'error design-missing 2' "$LINE"
mkdir -p "$REPO/.work/design-snapshot"
printf '.work/\n' >> "$REPO/.git/info/exclude"
printf '{"schemaVersion":1,"propose":{"nodes":[%s],"edges":[%s]}}\n' "$N_PLACED_RM" "$E_PLACED" > "$REPO/.work/design-snapshot/design.json"
( cd "$REPO" && python3 "$STUBS/extract.py" ) && mv "$REPO/.blueprint/graph.json" "$REPO/.work/design-snapshot/graph.json" && rm -rf "$REPO/.blueprint"
: > "$STUB_LOG"
sc prepare --item ESAS-304 --design .work/design-snapshot/design.json --graph .work/design-snapshot/graph.json
check 'no-layer: a named --design/--graph is read: outcome=ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"

# ---------------------------------------------------------------------------
printf '\nfleet step 0: the design layer carried into <scaffold-wt>/.blueprint/, both verbs on the defaults\n'
# ---------------------------------------------------------------------------
# /start-multi step 0's own sequence: a clean worktree on int/<run-id> cut from
# a main checkout whose HEAD is BASE, the main checkout's design.json and
# graph.json copied into <scaffold-wt>/.blueprint/ (gitignored, where the
# declared extract writes), prepare and finish with no --design/--graph and one
# absolute --map per unit, the agent placing the event between them. The read
# model waits on that event, so finish reads it satisfied only when its
# scaffolder re-run reads the graph extract just rewrote: a graph named
# elsewhere is a stale snapshot, and the placed event would still read absent.
new_repo step0-main "$FULL_TOOLING"
MAIN=$REPO
design "{\"schemaVersion\":1,\"propose\":{\"nodes\":[$N_SHIPPED,$N_SHIPPED_RM],\"edges\":[$E_SHIPPED]}}"
RUN_ID=multi-ESAS-304
WT="$TMP/step0-scaffold-wt"
git -C "$MAIN" branch "int/$RUN_ID"
git -C "$MAIN" worktree add -q "$WT" "int/$RUN_ID"
check 'step0: the main checkout is on BASE with no tracked modifications (the carry condition)' \
  "$( git -C "$MAIN" rev-parse HEAD )|$( git -C "$MAIN" status --porcelain --untracked-files=no )" "$( git -C "$WT" rev-parse HEAD )|"
mkdir -p "$WT/.blueprint" "$TMP/step0-run/units"
cp "$MAIN/.blueprint/design.json" "$MAIN/.blueprint/graph.json" "$WT/.blueprint/"
printf '{"mapId": "ESAS-304", "scenarios": []}\n' > "$TMP/step0-run/units/ESAS-304.map.json"
REPO=$WT
: > "$STUB_LOG"
sc prepare --item "$RUN_ID" --repo "$WT" --map "$TMP/step0-run/units/ESAS-304.map.json"
check 'step0: prepare on the defaults is ok' "$( attr "$LINE" outcome )" ok "$LINE" "$( tail -5 "$OUT" )"
STEP0_REPORT="$WT/$( attr "$LINE" path )/scaffold.json"
check 'step0: prepare'"'"'s worklist is the event' \
  "$( js "$STEP0_REPORT" "[f['node'] for f in d['worklist']]" )" "['orders_evt_order-shipped']"
python3 - "$STEP0_REPORT" "$WT" <<'PY'
import json, os, sys
for f in json.load(open(sys.argv[1]))["worklist"]:
    with open(os.path.join(sys.argv[2], f["file"]), "a") as fh:
        fh.write(f["code"] + "\n")
PY
sc finish --item "$RUN_ID" --repo "$WT" --map "$TMP/step0-run/units/ESAS-304.map.json"
check 'step0: finish on the defaults commits (outcome=ok)' \
  "$( attr "$LINE" outcome ) $( git -C "$WT" log -1 --format=%s )" "ok chore($RUN_ID): scaffold the agreed design" "$LINE" "$( tail -5 "$OUT" )"
check 'step0: finish counts the placed event and owes nothing (placed>=1, stillOwed=0)' \
  "$( [ "$( attr "$LINE" placed )" -ge 1 ] 2>/dev/null && echo placed-ok )|stillOwed=$( attr "$LINE" stillOwed )" 'placed-ok|stillOwed=0' "$LINE"
check 'step0: scaffold.json placed[] names the event, and stillOwed[] is empty' \
  "$( js "$STEP0_REPORT" "([p['node'] for p in d['placed']], d['stillOwed'])" )" "(['orders_evt_order-shipped'], [])"
check 'step0: the read model that waited on the event was created in the same commit' \
  "$( git -C "$WT" show --name-only --format= HEAD -- src/read-models | tr '\n' '|' )" 'src/read-models/shipped-orders.ts|'
check 'step0: the main checkout is untouched' "$( git -C "$MAIN" status --porcelain | tr '\n' '|' )x" x

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
