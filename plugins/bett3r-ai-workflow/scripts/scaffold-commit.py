#!/usr/bin/env python3
"""The design-end scaffold commit (ESAS-304): one commit of everything derivable
from the agreed design, made only when the host's declared typecheck is green.

/design commits its docs (`docs(<id>): design`), then runs Step 4b:

  scaffold-commit prepare --item <id> [--repo DIR] [--design FILE] [--graph FILE] [--map FILE ...]
  (an agent places the topology fragments the report's worklist[] names)
  scaffold-commit finish  --item <id> [--repo DIR] [--design FILE] [--graph FILE] [--map FILE ...] [--abort]
  scaffold-commit census  --item <id> [--repo DIR]

Every run ends in exactly ONE line (ADR-004: read the line, never the exit code alone):

    SCAFFOLD-COMMIT:v1 verb=<prepare|finish|census> outcome=<ok|skipped|blocked|gate-red|error> [key=value ...]

prepare and finish carry the counts created, appended, placed, stillOwed, held,
asked, stale and edited; census carries notImplemented and holds. Exit 0 for ok
and skipped, 1 for gate-red, 2 for error, 3 for blocked. An unexpected failure
prints `exception: <type>: <message>` and ends outcome=error reason=exception,
after prepare or finish restored the tree as on any other non-ok outcome.

It runs ONLY commands `.blueprint.config.json` declares under `designTooling`,
never a framework default: `scaffold` and `typecheck` are both required (either
missing is outcome=skipped reason=undeclared-designTooling.<key>, and nothing
runs); `extract` and `observe` run when declared. `scaffold` is called with
`--design <file> --graph <file> --map <file> [--map <file> ...] --json [--write]`,
the scaffold-core CLI contract, whose `--map` is repeatable and read in argv
order; the others with no arguments. Every command runs in the repository root
through `sh -c`.

--map is repeatable here too: each one is handed to the scaffolder as its own
`--map`, in the order given (a fleet's step 0 passes one per unit projection).
With none given the map is <path>/map.json. Every map named, or the default,
must be a file, else outcome=error reason=map-missing (the missing path printed
as `map-missing: <path>`) and nothing runs: a named map that is absent is a
lost input, never one to skip. --design, --graph and --map are relative to the
repository root; an absolute path is used as given. With no --design named and
no .blueprint/design.json on disk the checkout has no design layer (it is
gitignored, and a lane worktree holds none): outcome=skipped
reason=no-design-layer, the default printed as `no-design-layer: <path>`, and
nothing runs. A --design that is named and absent stays
outcome=error reason=design-missing, as an absent --graph does.

prepare
  Refuses a dirty tree (reason=dirty-tree): the restore below is only exact
  because the tree was clean. Then, against the committed <path>/scaffold.json
  of an earlier run, deletes each UNTOUCHED stub (`git hash-object` equals its
  manifest blob) and reports each EDITED one, which is never touched; re-runs
  `extract` when it deleted any, so the graph no longer counts them as code.
  A deleted stub the scaffolder does not write again is STALE: each barrel line
  the committed report's appended[] recorded for its node is removed (unless
  this run appends the same line), and listed on the stale entry as barrel[].
  Holds out every proposed node and edge whose comment thread has an open
  remark (unresolved, not a reaction; a reply rolls up to the element its root
  is anchored on), and every edge touching a held node: the scaffolder reads a
  copy of the design without them. Dry-runs the scaffolder and classifies its
  blocks: code `no-template` is STILL OWED (reported, the commit proceeds),
  anything else is ASKED (a missing decision: outcome=blocked reason=asked, the
  questions printed as `asked: <node> <question>`, the tree restored, deleted
  stubs included, as on every other non-ok prepare). Then runs it
  with --write (create-only files plus guarded barrel lines) and writes the
  draft report. worklist[] is every topology fragment (artifact command, event
  or invariant) for the placing agent; any other fragment is registration and
  stays STILL OWED for /build.

finish
  Needs the draft report and HEAD still at its baseSha. `--abort` restores the
  tree (outcome=gate-red reason=aborted). Otherwise runs `extract`, re-runs the
  scaffolder with --write so units deferred on a placed fragment get written,
  runs `observe` (else prints `observe: none declared`), then the typecheck. A
  unit still deferred on a worklist node is a placement failure
  (gate-red reason=placement-incomplete); one deferred on anything else is
  STILL OWED. placed[] is this run's placed worklist plus the committed report's
  placed[] entries off it (placed by an earlier run). On green it commits every
  change plus <path>/scaffold.json as `chore(<id>): scaffold the agreed design`;
  when the report equals the committed one and nothing else changed, it commits
  nothing (reason=unchanged). The comparison leaves out what a re-run recomputes
  from a tree already holding the scaffold: baseSha, worklist[], the raw
  scaffolder JSON and the graph digest (see VOLATILE). Past the two checks above, every non-ok finish restores
  the tracked edits and removes the new paths: the docs commit stands.

census
  Reads the committed report's scenarioTests[] and unplaced[] by scenario id and
  prints `not-implemented: <id> presence=<absent|pending>` for each with no
  implemented test (a string starting "<id>: " right after its opening quote,
  on a line with no `.todo(`, in any tracked or untracked, not ignored, file
  outside the work-docs root), and each ESAS-296 hold
  (scenariosExcluded[] reason review) as `hold: <id> under review (<why>)`,
  never as not implemented. outcome=blocked when any is not implemented: the
  caller decides whether that warns (a fleet lane) or blocks.

The report, <path>/scaffold.json (<path> from work-docs-path): the final
scaffolder JSON (`scaffolder`), manifest[] {file, node, blob}, worklist[],
placed[], held[], stillOwed[], asked[], stale[] {file, node, barrel[]?}, edited[], observe, the
scaffolder's scenarioTests[], unplaced[] and scenariosExcluded[], input digests
(inputs.maps[] {file, digest}, one per map in the order given, file
repo-relative when the map lies inside the repo, else as given; then the
design and the graph) and baseSha.
"""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

TOKEN = "SCAFFOLD-COMMIT:v1"
CONFIG = ".blueprint.config.json"
REPORT = "scaffold.json"
PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK_DOCS_PATH = os.path.join(PLUGIN, "bin", "work-docs-path")
COUNT_KEYS = ("created", "appended", "placed", "stillOwed", "held", "asked", "stale", "edited")
# Fragments the placing agent writes in /design; every other fragment is
# registration (or a test) and is left for /build (ESAS-289-F3, P10).
TOPOLOGY = ("command", "event", "invariant")
FLAGS = {"prepare": ("item", "repo", "design", "graph", "map"),
         "finish": ("item", "repo", "design", "graph", "map", "abort"),
         "census": ("item", "repo")}
BOOLEAN_FLAGS = ("abort",)
# Flags that may be given more than once, kept as a list in argv order.
REPEATABLE_FLAGS = ("map",)
DEFAULT_DESIGN = ".blueprint/design.json"
EXIT = {"ok": 0, "skipped": 0, "gate-red": 1, "error": 2, "blocked": 3}
# The node id a proposed node takes: blueprint-schema's nodeId/slugify
# (graph.ts) and NODE_ABBREV (nodes.ts); `invariant` is the abbreviation the
# scaffold core reserves for it (filter.ts scaffoldNodeId).
NODE_ABBREV = {"aggregate": "agg", "system": "sys", "command": "cmd", "event": "evt", "policy": "pol",
               "read-model": "rm", "external-system": "ext", "datastore": "tbl", "cache": "cache",
               "ui": "ui", "postgres-view": "view", "invariant": "inv"}


class Refusal(Exception):
    def __init__(self, outcome, reason, **attrs):
        super().__init__(reason)
        self.outcome, self.reason, self.attrs = outcome, reason, attrs


def verdict(verb, outcome, counts=None, **extra):
    parts = [TOKEN, f"verb={verb or 'none'}", f"outcome={outcome}"]
    if counts is not None:
        parts += [f"{k}={counts.get(k, 0)}" for k in COUNT_KEYS]
    parts += [f"{k}={v}" for k, v in extra.items() if v is not None]
    print(" ".join(parts))
    return EXIT[outcome]


# --- arguments, config, paths --------------------------------------------------

def parse_flags(verb, argv):
    flags, i = {}, 0
    while i < len(argv):
        arg = argv[i]
        if not arg.startswith("--"):
            raise Refusal("error", "unexpected-argument")
        name = arg[2:]
        if name not in FLAGS[verb]:
            raise Refusal("error", f"unknown-flag-{name}")
        if name in BOOLEAN_FLAGS:
            flags[name] = True
            i += 1
            continue
        if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
            raise Refusal("error", f"missing-value-{name}")
        if name in REPEATABLE_FLAGS:
            flags.setdefault(name, []).append(argv[i + 1])
        else:
            flags[name] = argv[i + 1]
        i += 2
    if "item" not in flags:
        raise Refusal("error", "missing-item")
    return flags


def git(repo, *args, check=True):
    run = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if check and run.returncode != 0:
        raise Refusal("error", "git-failed", cmd=args[0])
    return run


def repo_root(flags):
    if "repo" in flags:
        return os.path.abspath(flags["repo"])
    run = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if run.returncode != 0:
        raise Refusal("error", "not-a-git-repo")
    return run.stdout.strip()


def work_docs_path(repo, item):
    """The folder the report lives in: work-docs-path's one rule, never restated here."""
    run = subprocess.run(["sh", WORK_DOCS_PATH, "--item", item, "--repo", repo], capture_output=True, text=True)
    lines = [l for l in run.stdout.splitlines() if l.strip()]
    line = lines[-1] if lines else ""
    attrs = dict(p.split("=", 1) for p in line.split()[1:] if "=" in p)
    if not line.startswith("WORK-DOCS-PATH:v1 outcome=ok") or "path" not in attrs:
        raise Refusal("error", f"work-docs-path-{attrs.get('reason', 'no-verdict')}")
    return attrs["path"], attrs["id"]


def tooling(repo):
    """designTooling, with both required keys checked; skipped when either is undeclared."""
    path = os.path.join(repo, CONFIG)
    data = {}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, UnicodeDecodeError, ValueError):
            raise Refusal("error", "config-unparseable")
    tools = data.get("designTooling") if isinstance(data, dict) else None
    tools = tools if isinstance(tools, dict) else {}
    for key in ("scaffold", "typecheck"):
        value = tools.get(key)
        if not isinstance(value, str) or not value.strip():
            raise Refusal("skipped", f"undeclared-designTooling.{key}")
    return {k: v for k, v in tools.items() if k in ("scaffold", "typecheck", "extract", "observe")
            and isinstance(v, str) and v.strip()}


def recorded(repo, given):
    """A map path as the report records it: repo-relative when it lies inside the
    repo (a fleet passes absolute paths), else as given."""
    rel = os.path.relpath(os.path.realpath(os.path.join(repo, given)), os.path.realpath(repo))
    return given if rel == ".." or rel.startswith(".." + os.sep) else rel


def inputs_of(repo, flags, path):
    if "design" not in flags and not os.path.isfile(os.path.join(repo, DEFAULT_DESIGN)):
        # A checkout with no design layer (.blueprint/ is gitignored; a lane
        # worktree or fresh clone holds none) has nothing agreed to scaffold.
        print(f"no-design-layer: {DEFAULT_DESIGN}")
        raise Refusal("skipped", "no-design-layer")
    design = os.path.join(repo, flags.get("design", DEFAULT_DESIGN))
    graph = os.path.join(repo, flags.get("graph", ".blueprint/graph.json"))
    named = flags.get("map") or [f"{path}/map.json"]
    maps = [{"given": m, "file": recorded(repo, m), "path": os.path.join(repo, m)} for m in named]
    for m in maps:
        if not os.path.isfile(m["path"]):
            print(f"map-missing: {m['given']}")
            raise Refusal("error", "map-missing")
    for name, file in (("design", design), ("graph", graph)):
        if not os.path.isfile(file):
            raise Refusal("error", f"{name}-missing")
    return design, graph, maps


# --- commands -------------------------------------------------------------------

def run_declared(repo, command, args=()):
    """A declared command, run as written plus quoted arguments. Output captured."""
    line = command + "".join(" " + shlex.quote(a) for a in args)
    return subprocess.run(["sh", "-c", line], cwd=repo, capture_output=True, text=True)


def show_tail(label, run, n=20):
    text = (run.stdout or "") + (run.stderr or "")
    lines = [l for l in text.splitlines() if l.strip()][-n:]
    print(f"{label}: exit {run.returncode}")
    for l in lines:
        print(f"  | {l}")


def scaffold(repo, tools, design, graph, maps, write):
    args = ["--design", design, "--graph", graph]
    for m in maps:
        args += ["--map", m["path"]]
    args += ["--json"] + (["--write"] if write else [])
    run = run_declared(repo, tools["scaffold"], args)
    if run.returncode not in (0, 3):
        show_tail("scaffold", run)
        raise Refusal("error", "scaffold-failed")
    try:
        result = json.loads(run.stdout)
    except ValueError:
        show_tail("scaffold", run)
        raise Refusal("error", "scaffold-output-unparseable")
    if not isinstance(result, dict):
        raise Refusal("error", "scaffold-output-unparseable")
    return result


def extract(repo, tools):
    if "extract" not in tools:
        print("extract: none declared")
        return
    run = run_declared(repo, tools["extract"])
    if run.returncode != 0:
        show_tail("extract", run)
        raise Refusal("error", "extract-failed")


# --- the tree -------------------------------------------------------------------

def is_clean(repo):
    return git(repo, "status", "--porcelain").stdout.strip() == b""


def restore(repo):
    """Back to HEAD (the docs commit): unstage everything, restore every tracked
    edit and deletion, remove every new (untracked, not ignored) path."""
    git(repo, "reset", "-q")
    changed = [p for p in git(repo, "diff", "--name-only", "-z").stdout.decode().split("\0") if p]
    if changed:
        git(repo, "checkout", "--", *changed)
    new = [p for p in git(repo, "ls-files", "--others", "--exclude-standard", "-z").stdout.decode().split("\0") if p]
    for rel in new:
        os.remove(os.path.join(repo, rel))
        prune_dirs(repo, os.path.dirname(rel))


def prune_dirs(repo, rel):
    while rel:
        full = os.path.join(repo, rel)
        if not os.path.isdir(full) or os.listdir(full):
            return
        os.rmdir(full)
        rel = os.path.dirname(rel)


def blob(repo, rel):
    return git(repo, "hash-object", "--", rel).stdout.decode().strip()


def digest(file):
    with open(file, "rb") as fh:
        return "sha256:" + hashlib.sha256(fh.read()).hexdigest()


def read_json(file):
    with open(file, encoding="utf-8") as fh:
        return json.load(fh)


def write_json(file, data):
    os.makedirs(os.path.dirname(file), exist_ok=True)
    with open(file, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(data, indent=2, sort_keys=True) + "\n")


# --- agreed: held elements ------------------------------------------------------

def slugify(label):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", label)
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", s)
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s)
    return s.strip("-").lower()


def node_id(node):
    return f"{slugify(node.get('subdomain', ''))}_{NODE_ABBREV.get(node.get('type'), node.get('type'))}_{slugify(node.get('label', ''))}"


def anchor_key(anchor):
    """blueprint-schema's commentAnchorKey, for a node or edge anchor."""
    if isinstance(anchor, str):
        return f"node:{anchor}"
    if isinstance(anchor, dict) and {"from", "to", "kind"} <= anchor.keys():
        return f"edge:{anchor['from']}|{anchor['to']}|{anchor['kind']}"
    return None


def hold(design):
    """The design the scaffolder may read, and held[]: every proposed node and
    edge whose thread has an open remark, every edge touching a held node."""
    comments = [c for c in design.get("comments") or [] if isinstance(c, dict)]
    by_id = {c.get("id"): c for c in comments}

    def root_anchor(comment):
        seen = set()
        while isinstance(comment.get("anchor"), dict) and "commentId" in comment["anchor"]:
            parent = by_id.get(comment["anchor"]["commentId"])
            if parent is None or id(parent) in seen:
                return None
            seen.add(id(parent))
            comment = parent
        return comment.get("anchor")

    open_remark = {}
    for c in comments:
        if c.get("resolved") or c.get("reaction") is not None:
            continue
        key = anchor_key(root_anchor(c))
        if key is not None and key not in open_remark:
            open_remark[key] = c.get("id")

    propose = design.get("propose") or {}
    held, held_nodes, nodes, edges = [], {}, [], []
    for node in propose.get("nodes") or []:
        nid = node_id(node)
        comment = open_remark.get(f"node:{nid}")
        if comment is None:
            nodes.append(node)
        else:
            held_nodes[nid] = comment
            held.append({"element": f"node:{nid}", "commentId": comment})
    for edge in propose.get("edges") or []:
        key = anchor_key(edge)
        comment = open_remark.get(key) or held_nodes.get(edge.get("from")) or held_nodes.get(edge.get("to"))
        if comment is None:
            edges.append(edge)
        else:
            held.append({"element": key, "commentId": comment})
    filtered = dict(design, propose=dict(propose, nodes=nodes, edges=edges))
    return filtered, sorted(held, key=lambda h: h["element"])


def scaffold_agreed(repo, tools, design_path, graph, maps, write):
    """One scaffolder run over the agreed design (the held elements removed)."""
    try:
        design = read_json(design_path)
    except (OSError, UnicodeDecodeError, ValueError):
        raise Refusal("error", "design-unparseable")
    filtered, held = hold(design)
    with tempfile.TemporaryDirectory() as tmp:
        agreed = os.path.join(tmp, "design.json")
        write_json(agreed, filtered)
        return scaffold(repo, tools, agreed, graph, maps, write), held


# --- classification -------------------------------------------------------------

def classify(result):
    """asked[] and stillOwed[] from one scaffolder result."""
    asked, owed = [], []
    for s in result.get("skipped") or []:
        if s.get("reason") not in ("blocked", "error"):
            continue
        decisions = s.get("decisions") or []
        if decisions and all(d.get("code") == "no-template" for d in decisions):
            owed.append({"node": s.get("node"), "reason": "no-template", "detail": s.get("detail")})
        else:
            question = "; ".join(d.get("question", "") for d in decisions) or s.get("detail") or "blocked"
            asked.append({"node": s.get("node"), "question": question})
    for t in result.get("scenarioTests") or []:
        if t.get("outcome") == "decision":
            asked.append({"node": t.get("scenarioId"), "question": "scenario test placement needs a decision"})
    for f in result.get("fragments") or []:
        if not is_topology(f):
            owed.append({"node": f.get("node"), "reason": "registration", "detail": f.get("file")})
    return asked, owed


def is_topology(fragment):
    return fragment.get("artifact") in TOPOLOGY and not str(fragment.get("file", "")).startswith("unplaced:")


def created_files(result):
    return [{"file": f["file"], "node": f.get("node")} for f in result.get("files") or [] if f.get("file")]


def appended_lines(result, created):
    paths = {c["file"] for c in created}
    return [a for a in result.get("appends") or [] if a.get("kind") == "barrel" and a.get("file") not in paths]


def by_key(items, *keys):
    return sorted(items, key=lambda x: tuple(str(x.get(k)) for k in keys))


def counts_of(report):
    return {"created": len(report["created"]), "appended": len(report["appended"]), "placed": len(report["placed"]),
            "stillOwed": len(report["stillOwed"]), "held": len(report["held"]), "asked": len(report["asked"]),
            "stale": len(report["stale"]), "edited": len(report["edited"])}


# --- verbs ----------------------------------------------------------------------

def prepare(repo, flags):
    tools = tooling(repo)
    path, fid = work_docs_path(repo, flags["item"])
    if not is_clean(repo):
        raise Refusal("error", "dirty-tree")
    design, graph, maps = inputs_of(repo, flags, path)
    base = git(repo, "rev-parse", "HEAD").stdout.decode().strip()
    report_file = os.path.join(repo, path, REPORT)

    try:
        # Stubs of an earlier scaffold commit: untouched ones go, edited ones stay.
        previous = read_json(report_file) if os.path.isfile(report_file) else {}
        deleted, edited, kept = [], [], []
        for entry in previous.get("manifest") or []:
            rel = entry.get("file")
            if not rel or not os.path.isfile(os.path.join(repo, rel)):
                continue
            if blob(repo, rel) == entry.get("blob"):
                os.remove(os.path.join(repo, rel))
                prune_dirs(repo, os.path.dirname(rel))
                deleted.append({"file": rel, "node": entry.get("node"), "blob": entry.get("blob")})
            else:
                edited.append({"file": rel, "node": entry.get("node")})
                kept.append(entry)
        if deleted:
            extract(repo, tools)
        dry, held = scaffold_agreed(repo, tools, design, graph, maps, write=False)
        asked, _ = classify(dry)
        if asked:
            restore(repo)
            for a in asked:
                print(f"asked: {a['node']} {a['question']}")
            return verdict("prepare", "blocked", counts={"asked": len(asked), "held": len(held)},
                           reason="asked", path=path)
        result, held = scaffold_agreed(repo, tools, design, graph, maps, write=True)
        _, owed = classify(result)
        created = created_files(result)
        stale = [dict(d) for d in deleted if not os.path.exists(os.path.join(repo, d["file"]))]
        unappend(repo, stale, previous.get("appended") or [], result)
        report = {
            "phase": "prepared", "ticket": fid, "baseSha": base,
            "created": created, "appended": appended_lines(result, created),
            "worklist": by_key([f for f in result.get("fragments") or [] if is_topology(f)], "node", "file"),
            "placed": [], "placedBefore": previous.get("placed") or [], "held": held, "asked": [], "stillOwed": by_key(owed, "node", "reason"),
            "deleted": deleted, "edited": by_key(edited, "file"), "carried": kept,
            "stale": stale, "scaffolder": result,
        }
        write_json(report_file, report)
    except Refusal:
        restore(repo)
        raise
    except Exception as e:
        restore(repo)
        return crashed("prepare", e, path)
    return verdict("prepare", "ok", counts=counts_of(report), path=path)


def unappend(repo, stale, appended, result):
    """Removes, from its barrel file, each line the committed report recorded as
    appended for a stale stub's node, unless this run's scaffolder appends the
    same line again; records what it removed on the stale entry as barrel[]."""
    again = {(a.get("file"), a.get("code")) for a in result.get("appends") or []}
    for entry in stale:
        lines = [a for a in appended if a.get("node") == entry["node"] and a.get("kind") == "barrel"
                 and (a.get("file"), a.get("code")) not in again]
        removed = []
        for a in lines:
            full = os.path.join(repo, a["file"])
            if not os.path.isfile(full):
                continue
            with open(full, encoding="utf-8") as fh:
                text = fh.read().splitlines(keepends=True)
            kept = [l for l in text if l.rstrip("\r\n") != a["code"]]
            if len(kept) != len(text):
                with open(full, "w", encoding="utf-8") as fh:
                    fh.write("".join(kept))
                removed.append({"file": a["file"], "code": a["code"]})
        if removed:
            entry["barrel"] = by_key(removed, "file", "code")


def crashed(verb, error, path):
    """An unexpected failure, after the tree was restored: one line naming it, then the verdict."""
    print(f"exception: {type(error).__name__}: {error}")
    return verdict(verb, "error", counts={}, reason="exception", path=path)


def finish(repo, flags):
    tools = tooling(repo)
    path, fid = work_docs_path(repo, flags["item"])
    report_file = os.path.join(repo, path, REPORT)
    draft = read_json(report_file) if os.path.isfile(report_file) else {}
    if draft.get("phase") != "prepared":
        raise Refusal("error", "not-prepared")
    if git(repo, "rev-parse", "HEAD").stdout.decode().strip() != draft.get("baseSha"):
        raise Refusal("error", "head-moved")
    if flags.get("abort"):
        restore(repo)
        return verdict("finish", "gate-red", counts=counts_of(draft), reason="aborted", path=path)
    try:
        design, graph, maps = inputs_of(repo, flags, path)
        extract(repo, tools)
        result, held = scaffold_agreed(repo, tools, design, graph, maps, write=True)
        asked, owed = classify(result)
        if asked:
            for a in asked:
                print(f"asked: {a['node']} {a['question']}")
            raise Refusal("blocked", "asked", asked=len(asked))

        worklist = {f.get("node") for f in draft["worklist"]}
        still_fragments = {f.get("node") for f in result.get("fragments") or [] if is_topology(f)}
        for d in result.get("deferred") or []:
            waits = d.get("waitsOn") or []
            if worklist.intersection(waits):
                print(f"placement: {d.get('node')} still waits on {', '.join(waits)}")
                raise Refusal("gate-red", "placement-incomplete")
            owed.append({"node": d.get("node"), "reason": "deferred", "detail": ", ".join(waits)})
        placed = [{"node": f.get("node"), "file": f.get("file")} for f in draft["worklist"]
                  if f.get("node") not in still_fragments]
        # Placed by an earlier run (its fragment is in code, so it is off this worklist): kept.
        placed += [p for p in draft.get("placedBefore") or [] if p.get("node") not in worklist]
        owed += [{"node": f.get("node"), "reason": "not-placed", "detail": f.get("file")} for f in draft["worklist"]
                 if f.get("node") in still_fragments]

        if "observe" in tools:
            run = run_declared(repo, tools["observe"])
            show_tail("observe", run, 5)
            if run.returncode != 0:
                raise Refusal("error", "observe-failed")
            observe = {"command": tools["observe"], "exit": run.returncode}
        else:
            print("observe: none declared")
            observe = None

        run = run_declared(repo, tools["typecheck"])
        show_tail("typecheck", run)
        if run.returncode != 0:
            raise Refusal("gate-red", "typecheck-red")

        created = by_key(draft["created"] + created_files(result), "file")
        manifest = [{"file": c["file"], "node": c["node"], "blob": blob(repo, c["file"])}
                    for c in created if os.path.isfile(os.path.join(repo, c["file"]))]
        manifest = by_key(manifest + draft["carried"], "file")
        report = {
            "version": 1, "ticket": fid, "baseSha": draft["baseSha"],
            "inputs": {"maps": [{"file": m["file"], "digest": digest(m["path"])} for m in maps],
                       "design": digest(design), "graph": digest(graph)},
            "created": created, "appended": by_key(draft["appended"] + appended_lines(result, created), "file", "code"),
            "manifest": manifest, "worklist": draft["worklist"], "placed": by_key(placed, "node"),
            "held": held, "asked": [], "stillOwed": by_key(owed, "node", "reason"),
            "stale": [{k: v for k, v in d.items() if k != "blob"} for d in draft["stale"]
                      if not os.path.exists(os.path.join(repo, d["file"]))],
            "edited": draft["edited"], "observe": observe,
            "scenarioTests": result.get("scenarioTests") or [], "unplaced": result.get("unplaced") or [],
            "scenariosExcluded": result.get("scenariosExcluded") or [],
            "scaffolder": result,
        }
        if unchanged(repo, path, report):
            restore(repo)
            return verdict("finish", "ok", counts=counts_of(report), reason="unchanged", path=path)
        write_json(report_file, report)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", f"chore({fid}): scaffold the agreed design")
    except Refusal as r:
        restore(repo)
        counts = counts_of(draft)
        counts.update(r.attrs)
        return verdict("finish", r.outcome, counts=counts, reason=r.reason, path=path)
    except Exception as e:
        restore(repo)
        return crashed("finish", e, path)
    sha = git(repo, "rev-parse", "HEAD").stdout.decode().strip()
    return verdict("finish", "ok", counts=counts_of(report), path=path, commit=sha)


# What a re-run recomputes from a tree that already holds the scaffold, so it
# differs from the first run without the outcome differing: the scaffolder's raw
# JSON (a placed fragment is now `satisfied`), worklist[] (it is off it, and in
# placed[]) and the graph digest (the graph is read from code the scaffold wrote).
VOLATILE = ("baseSha", "scaffolder", "worklist")


def comparable(report):
    out = {k: v for k, v in report.items() if k not in VOLATILE}
    out["inputs"] = {k: v for k, v in (report.get("inputs") or {}).items() if k != "graph"}
    return out


def unchanged(repo, path, report):
    """The committed report says the same (VOLATILE aside) and nothing else changed."""
    rel = f"{path}/{REPORT}"
    shown = git(repo, "show", f"HEAD:{rel}", check=False)
    if shown.returncode != 0:
        return False
    try:
        committed = json.loads(shown.stdout)
    except ValueError:
        return False
    if not isinstance(committed, dict) or comparable(committed) != comparable(json.loads(json.dumps(report))):
        return False
    git(repo, "add", "-A")
    others = [p for p in git(repo, "diff", "--cached", "--name-only", "-z").stdout.decode().split("\0") if p and p != rel]
    git(repo, "reset", "-q")
    return not others


# A pending test: `.todo(` on the title's line (scaffold-core test-plan.ts PENDING).
PENDING = re.compile(r"\.todo\s*\(")


def census(repo, flags):
    path, _ = work_docs_path(repo, flags["item"])
    report_file = os.path.join(repo, path, REPORT)
    if not os.path.isfile(report_file):
        raise Refusal("skipped", "no-scaffold-report")
    report = read_json(report_file)
    if report.get("phase") == "prepared":
        raise Refusal("error", "report-not-committed")
    root = path.rsplit("/", 1)[0]
    ids = sorted({t.get("scenarioId") for t in (report.get("scenarioTests") or []) + (report.get("unplaced") or [])
                  if t.get("scenarioId")})
    missing = 0
    for sid in ids:
        presence = presence_of(repo, sid, root)
        if presence != "implemented":
            missing += 1
            print(f"not-implemented: {sid} presence={presence}")
    holds = [e for e in report.get("scenariosExcluded") or [] if e.get("reason") == "review"]
    for e in sorted(holds, key=lambda e: str(e.get("scenarioId"))):
        print(f"hold: {e.get('scenarioId')} under review ({e.get('review') or 'review'})")
    return verdict("census", "blocked" if missing else "ok", notImplemented=missing, holds=len(holds),
                   **({"reason": "scenario-not-implemented"} if missing else {}))


def presence_of(repo, sid, root):
    """implemented | pending | absent, by a title starting "<id>: " outside the work-docs
    root. The title starts at a string's opening quote (scaffold-core test-plan.ts
    findScenarioTests), so a comment naming the id is no test and `S1: ` never
    matches inside `XS1: `."""
    run = git(repo, "grep", "--untracked", "-h", "-F", "-e", f"{sid}: ", "--", ".", f":(exclude){root}", check=False)
    title = re.compile("['\"`]" + re.escape(sid) + ": ")
    lines = [l for l in run.stdout.decode(errors="replace").splitlines() if title.search(l)]
    if any(not PENDING.search(l) for l in lines):
        return "implemented"
    return "pending" if lines else "absent"


VERBS = {"prepare": prepare, "finish": finish, "census": census}


def main(argv):
    verb = argv[1] if len(argv) > 1 else ""
    counted = verb in ("prepare", "finish")
    try:
        if verb not in VERBS:
            raise Refusal("error", "unknown-verb")
        flags = parse_flags(verb, argv[2:])
        repo = repo_root(flags)
        return VERBS[verb](repo, flags)
    except Refusal as r:
        counts = dict(r.attrs) if counted else None
        return verdict(verb if verb in VERBS else None, r.outcome, counts=counts, reason=r.reason)
    except Exception as e:
        print(f"exception: {type(e).__name__}: {e}")
        return verdict(verb if verb in VERBS else None, "error", counts={} if counted else None, reason="exception")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
