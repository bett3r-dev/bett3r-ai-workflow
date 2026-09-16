#!/usr/bin/env python3
"""The map verbs over a design's map.json. It says what it did in ONE line.

    DESIGN-MAP:v1 outcome=ok verb=render expected=<n> payload=<n> rendered=<n> page=<path>
    DESIGN-MAP:v1 outcome=error verb=<verb> reason=<reason> [key=value ...]

Read the line, never the exit code alone (ADR-004): 0 for ok, 2 for error, and
no line at all means the script died before concluding. An error line carries
no `page=`: a caller that publishes whatever `page=` names must find nothing.

Usage:

  design-map render <map.json> --expect <n> [--out <page.html>]
  design-map check-page <map.json> <page.html> --expect <n>

`render` validates the payload against the committed schema
(`skills/design-map/map.schema.json`), then writes a self-contained HTML page
with one card per fork. The owner answers on it; each answer is written to the
artifact's `db` store as `answers/<forkId>` = `{pick, comment, updatedAt}`, the
shape of the ESAS-156 prototype's writer (esas `docs/prs/ESAS-156/map.html`,
`saveAnswer`), so answers saved there parse unchanged. When `claude.use("db")`
resolves null the page is read-only and says to reply in the terminal.
`--out` defaults to `<map dir>/<map stem>.page.html`.

A fork missing from the page is taken on its recommendation without the owner
ever seeing it, so two counts gate the render, and they catch different drops:

  count-mismatch     the payload holds a number of forks other than --expect —
                     a fork lost between the design and the payload. --expect is
                     mandatory (reason=missing-expect): an optional guard is one
                     nobody passes on the day it would have mattered.
  page-missing-forks the emitted page, parsed back, does not embed every
                     payload fork exactly once — a fork lost while drawing.

`check-page` runs the same two gates over a page already on disk (one edited
by hand, or published earlier) and writes and removes nothing; its ok line has
no `page=`.

Once the arguments parse, a render refusal leaves no page of its own at
`--out`: the page is written to a temporary file and moved into place only after
both counts hold, and a page an earlier render left at `--out` is removed, so a
refusal can never be followed by publishing a stale page. Only a file carrying
the generator marker every rendered page opens with is removed; any other file
at `--out` is left untouched, and `--out` naming the map itself is
reason=out-is-map. Other reasons:

  unknown-verb, unknown-flag-<name>, missing-map, missing-expect,
  malformed-expect, map-unreadable, map-unparseable, schema-unreadable,
  bare-actor (at=<json pointer>), schema-invalid (at=<json pointer> rule=<keyword>),
  duplicate-fork-id (id=<id>), out-path-whitespace, out-dir-missing, out-is-map,
  missing-page, page-unreadable

A bare `actor` key is refused anywhere in the payload, before the schema runs:
the map's who-level is `mapActor`, never `actor`, so a map role can never be
joined to an op's ActorId by accident.

Standard library only: `jsonschema` is not a dependency. The validator below
implements exactly the keywords the committed schema uses (listed in its
`$comment`), and meeting any other keyword is reason=schema-unreadable rather
than a keyword silently ignored.
"""

import html
import json
import os
import re
import sys
import tempfile
from html.parser import HTMLParser

TOKEN = "DESIGN-MAP:v1"
# Written into every page `render` emits; a refusal removes only a file carrying it.
GENERATOR = '<meta name="generator" content="design-map">'
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.join(SCRIPT_DIR, "..", "skills", "design-map", "map.schema.json")


class Refusal(Exception):
    def __init__(self, reason, **attrs):
        super().__init__(reason)
        self.reason = reason
        self.attrs = attrs


def verdict(outcome, **attrs):
    parts = [TOKEN, f"outcome={outcome}"]
    parts += [f"{key}={val}" for key, val in attrs.items()]
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return 0 if outcome == "ok" else 2


def parse_args(args):
    positional, flags, i = [], {}, 0
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            name = a[2:]
            if name not in ("expect", "out"):
                raise Refusal(f"unknown-flag-{name}")
            if i + 1 >= len(args):
                raise Refusal(f"missing-{name}")
            flags[name] = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1
    return positional, flags


# --- validation -------------------------------------------------------------

KEYWORDS = {
    "$schema", "$id", "$comment", "$defs", "title", "type", "const", "enum",
    "required", "properties", "additionalProperties", "items", "minItems",
    "minLength", "pattern", "$ref", "allOf", "if", "then",
}

TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
}


def pointer(path):
    return "/" + "/".join(str(p) for p in path) if path else "/"


def find_bare_actor(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "actor":
                return path + (key,)
            found = find_bare_actor(child, path + (key,))
            if found:
                return found
    elif isinstance(value, list):
        for i, child in enumerate(value):
            found = find_bare_actor(child, path + (i,))
            if found:
                return found
    return None


def ecma_pattern(pattern):
    """A schema pattern is ECMA-262, where a trailing `$` matches only at the
    end; Python's `$` also matches before a final newline, so "F1\\n" would pass."""
    return re.sub(r"(?<!\\)\$$", r"\\Z", pattern)


def same(a, b):
    """JSON equality: 1 and true are different values."""
    return type(a) is type(b) and a == b


class Validator:
    def __init__(self, schema):
        self.root = schema

    def resolve(self, ref):
        if not ref.startswith("#/$defs/"):
            raise Refusal("schema-unreadable", detail="unsupported-ref")
        return self.root["$defs"][ref[len("#/$defs/"):]]

    def errors(self, schema, value, path=()):
        """The first violation as (path, keyword), or None."""
        unknown = set(schema) - KEYWORDS
        if unknown:
            raise Refusal("schema-unreadable", detail=f"unsupported-keyword-{sorted(unknown)[0]}")
        if "$ref" in schema:
            found = self.errors(self.resolve(schema["$ref"]), value, path)
            if found:
                return found
        if "type" in schema and not TYPES[schema["type"]](value):
            return path, "type"
        if "const" in schema and not same(value, schema["const"]):
            return path, "const"
        if "enum" in schema and not any(same(value, e) for e in schema["enum"]):
            return path, "enum"
        if isinstance(value, str):
            if len(value) < schema.get("minLength", 0):
                return path, "minLength"
            if "pattern" in schema and not re.search(ecma_pattern(schema["pattern"]), value):
                return path, "pattern"
        if isinstance(value, list):
            if len(value) < schema.get("minItems", 0):
                return path, "minItems"
            if "items" in schema:
                for i, item in enumerate(value):
                    found = self.errors(schema["items"], item, path + (i,))
                    if found:
                        return found
        if isinstance(value, dict):
            for key in schema.get("required", []):
                if key not in value:
                    return path + (key,), "required"
            props = schema.get("properties", {})
            for key, child in value.items():
                if key in props:
                    found = self.errors(props[key], child, path + (key,))
                    if found:
                        return found
                elif schema.get("additionalProperties", True) is False:
                    return path + (key,), "additionalProperties"
        for sub in schema.get("allOf", []):
            found = self.errors(sub, value, path)
            if found:
                return found
        if "if" in schema and self.errors(schema["if"], value, path) is None:
            found = self.errors(schema.get("then", {}), value, path)
            if found:
                return found
        return None


def load_schema():
    try:
        with open(SCHEMA_PATH, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        raise Refusal("schema-unreadable")


def load_map(path):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        raise Refusal("map-unreadable")
    try:
        return json.loads(text)
    except ValueError:
        raise Refusal("map-unparseable")


def validate(payload):
    at = find_bare_actor(payload)
    if at:
        raise Refusal("bare-actor", at=pointer(at))
    schema = load_schema()
    found = Validator(schema).errors(schema, payload)
    if found:
        path, rule = found
        raise Refusal("schema-invalid", at=pointer(path), rule=rule)
    seen = set()
    for fork in payload["forks"]:
        if fork["id"] in seen:
            raise Refusal("duplicate-fork-id", id=fork["id"])
        seen.add(fork["id"])


# --- the page ---------------------------------------------------------------

STYLE = """
body{font:15px/1.5 system-ui,sans-serif;margin:0;background:#f6f5f2;color:#1d1d1b}
header{padding:20px 28px;border-bottom:1px solid #ddd;background:#fff}
h1{margin:0 0 4px;font-size:20px} #dbnote{color:#555;font-size:13px}
.levels{padding:12px 28px;font-size:13px;color:#444} .levels b{color:#1d1d1b}
main{padding:12px 28px 40px;display:grid;gap:14px;max-width:960px}
.fork{background:#fff;border:1px solid #ddd;border-left:5px solid #c9c9c9;border-radius:8px;padding:14px 18px}
.fork.open{border-left-color:#d4553b} .fork.mine{border-left-color:#d49a1f} .fork.done{border-left-color:#2f8f5b}
.fork.moot{opacity:.6}
.eyebrow{font-size:12px;color:#666} h3{margin:2px 0 8px;font-size:16px}
.opt{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:6px 10px;border:1px solid #e3e3e3;border-radius:6px;margin:6px 0}
.opt.rec{background:#fbf6e8} .opt.picked{outline:2px solid #2f8f5b}
.badge{font-size:11px;background:#d49a1f;color:#fff;border-radius:4px;padding:1px 5px;margin-left:6px}
textarea{width:100%;min-height:54px;box-sizing:border-box;margin-top:6px}
.btn{font:inherit;font-size:13px;padding:4px 10px;border-radius:5px;border:1px solid #bbb;background:#fff;cursor:pointer}
.btn:disabled{cursor:not-allowed;opacity:.5} .saved{font-size:12px;color:#555;margin-left:8px}
"""

# The answer writer is the ESAS-156 prototype's (esas docs/prs/ESAS-156/map.html,
# saveAnswer and the db bootstrap), so an answers store written by either page
# reads identically.
SCRIPT = """
const MAP = JSON.parse(document.getElementById("map-data").textContent);
const FORKS = {};
MAP.forks.forEach(f => { FORKS[f.id] = f; });
let db = null;
let answers = {};

function stateOf(id) {
  const f = FORKS[id];
  if (f.status === "moot") return "moot";
  if (answers[id]) return "done";
  return f.status === "decided" ? "mine" : "open";
}
function recKey(f) {
  const o = f.options.find(o => o.recommended);
  return o ? o.key : null;
}
function renderCard(id) {
  const card = document.querySelector('[data-fork-id="' + id + '"]');
  const a = answers[id] || null;
  card.className = "fork " + stateOf(id);
  card.querySelectorAll("[data-pick]").forEach(b => {
    const picked = !!(a && a.pick === b.dataset.pick);
    b.closest(".opt").classList.toggle("picked", picked);
    b.textContent = picked ? "Chosen" : "Choose";
  });
  const ta = card.querySelector("textarea");
  if (a && document.activeElement !== ta) ta.value = a.comment || "";
  card.querySelector(".saved").textContent = a && a.updatedAt
    ? "Saved " + new Date(a.updatedAt).toLocaleString()
    : (db ? "" : "Answers can't be saved in this view. Reply in the terminal.");
  card.querySelectorAll("button, textarea").forEach(el => { el.disabled = !db || FORKS[id].status === "moot"; });
}
function renderAll() { Object.keys(FORKS).forEach(renderCard); }

async function saveAnswer(id, patch) {
  if (!db) return;
  const prev = answers[id] || {};
  const doc = { pick: prev.pick || null, comment: prev.comment || "", ...patch, updatedAt: new Date().toISOString() };
  answers[id] = doc; renderCard(id);
  const s = document.querySelector('[data-fork-id="' + id + '"] .saved');
  try { await db.doc("answers/" + id).set(doc); s.textContent = "Saved"; }
  catch (e) { s.textContent = "Not saved: " + (e && e.message || "store refused the write"); }
}

document.addEventListener("click", e => {
  const card = e.target.closest("[data-fork-id]");
  if (!card) return;
  const id = card.dataset.forkId;
  const comment = card.querySelector("textarea").value;
  if (e.target.dataset.pick) { saveAnswer(id, { pick: e.target.dataset.pick, comment }); return; }
  if (e.target.dataset.action === "save") { saveAnswer(id, { comment }); return; }
  if (e.target.dataset.action === "agree") { saveAnswer(id, { pick: recKey(FORKS[id]), comment }); return; }
});

renderAll();
(async () => {
  try { db = window.claude && window.claude.use ? await window.claude.use("db") : null; } catch (_) { db = null; }
  const note = document.getElementById("dbnote");
  if (!db) {
    note.textContent = "Answers can't be saved in this view. Reply in the terminal.";
    renderAll();
    return;
  }
  note.textContent = "Answers save as you click. Claude reads them back.";
  const col = db.collection("answers");
  const apply = snap => { const next = {}; (snap.docs || []).forEach(d => { next[d.id] = d.data(); }); answers = next; renderAll(); };
  if (typeof col.onSnapshot === "function") col.onSnapshot(apply, () => { note.textContent = "Lost the answer store; reload to reconnect."; });
  else col.get().then(apply);
  renderAll();
})();
"""


def esc(text):
    return html.escape(text, quote=True)


def fork_card(fork, deliverable_of):
    fid = fork["id"]
    where = deliverable_of.get(fid)
    eyebrow = esc(fid) + (f" &middot; {esc(where['id'])} {esc(where['title'])}" if where else "")
    status = fork["status"]
    if status == "decided":
        eyebrow += f" &middot; decided ({esc(fork['by'])})"
    elif status == "moot":
        eyebrow += f" &middot; moot: {esc(fork['reason'])}"
    options = "".join(
        f'<div class="opt{" rec" if o.get("recommended") else ""}"><div><b>{esc(o["key"])}</b> {esc(o["label"])}'
        f'{"<span class=badge>recommended</span>" if o.get("recommended") else ""}</div>'
        f'<button class="btn" data-pick="{esc(o["key"])}" disabled>Choose</button></div>'
        for o in fork["options"]
    )
    return (
        f'<article class="fork" data-fork-id="{esc(fid)}">'
        f'<div class="eyebrow">{eyebrow}</div><h3>{esc(fork["title"])}</h3>'
        f'<p>{esc(fork["problem"])}</p>{options}'
        f'<p><b>Recommendation.</b> {esc(fork["recommendation"])}</p>'
        f'<textarea placeholder="Anything the options miss, or a question for me" disabled></textarea>'
        f'<div><button class="btn" data-action="save" disabled>Save comment</button> '
        f'<button class="btn" data-action="agree" disabled>Agree with the recommendation</button>'
        f'<span class="saved"></span></div></article>'
    )


def levels(payload):
    if payload["layout"] != "impactMap":
        return ""
    def names(key):
        return ", ".join(esc(n["title"]) for n in payload[key])
    return (
        f'<div class="levels"><b>Goal</b> {esc(payload["goal"]["title"])} &middot; '
        f'<b>Actors</b> {names("mapActors")} &middot; <b>Impacts</b> {names("impacts")} &middot; '
        f'<b>Deliverables</b> {names("deliverables")}</div>'
    )


def page(payload):
    deliverable_of = {}
    for d in payload.get("deliverables", []):
        for fid in d.get("forks", []):
            deliverable_of.setdefault(fid, d)
    # `<` escaped so no string in the payload can close the data script early.
    data = json.dumps(payload, ensure_ascii=False).replace("<", "\\u003c")
    cards = "".join(fork_card(f, deliverable_of) for f in payload["forks"])
    return (
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        f"{GENERATOR}"
        f"<title>{esc(payload['title'])}</title><style>{STYLE}</style></head><body>"
        f"<header><h1>{esc(payload['title'])}</h1>"
        "<div>A fork you leave unanswered is taken on its recommendation.</div>"
        "<div id=\"dbnote\">Connecting to the answer store&hellip;</div></header>"
        f"{levels(payload)}<main>{cards}</main>"
        f"<script type=\"application/json\" id=\"map-data\">{data}</script>"
        f"<script>{SCRIPT}</script></body></html>\n"
    )


class ForkCards(HTMLParser):
    """Collects the data-fork-id of every <article> in an emitted page."""

    def __init__(self):
        super().__init__()
        self.ids = []

    def handle_starttag(self, tag, attrs):
        if tag == "article":
            fid = dict(attrs).get("data-fork-id")
            if fid is not None:
                self.ids.append(fid)


def drawn_forks(text):
    parser = ForkCards()
    parser.feed(text)
    parser.close()
    return parser.ids


def check_page(payload, expected, text):
    """The page gate: every payload fork drawn exactly once, or a refusal."""
    drawn = drawn_forks(text)
    wanted = [f["id"] for f in payload["forks"]]
    if sorted(drawn) != sorted(wanted):
        raise Refusal("page-missing-forks", expected=expected, payload=len(wanted), rendered=len(set(drawn)))
    return len(drawn)


def expectation(flags):
    if "expect" not in flags:
        raise Refusal("missing-expect")
    if not re.fullmatch(r"[0-9]+", flags["expect"]):
        raise Refusal("malformed-expect")
    return int(flags["expect"])


def counted_payload(map_path, expected):
    payload = load_map(map_path)
    validate(payload)
    count = len(payload["forks"])
    if count != expected:
        raise Refusal("count-mismatch", expected=expected, payload=count)
    return payload, count


def same_file(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def remove_page(out):
    """Remove a page an earlier render left at --out, and nothing else: a file
    without the generator marker (the map itself, anything a caller named) is
    never touched."""
    try:
        with open(out, encoding="utf-8", errors="replace") as fh:
            head = fh.read(4096)
    except OSError:
        return
    if GENERATOR in head and os.path.isfile(out):
        os.remove(out)


def render(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    map_path = positional[0]
    stem = os.path.splitext(os.path.basename(map_path))[0]
    out = flags.get("out") or os.path.join(os.path.dirname(map_path) or ".", f"{stem}.page.html")
    try:
        expected = expectation(flags)
        if re.search(r"\s", out):
            raise Refusal("out-path-whitespace")
        if same_file(out, map_path):
            raise Refusal("out-is-map")
        payload, count = counted_payload(map_path, expected)
        text = page(payload)
        rendered = check_page(payload, expected, text)
        directory = os.path.dirname(out) or "."
        if not os.path.isdir(directory):
            raise Refusal("out-dir-missing")
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".design-map-", suffix=".html")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, out)
    except Refusal:
        remove_page(out)
        raise
    return dict(expected=expected, payload=count, rendered=rendered, page=out)


def check(positional, flags):
    if len(positional) < 2:
        raise Refusal("missing-page" if positional else "missing-map")
    map_path, page_path = positional[0], positional[1]
    expected = expectation(flags)
    payload, count = counted_payload(map_path, expected)
    try:
        with open(page_path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        raise Refusal("page-unreadable")
    rendered = check_page(payload, expected, text)
    return dict(expected=expected, payload=count, rendered=rendered)


VERBS = {"render": render, "check-page": check}


def main(argv):
    verb = argv[1] if len(argv) > 1 else ""
    try:
        if verb not in VERBS:
            raise Refusal("unknown-verb")
        positional, flags = parse_args(argv[2:])
        if verb == "check-page" and "out" in flags:
            raise Refusal("unknown-flag-out")
        attrs = VERBS[verb](positional, flags)
    except Refusal as r:
        return verdict("error", verb=verb or "none", reason=r.reason, **r.attrs)
    return verdict("ok", verb=verb, **attrs)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
