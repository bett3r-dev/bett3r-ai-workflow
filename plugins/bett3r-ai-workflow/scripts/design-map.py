#!/usr/bin/env python3
"""The map verbs over a design's map.json. It says what it did in ONE line.

    DESIGN-MAP:v1 outcome=ok verb=validate forks=<n>
    DESIGN-MAP:v1 outcome=ok verb=write forks=<n> map=<path>
    DESIGN-MAP:v1 outcome=ok verb=render expected=<n> payload=<n> rendered=<n> page=<path>
    DESIGN-MAP:v1 outcome=ok verb=render maps=<n> forks=<n> expected=<n> page=<path>   (--stack)
    DESIGN-MAP:v1 outcome=ok verb=apply-answers final=<bool> open=<n> owner=<n> recommendation=<n> code=<n> moot=<n> otherMap=<n> commented=<ids|none> map=<path>
    DESIGN-MAP:v1 outcome=ok verb=candidates forks=<n> candidates=<n> skipped-open=<n> skipped-moot=<n> skipped-nowalk=<n> skipped-untestable=<n>
    DESIGN-MAP:v1 outcome=ok verb=check-plan review=<human|unattended|none> candidates=<n> scenarios=<n> seams=<n>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=unattended-confirmed
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=candidate-in-oracle slice=<id>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=slice-unscened slice=<id>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=scenario-unstructured slice=<id> why=<w>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=plan-unseamed
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=seam-unstructured seam=<name|index> why=<w>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=slice-unseamed slice=<id>
    DESIGN-MAP:v1 outcome=fail verb=check-plan reason=unnamed-seam slice=<id> seam=<name>
    DESIGN-MAP:v1 outcome=ok verb=project ticket=<K> forks=<n> nodes=<n>
    DESIGN-MAP:v1 outcome=ok verb=decisions open=<n> owner=<n> recommendation=<n> code=<n> moot=<n>
    DESIGN-MAP:v1 outcome=ok verb=record forks=<n> payloads=<n> owner=<n> recommendation=<n> code=<n> unresolved=<n> nocard=<n> already=<n> sidecar=<path>
    DESIGN-MAP:v1 outcome=fail verb=decisions reason=open-forks open=<n> owner=<n> ...
    DESIGN-MAP:v1 outcome=ok verb=count forks=<n> owner=<n> code=<n> recommendation=<n> open=<n> moot=<n>
    DESIGN-MAP:v1 outcome=ok verb=count map=none                          (--line, no map file)
    DESIGN-MAP:v1 outcome=current verb=drift mapSeq=<n> feedSeq=<n>
    DESIGN-MAP:v1 outcome=drifted verb=drift mapSeq=<n|none> feedSeq=<n>
    DESIGN-MAP:v1 outcome=skip verb=drift mapSeq=<n|none> feedSeq=none reason=no-map-feed
    DESIGN-MAP:v1 outcome=ok verb=select target=<board|artifact|board-candidate> reason=<r> probe=<skipped|done>
    DESIGN-MAP:v1 outcome=error verb=<verb> reason=<reason> [key=value ...]

Read the line, never the exit code alone (ADR-004): 0 for ok, 1 for fail
(check-plan's two assertions and decisions --closed, below), 2 for error
(drift: 0 for current and skip, 1 for drifted), and no line at all means the
script died before concluding. An error line carries no `page=`: a caller
that publishes whatever `page=` names must find nothing.

Usage:

  design-map validate <map.json>
  design-map write <map.json>          (the map on stdin)
  design-map render <map.json> --expect <n> [--out <page.html>]
  design-map check-page <map.json> <page.html> --expect <n>
  design-map apply-answers <map.json> <answers-dir> [--final]
  design-map candidates <map.json>
  design-map check-plan <slices.yaml>
  design-map render --stack <m1> <m2>... --expect <n1> <n2>... --out <page.html>
  design-map project --ticket <K> <map.json>...   (the map, then the verdict, on stdout)
  design-map decisions <map.json> [--closed]
  design-map record <map.json>         (the payloads, then the verdict, on stdout)
  design-map count <map.json> [--lane <lane.yaml>] [--line]
  design-map drift <map.json> (--feed-seq <n> | --no-feed)
  design-map select --phase probe|start --captures <dir> [--map <map.json>] [--lane <lane.yaml>]

A map is `structureVersion: 2`. Two committed files describe it:

  skills/design-map/map.schema.json           the vocabulary: the closed sets
      (fork status kind, decided source, node level, map shape), a
      byte-identical copy of what esas emits
      (packages/esas-schema/schema/map.schema.json). Never hand-edited.
  skills/design-map/map-structure.schema.json the structure: nodes, forks,
      cards, options, links. It names every closed set by a `$ref` into
      map.schema.json, resolved from its own directory, so the values are
      read from the copy as data and restated nowhere.

A map in any other shape (a 161 `schemaVersion: 1` map included) is
reason=schema-invalid. After the schema, the checks JSON Schema cannot express:

  duplicate-node-id (id=)            two nodes share an id
  duplicate-fork-id (id=)            two forks share an id
  duplicate-option-id (id= option=)  one fork's card repeats an option id
  unknown-option (id= at=)           a decided status, or the card's
                                     recommendation, names no option of that card
  decided-title-only (id=)           a fork with no card is decided: there is
                                     no option for the status to name
  dangling-ref (id= at=)             an anchor or a parent names no node, a
                                     restsOn entry names no fork, or a link's
                                     deliverableId names no node

`validate` runs the bare-actor check (below), the schema and these checks,
and writes nothing; it accepts an ungrounded map.

`write` is the only structural authoring path. It reads a full map on stdin,
runs the same checks as `validate`, and replaces the target whole: a temporary
file in the target's directory, moved over it, in the formatting apply-answers
writes. It never merges with the file it replaces. Every refusal leaves the
target byte-identical, and an absent target is not created. Reasons:
missing-map (no target argument), map-dir-missing (the target's directory does
not exist), map-unparseable (stdin is not UTF-8 JSON), upstream-refused (stdin
ends in a verdict line other than project's ok one, below), map-unwritable, and the
validate reasons. `render` and `check-page` also refuse reason=not-grounded when
the map holds at least one fork and `grounded` is not true: an ungrounded
draft is never drawn for the owner to answer.

`render` validates the payload, then writes a self-contained HTML page with one
card per fork, drawn from its `card` (problem, use cases, options and their
walks, recommendation, what an overturn costs). A fork with no card is drawn by
its title alone, with nothing to pick, and still counts as drawn. A decided
fork carries a class naming its source, one style per value of the
vocabulary's decided source (owner, recommendation and code are three distinct
styles), and the page's legend shows each. The owner answers on it; each answer is written to the
artifact's `db` store as `answers/<forkId>` = `{pick, comment, updatedAt}`, the
shape of the ESAS-156 prototype's writer (esas `docs/prs/ESAS-156/map.html`,
`saveAnswer`), so answers saved there parse unchanged; when the map carries a
`mapId` the page also writes `map: <mapId>` into each answer. When `claude.use("db")`
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
  the post-schema reasons above, not-grounded, out-path-whitespace,
  out-dir-missing, out-is-map, missing-page, page-unreadable,
  and with --stack: missing-out, expect-count-mismatch, duplicate-fork-id

`apply-answers` folds the owner's saved answers into the map's fork statuses,
`{kind: open}`, `{kind: decided, source, option}` or `{kind: moot, reason}`,
and never deletes a fork. The answers dir
holds one file per saved answer, `<answers-dir>/<forkId>.json`, containing the
`answers/<forkId>` document as the page wrote it, `{pick, comment, updatedAt,
map?}` (dot-files are ignored; any other entry is reason=answer-unexpected-file).

  - an answer whose `map` is   -> skipped before any check (fork and pick are
    not the map's mapId          not looked at) and counted in otherMap=; on a
                                 map with no mapId, every answer naming a map is
                                 skipped. An answer with no `map` applies.
  - an answer with a pick     -> {kind: decided, source: owner, option: <pick>}
                                 — also over any earlier decision, code included
  - no answer                 -> status unchanged
  - a comment with no pick    -> status unchanged; the comment is printed as
                                 `comment <forkId>: <text>` before the verdict,
                                 and an open fork's id is listed in commented=
  - a moot fork               -> left exactly as it is, answer or not, even a
                                 pick naming no option (no refusal)
  - --final                   -> every fork with a card still open after the
                                 fold becomes {kind: decided, source:
                                 recommendation, option: card.recommendation.option};
                                 refused reason=title-only-open (id= the first)
                                 while any fork with no card is still open

Without --final no fork is ever made decided(recommendation): a fork the owner
has not reached yet must stay distinguishable from one they let stand.

The map is updated in place, and only whole: the folded payload is validated
against the schema, written to a temporary file beside the map and moved over
it. Every refusal leaves the author's map byte-identical. Reasons:

  missing-answers, answers-dir-missing, answer-unexpected-file (name=<entry>),
  answer-unreadable, answer-unparseable, answer-malformed (also a `map` that
  is not a string), unknown-fork, unknown-pick, fork-title-only (a pick on a
  fork with no card), title-only-open (each with id=<forkId>), map-unwritable,
  and the map reasons above

A bare `actor` key is refused anywhere in the payload, before the schema runs:
the map's who-level is `mapActor`, never `actor`, so a map role can never be
joined to an op's ActorId by accident.

`candidates` validates the map (the same refusals as `validate`), then reads
it, never writing anything. For each fork it prints zero or more compact JSON
lines, one per walk of the fork's status.option — never a rejected option's
walk, since a rejected option is a confidently-wrong oracle:

  {"fork": <id>, "option": <id>, "scenario": <text>, "source": <decided source>, "example": <walk text>}

in that fixed key order (documented here rather than sorted, so a reader can
diff two runs by eye). A fork is skipped and counted, never printed, when:

  skipped-open        status.kind is "open" (the owner has not reached it)
  skipped-moot         status.kind is "moot" (never named in the output)
  skipped-nowalk        always 0 — see the two refusals below. The key stays on
                        the verdict line because /plan parses that line, and its
                        zero is the proof the refusal fired rather than a fork
                        being quietly dropped from the census.
  skipped-untestable    the fork carries `testable: false` (a process-rule
                        card the design lane marks unoracled, ESAS-164)

Two refusals, both outcome=fail (exit 1 — a fixable map, not a broken tool),
because a walk IS the oracle a slice is built from and this verb is the last
moment it can be fixed cheaply:

  decided-nowalk        decided, and the chosen option carries no walk at all:
                        a choice somebody made that nobody can test
  walk-unstructured     decided, and a walk of the chosen option is prose —
                        no given/when/then, and not `kind: structural`.
                        Reported as walk=<index>, never the scenario text:
                        every attribute on a verdict line is space-free by
                        contract, and a refusal nobody can parse reads
                        downstream as no refusal at all.

A fork that is both decided with a zero-walk option AND `testable: false` is
counted only under skipped-untestable: untestable is checked first, so it
wins the tie (ESAS-165 D1/AC3 leaves the precedence to this build) — and it
short-circuits both refusals above for the same reason. A
card-less decided fork cannot reach `candidates` at all: `validate` already
refuses it as `decided-title-only`.

`check-plan` reads a `slices.yaml` (PyYAML, not committed elsewhere in this
script; `reason=yaml-unavailable` if the interpreter has no PyYAML installed,
never a silent pass) and makes two ADR-004 assertions about it, each an
`outcome=fail` (exit 1, distinct from `outcome=error`'s exit 2 — a plan that
parses but fails an assertion is not the same event as one this script could
not read):

  reason=unattended-confirmed   top-level `review: unattended` and any
                                 `candidateOracles[].status` is "confirmed"
                                 (ESAS-165 AC2: unattended /plan never
                                 confirms a candidate, so a confirmed one
                                 there means the file was hand-edited)
  reason=candidate-in-oracle    a non-confirmed candidate's example appears
                                 verbatim (as a substring) in a slice's
                                 `oracle:` string. A confirmed candidate's
                                 example there is the attended promotion
                                 (ESAS-165 D4) and passes. Empty examples
                                 never match; the offending slice's id is
                                 named as slice=, or slice=unknown when that
                                 slice carries no id)

and, over the slices themselves:

  reason=slice-unscened         a slice carries no `scenarios:` at all
  reason=scenario-unstructured  a scenario is not a Given/When/Then triple
                                 (`why=missing-<fields>`), or a
                                 `kind: structural` one carries GWT / no text
  reason=plan-unseamed          the plan declares no `seams:`
  reason=seam-unstructured      a declared seam has no `name`/`at`, repeats a
                                 name, has an unknown `kind`, or is a second
                                 (or `kind: new`) seam with no `why:`
  reason=slice-unseamed         a slice names no `seam:`
  reason=unnamed-seam           a slice's `seam:` is not one the plan declared
                                 — it tests somewhere nobody agreed to

The seam block is the unit's answer to "where do we test this", written once:
fewest, highest, existing over new. `at:` records where it is; `why:` is owed
by every seam after the first and by every new one, so adding a seam costs a
justification and the ideal number stays one.

else `outcome=ok review=<the top-level review, or "none"> candidates=<the
length of candidateOracles, 0 if the key is absent> scenarios=<n> seams=<n>`. Other reasons, all
`outcome=error`: `missing-plan` (no argument), `plan-unreadable` (the file
cannot be opened as UTF-8), `plan-unparseable` (invalid YAML, or the
document / its `candidateOracles` / its `slices` is not the shape this reads
as a mapping/list).

`render --stack` renders several maps onto one page (ESAS-166 D3). Each map is
validated and must be grounded, as for a single render, and a refusal about
one map gains map=<path>. `--expect` takes one value per map, in argument
order: a different count is reason=expect-count-mismatch, and one map's miss is
count-mismatch map=<path>. `--out` is required (reason=missing-out), and a
fork id in two maps is reason=duplicate-fork-id, since answers are keyed by
fork id. The page holds one <section data-map-id> per map, ordered by most
open forks first, then by the lowest ticket key over the map's forks'
tickets, compared by project and then by number as an integer (ESAS-9 before
ESAS-11; a map with no forks sorts last), then by argument order. The page
gate counts every fork of the stack exactly once, and a refusal removes an
earlier page at --out, as for a single render. The page's answer writer
stamps each answer with the mapId of the fork's own map.

`project --ticket K <map>...` (ESAS-166 D10) validates every input (refusals
name map=), then prints a v2 map on stdout: the forks whose tickets contain K,
in input order; the nodes their anchors name, with every ancestor reached
through parents; restsOn pruned to kept forks; the links whose deliverableId
is a kept node; mapId K; grounded and shape from the inputs
(grounded-mismatch, shape-mismatch when they disagree). A node id defined
differently in two inputs is node-conflict; a fork id in two inputs is
duplicate-fork-id. feedSeq and target are not carried over. Also
missing-ticket and malformed-ticket. The verdict follows the JSON as the last
stdout line (ADR-004). So `write` drops a last stdin line that is project's ok
verdict. When the last line is any other verdict, `write` refuses
reason=upstream-refused and leaves the target untouched. That way,
`project ... | write <target>` refuses a failed projection even in a shell
without pipefail.

`decisions <map>` (ESAS-166 D5) prints per-ticket Markdown. It has a
`## <ticket>` heading per ticket, ordered by ticket key, and one line per fork
carrying that ticket: `- <id> <title>: owner — <option> (<label>)`, `applied
on recommendation — ...`, `code — ...`, `moot — <reason>` or `open`. The
verdict counts each fork once. With --closed, open > 0 is outcome=fail
reason=open-forks (exit 1), printed after the Markdown.

`record <map>` (XL-70 F1) prints, before the verdict, the JSON array of
payloads for every fork the map says is answered — one object per fork with a
`decided` status, in map order, each carrying `forkKey` (the fork's own map id,
which is the join key), `question` (its title), `options` (every option label),
`chosen` (the map's `status.option`, the id and not the label), `chosenLabel`,
`rationale` (the card's `recommendation.why`), `source` and `tickets`. It is
pure over files, like `apply-answers`: no network call, no subprocess, no tool
of its own. Whoever hands the payload to a recorder is the caller; this verb
only derives what would be said, which is what makes the whole derivation
testable with nothing reachable.

An `open` or `moot` fork is `unresolved=` and gets no payload — nothing has been
answered to record. A decided fork with no card is `nocard=` and gets none
either: its options and rationale live on the card, and a payload missing them
is not a smaller payload but a different claim.

The `sidecar=` the verdict names is where the id a recorder hands back is
written: `<map path without its .json>.resolved-by.json`, beside the map, a
JSON object keyed by fork id. Beside rather than inside because the fork object
is closed (`additionalProperties: false`), as is every `status` branch, and the
status kind refs the byte-identical copy of what esas emits, so the id would be
a cross-repo vocabulary change and not a field addition; named after its own map rather than a flat
`resolved-by.json` because a run dir holds one map per subject in a single
directory. That file is the id's ONE home: it is never written into the map.
`record` READS it and writes nothing — a fork whose id it already carries is
`already=` and is not offered a second time, so re-running the step after two
more answers cannot post the earlier ones twice. A sidecar that does not parse
is `reason=sidecar-unparseable`, never an empty start, which would re-offer
every answer in the map.

`count <map>` (ESAS-162 D4) counts the forks by status as `decisions` does,
and validates the map first. With --line it prints, before the verdict, the
one line a PR body carries: `N of M forks answered by the owner (C by code, R
on recommendation, O open, K moot)`; a missing map file prints `map: none`
(verdict map=none, still ok). With --lane, a brief holding a line-anchored
`mapProvenance: lost` prints `map: owner answers not carried: run dir absent`
instead, whether or not the file exists. Without --line, a missing map is
reason=map-not-found.

`drift <map> (--feed-seq <n> | --no-feed)` (ESAS-162 D5) compares the map
file's own `feedSeq` (verdict mapSeq=, `none` when absent) with the seq the
caller read from the map feed (verdict feedSeq=): equal is outcome=current,
anything else (a map with no feedSeq included) outcome=drifted; --no-feed is
outcome=skip reason=no-map-feed. The map is validated first. Refusals:
missing-feed (neither flag), conflicting-feed (both), bad-feed-seq (not a
non-negative integer).

Standard library only for every map verb: `jsonschema` is not a dependency
(`check-plan` is the one exception, since a `slices.yaml` is YAML, not JSON,
and PyYAML is imported lazily inside it so its absence never breaks any
other verb — see `reason=yaml-unavailable` above). The validator below
implements exactly the keywords the structure schema uses (listed in its
`$comment`), and meeting any other keyword is reason=schema-unreadable rather
than a keyword silently ignored. So is a `$ref` that resolves nowhere — a
missing or unparseable map.schema.json, or a pointer naming no definition —
since a ref skipped silently would leave its enum unchecked while every valid
map still passed.
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
# The structure schema; the vocabulary copy it $refs sits beside it.
STRUCTURE_PATH = os.path.join(SCRIPT_DIR, "..", "skills", "design-map", "map-structure.schema.json")
VOCABULARY_FILE = "map.schema.json"


class Refusal(Exception):
    """outcome defaults to "error" (exit 2): a verb call itself did not
    conclude. check-plan also raises this with outcome="fail" (exit 1) for
    the two ADR-004 assertions it makes about an otherwise-parseable plan
    (ADR-004: the line is the contract, not the bare exit code, but the two
    outcomes still need two different codes for a shell caller)."""

    def __init__(self, reason, outcome="error", **attrs):
        super().__init__(reason)
        self.reason = reason
        self.outcome = outcome
        self.attrs = attrs


EXIT_CODES = {"ok": 0, "fail": 1, "current": 0, "skip": 0, "drifted": 1}


def verdict(outcome, **attrs):
    parts = [TOKEN, f"outcome={outcome}"]
    parts += [f"{key}={val}" for key, val in attrs.items()]
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return EXIT_CODES.get(outcome, 2)


BOOLEAN_FLAGS = ("final", "stack", "closed", "line", "no-feed")
VALUE_FLAGS = ("expect", "out", "ticket", "lane", "feed-seq", "phase", "captures", "map", "readback")


def parse_args(args):
    """With `--stack` anywhere in the arguments, `--expect` takes every value up
    to the next `--` flag (one per map); otherwise it takes exactly one."""
    positional, flags, i = [], {}, 0
    stack = "--stack" in args
    while i < len(args):
        a = args[i]
        if a.startswith("--") and a[2:] in BOOLEAN_FLAGS:
            flags[a[2:]] = True
            i += 1
        elif a.startswith("--"):
            name = a[2:]
            if name not in VALUE_FLAGS:
                raise Refusal(f"unknown-flag-{name}")
            if i + 1 >= len(args):
                raise Refusal(f"missing-{name}")
            if name == "expect" and stack:
                values = []
                i += 1
                while i < len(args) and not args[i].startswith("--"):
                    values.append(args[i])
                    i += 1
                flags[name] = values
                continue
            flags[name] = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1
    return positional, flags


# --- validation -------------------------------------------------------------

KEYWORDS = {
    "$schema", "$id", "$comment", "$defs", "title", "description", "type",
    "const", "enum", "required", "properties", "additionalProperties", "items",
    "minItems", "minLength", "minimum", "pattern", "$ref", "allOf", "oneOf",
    "if", "then",
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


def read_schema(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError):
        raise Refusal("schema-unreadable")
    if not isinstance(doc, dict):
        raise Refusal("schema-unreadable")
    return doc


class Validator:
    """JSON Schema over the keywords in KEYWORDS. A `$ref` is `#<pointer>` into
    the document it appears in, or `<file>#<pointer>` into a schema file in the
    same directory as that document; both must resolve."""

    def __init__(self, path):
        self.docs = {}
        self.root = self.document(path)

    def document(self, path):
        path = os.path.abspath(path)
        if path not in self.docs:
            self.docs[path] = read_schema(path)
        return path

    def resolve(self, ref, base):
        """(subschema, path of the document it lives in)."""
        name, hash_, frag = ref.partition("#")
        if not hash_ or (frag and not frag.startswith("/")) or os.path.basename(name) != name:
            raise Refusal("schema-unreadable", detail="unsupported-ref")
        doc = self.document(os.path.join(os.path.dirname(base), name)) if name else base
        node = self.docs[doc]
        for token in frag.split("/")[1:]:
            token = token.replace("~1", "/").replace("~0", "~")
            if not isinstance(node, dict) or token not in node:
                raise Refusal("schema-unreadable", detail="unresolvable-ref")
            node = node[token]
        if not isinstance(node, dict):
            raise Refusal("schema-unreadable", detail="unresolvable-ref")
        return node, doc

    def check(self, value):
        return self.errors(self.docs[self.root], value, (), self.root)

    def errors(self, schema, value, path, base):
        """The first violation as (path, keyword), or None."""
        unknown = set(schema) - KEYWORDS
        if unknown:
            raise Refusal("schema-unreadable", detail=f"unsupported-keyword-{sorted(unknown)[0]}")
        if "$ref" in schema:
            target, doc = self.resolve(schema["$ref"], base)
            found = self.errors(target, value, path, doc)
            if found:
                return found
        if "type" in schema and not TYPES[schema["type"]](value):
            return path, "type"
        if "const" in schema and not same(value, schema["const"]):
            return path, "const"
        if "enum" in schema and not any(same(value, e) for e in schema["enum"]):
            return path, "enum"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if "minimum" in schema and value < schema["minimum"]:
                return path, "minimum"
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
                    found = self.errors(schema["items"], item, path + (i,), base)
                    if found:
                        return found
        if isinstance(value, dict):
            for key in schema.get("required", []):
                if key not in value:
                    return path + (key,), "required"
            props = schema.get("properties", {})
            for key, child in value.items():
                if key in props:
                    found = self.errors(props[key], child, path + (key,), base)
                    if found:
                        return found
                elif schema.get("additionalProperties", True) is False:
                    return path + (key,), "additionalProperties"
        for sub in schema.get("allOf", []):
            found = self.errors(sub, value, path, base)
            if found:
                return found
        if "oneOf" in schema:
            results = [(sub, self.errors(sub, value, path, base)) for sub in schema["oneOf"]]
            matched = [sub for sub, found in results if found is None]
            if len(matched) != 1:
                # With no branch matching, the one branch whose `const`
                # properties the value carries is the one it meant: report its
                # violation rather than the bare oneOf.
                meant = [found for sub, found in results if found and discriminated(sub, value)]
                return meant[0] if not matched and len(meant) == 1 else (path, "oneOf")
        if "if" in schema and self.errors(schema["if"], value, path, base) is None:
            found = self.errors(schema.get("then", {}), value, path, base)
            if found:
                return found
        return None


def discriminated(schema, value):
    consts = {k: c["const"] for k, c in schema.get("properties", {}).items() if isinstance(c, dict) and "const" in c}
    return bool(consts) and isinstance(value, dict) and all(k in value and same(value[k], c) for k, c in consts.items())


def vocabulary():
    """The vocabulary copy's `$defs`, read as data."""
    doc = read_schema(os.path.join(os.path.dirname(STRUCTURE_PATH), VOCABULARY_FILE))
    defs = doc.get("$defs")
    if not isinstance(defs, dict):
        raise Refusal("schema-unreadable")
    return defs


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


def unique(ids, reason, **attrs):
    seen = set()
    for i in ids:
        if i in seen:
            raise Refusal(reason, id=i, **attrs)
        seen.add(i)
    return seen


def check_semantics(payload):
    """What the structure schema cannot say; runs only on a schema-valid map."""
    nodes = unique([n["id"] for n in payload["nodes"]], "duplicate-node-id")
    forks = unique([f["id"] for f in payload["forks"]], "duplicate-fork-id")
    for i, fork in enumerate(payload["forks"]):
        fid, status, card = fork["id"], fork["status"], fork.get("card")
        options = set()
        if card is not None:
            for option in card["options"]:
                if option["id"] in options:
                    raise Refusal("duplicate-option-id", id=fid, option=option["id"])
                options.add(option["id"])
            if card["recommendation"]["option"] not in options:
                raise Refusal("unknown-option", id=fid, at=pointer(("forks", i, "card", "recommendation", "option")))
            for j, option in enumerate(card["options"]):
                for k, walk in enumerate(option["walks"]):
                    at = ("forks", i, "card", "options", j, "walks", k)
                    gwt = [f for f in ("given", "when", "then") if f in walk]
                    # Partial is the shape to refuse loudest. A walk carrying a
                    # `given` and a `when` and no `then` reads, at a glance and
                    # in the rendered card, exactly like one structured on
                    # purpose — and it is the half-written one, which is how an
                    # oracle ends up asserting a setup rather than an outcome.
                    if gwt and len(gwt) != 3:
                        raise Refusal("walk-partial-gwt", id=fid, option=option["id"],
                                      at=pointer(at), have=",".join(sorted(gwt)))
                    # A structural walk asserts a census over source ("every X
                    # does Y, and nothing outside Z does Y"). Given/When/Then
                    # has no room for the negative half, so carrying both means
                    # one of the two is decoration and nobody can tell which.
                    if walk.get("kind") == "structural" and gwt:
                        raise Refusal("walk-structural-gwt", id=fid, option=option["id"],
                                      at=pointer(at))
        if "option" in status:
            if card is None:
                raise Refusal("decided-title-only", id=fid)
            if status["option"] not in options:
                raise Refusal("unknown-option", id=fid, at=pointer(("forks", i, "status", "option")))
    refs = []
    for i, node in enumerate(payload["nodes"]):
        refs += [(p, nodes, ("nodes", i, "parents", j)) for j, p in enumerate(node["parents"])]
    for i, fork in enumerate(payload["forks"]):
        if "anchor" in fork:
            refs.append((fork["anchor"], nodes, ("forks", i, "anchor")))
        refs += [(r, forks, ("forks", i, "restsOn", j)) for j, r in enumerate(fork["restsOn"])]
    for i, link in enumerate(payload.get("links", [])):
        refs.append((link["deliverableId"], nodes, ("links", i, "deliverableId")))
    for ref, known, at in refs:
        if ref not in known:
            raise Refusal("dangling-ref", id=ref, at=pointer(at))


def validate(payload):
    at = find_bare_actor(payload)
    if at:
        raise Refusal("bare-actor", at=pointer(at))
    found = Validator(STRUCTURE_PATH).check(payload)
    if found:
        path, rule = found
        raise Refusal("schema-invalid", at=pointer(path), rule=rule)
    check_semantics(payload)


def require_grounded(payload):
    if payload["forks"] and payload["grounded"] is not True:
        raise Refusal("not-grounded")


# --- the page ---------------------------------------------------------------

STYLE = """
body{font:15px/1.5 system-ui,sans-serif;margin:0;background:#f6f5f2;color:#1d1d1b}
header{padding:20px 28px;border-bottom:1px solid #ddd;background:#fff}
h1{margin:0 0 4px;font-size:20px} #dbnote{color:#555;font-size:13px}
.levels{padding:12px 28px;font-size:13px;color:#444} .levels b{color:#1d1d1b}
main{padding:12px 28px 40px;display:grid;gap:14px;max-width:960px}
.fork{background:#fff;border:1px solid #ddd;border-left:5px solid #c9c9c9;border-radius:8px;padding:14px 18px}
.fork.open{border-left-color:#d4553b} .fork.done{border-left-color:#2f8f5b}
.fork.moot{opacity:.6} .fork.titleonly h3{color:#666} .locked{font-size:13px;color:#666}
.legend{padding:8px 28px;font-size:12px;color:#444;display:flex;gap:10px;flex-wrap:wrap}
.legend span{border-left:5px solid #c9c9c9;padding:0 6px;background:#fff}
.walks{margin:4px 0 2px 18px;font-size:13px;color:#333} .note{font-size:13px;color:#555;margin:2px 0}
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
const DATA = JSON.parse(document.getElementById("map-data").textContent);
// A stacked page embeds {stack: [map, ...]}; each fork remembers its own map's id.
const MAPS = DATA.stack || [DATA];
// Each fork's own map's id, computed at render time (fork_maps); a fork of a map
// without mapId is absent, so its answers carry no map.
const FORK_MAP = JSON.parse(document.getElementById("fork-maps").textContent);
const FORKS = {};
MAPS.forEach(m => m.forks.forEach(f => { FORKS[f.id] = f; }));
let db = null;
let answers = {};

function stateOf(id) {
  const f = FORKS[id];
  if (f.status.kind === "moot") return "moot";
  if (answers[id] && answers[id].pick) return "done";
  return f.status.kind === "decided" ? "decided " + f.status.source : "open";
}
function recKey(f) {
  return f.card ? f.card.recommendation.option : null;
}
function renderCard(id) {
  const card = document.querySelector('[data-fork-id="' + id + '"]');
  const a = answers[id] || null;
  card.className = "fork " + stateOf(id) + (FORKS[id].card ? "" : " titleonly");
  if (!FORKS[id].card) return;
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
  card.querySelectorAll("button, textarea").forEach(el => { el.disabled = !db || FORKS[id].status.kind === "moot"; });
}
function renderAll() { Object.keys(FORKS).forEach(renderCard); }

async function saveAnswer(id, patch) {
  if (!db) return;
  const prev = answers[id] || {};
  const doc = { pick: prev.pick || null, comment: prev.comment || "", ...patch, updatedAt: new Date().toISOString() };
  if (FORK_MAP[id]) doc.map = FORK_MAP[id];
  answers[id] = doc; renderCard(id);
  const s = document.querySelector('[data-fork-id="' + id + '"] .saved');
  try { await db.doc("answers/" + id).set(doc); s.textContent = "Saved"; }
  catch (e) { s.textContent = "Not saved: " + (e && e.message || "store refused the write"); }
}

document.addEventListener("click", e => {
  const card = e.target.closest("[data-fork-id]");
  if (!card || !FORKS[card.dataset.forkId].card) return;
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


# One border colour per decided source, assigned in the vocabulary's order; the
# source values themselves are read from map.schema.json, never listed here.
SOURCE_COLOURS = ["#d49a1f", "#3b6fd4", "#7a4fc9", "#1f9aa3", "#9a6b3b"]


def source_styles(vocab):
    sources = vocab["decidedSource"]["enum"]
    if len(sources) > len(SOURCE_COLOURS):
        raise Refusal("schema-unreadable", detail="too-many-decided-sources")
    return list(zip(sources, SOURCE_COLOURS))


def status_class(fork):
    status = fork["status"]
    kind = status["kind"]
    cls = f"fork {kind} {status['source']}" if kind == "decided" else f"fork {kind}"
    return cls if "card" in fork else cls + " titleonly"


def items(texts, cls=None):
    if not texts:
        return ""
    attr = f' class="{cls}"' if cls else ""
    return f"<ul{attr}>" + "".join(f"<li>{t}</li>" for t in texts) + "</ul>"


def option_block(option, recommended):
    oid = option["id"]
    rec = option["id"] == recommended
    walks = items([f"<i>{esc(w['scenario'])}</i> &mdash; {esc(w['text'])}" for w in option["walks"]], "walks")
    extra = ""
    if "rejectedBecause" in option:
        extra += f'<p class="note">Rejected because {esc(option["rejectedBecause"])}</p>'
    if option.get("evidence"):
        extra += f'<p class="note">Evidence: {esc("; ".join(option["evidence"]))}</p>'
    return (
        f'<div class="opt{" rec" if rec else ""}"><div><b>{esc(oid)}</b> {esc(option["label"])}'
        f'{"<span class=badge>recommended</span>" if rec else ""}{walks}{extra}</div>'
        f'<button class="btn" data-pick="{esc(oid)}" disabled>Choose</button></div>'
    )


def fork_card(fork, node_titles):
    fid = fork["id"]
    eyebrow = esc(fid) + " &middot; " + esc(", ".join(fork["tickets"]))
    if fork.get("anchor") in node_titles:
        eyebrow += f" &middot; {esc(node_titles[fork['anchor']])}"
    status = fork["status"]
    if "source" in status:
        eyebrow += f" &middot; decided ({esc(status['source'])}): {esc(status['option'])}"
    elif "reason" in status:
        eyebrow += f" &middot; moot: {esc(status['reason'])}"
    if fork["restsOn"]:
        eyebrow += " &middot; rests on " + esc(", ".join(fork["restsOn"]))
    head = (
        f'<article class="{status_class(fork)}" data-fork-id="{esc(fid)}">'
        f'<div class="eyebrow">{eyebrow}</div><h3>{esc(fork["title"])}</h3>'
    )
    card = fork.get("card")
    if card is None:
        return head + '<p class="locked">No card yet: this fork is drawn by its title until it unlocks.</p></article>'
    recommended = card["recommendation"]["option"]
    options = "".join(option_block(o, recommended) for o in card["options"])
    return (
        f'{head}<p>{esc(card["problem"])}</p>'
        f'{items([esc(u) for u in card["useCases"]])}{options}'
        f'<p><b>Recommendation.</b> {esc(recommended)}: {esc(card["recommendation"]["why"])}</p>'
        f'<p class="note"><b>If overturned.</b> {esc(card["ifOverturned"])}</p>'
        f'<textarea placeholder="Anything the options miss, or a question for me" disabled></textarea>'
        f'<div><button class="btn" data-action="save" disabled>Save comment</button> '
        f'<button class="btn" data-action="agree" disabled>Agree with the recommendation</button>'
        f'<span class="saved"></span></div></article>'
    )


def levels(payload, vocab):
    """The nodes, one row per level in the vocabulary's order; struck nodes struck through."""
    rows = []
    for level in vocab["mapNodeLevel"]["enum"]:
        names = [
            f'<s title="struck: {esc(n["struck"]["reason"])}">{esc(n["title"])}</s>' if "struck" in n else esc(n["title"])
            for n in payload["nodes"] if n["level"] == level
        ]
        if names:
            rows.append(f"<b>{esc(level)}</b> {', '.join(names)}")
    return f'<div class="levels">{" &middot; ".join(rows)}</div>' if rows else ""


def legend(styles):
    return '<div class="legend">' + "".join(
        f'<span class="{esc(source)}">decided: {esc(source)}</span>' for source, _ in styles
    ) + "</div>"


def cards_of(payload):
    node_titles = {n["id"]: n["title"] for n in payload["nodes"]}
    return "".join(fork_card(f, node_titles) for f in payload["forks"])


def fork_maps(payloads):
    """Fork id -> the mapId of the fork's own map, for the page's answer writer
    (ESAS-166 D5.1: a stacked page never cross-binds answers). Forks of a map
    without mapId are left out."""
    return {f["id"]: p["mapId"] for p in payloads if p.get("mapId") for f in p["forks"]}


def page(payload, stack=None):
    """One map's page, or with `stack` (the ordered payloads) one page holding a
    <section data-map-id> per map, each with its own levels and cards."""
    vocab = vocabulary()
    styles = source_styles(vocab)
    style = STYLE + "".join(
        f".fork.{source}{{border-left-color:{colour}}} .legend .{source}{{border-left-color:{colour}}}\n"
        for source, colour in styles
    ) + ("section.map{display:grid;gap:14px} section.map h2{margin:12px 0 0;font-size:17px}\n" if stack else "")
    if stack is None:
        title = payload.get("mapId") or "Design map"
        body = f"{levels(payload, vocab)}{legend(styles)}<main>{cards_of(payload)}</main>"
        embedded = payload
    else:
        title = "Design maps"
        sections = "".join(
            f'<section class="map" data-map-id="{esc(p.get("mapId", ""))}">'
            f'<h2>{esc(p.get("mapId") or "Design map")}</h2>{levels(p, vocab)}{cards_of(p)}</section>'
            for p in stack
        )
        body = f"{legend(styles)}<main>{sections}</main>"
        embedded = {"stack": stack}
    # `<` escaped so no string in the payload can close the data script early.
    data = json.dumps(embedded, ensure_ascii=False).replace("<", "\\u003c")
    fork_map = json.dumps(fork_maps(stack if stack is not None else [payload]), ensure_ascii=False).replace("<", "\\u003c")
    return (
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        f"{GENERATOR}"
        f"<title>{esc(title)}</title><style>{style}</style></head><body>"
        f"<header><h1>{esc(title)}</h1>"
        "<div>A fork you leave unanswered is taken on its recommendation.</div>"
        "<div id=\"dbnote\">Connecting to the answer store&hellip;</div></header>"
        f"{body}"
        f"<script type=\"application/json\" id=\"map-data\">{data}</script>"
        f"<script type=\"application/json\" id=\"fork-maps\">{fork_map}</script>"
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


def check_page(payload, expected, text, forks=None):
    """The page gate: every payload fork drawn exactly once, or a refusal.
    `forks` (a stack's fork ids across every map) replaces the payload's own."""
    drawn = drawn_forks(text)
    wanted = [f["id"] for f in payload["forks"]] if forks is None else forks
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
    require_grounded(payload)
    count = len(payload["forks"])
    if count != expected:
        raise Refusal("count-mismatch", expected=expected, payload=count)
    return payload, count


def naming_map(path, fn, *args):
    """Run fn; a refusal it raises gains map=<path>, so a caller handed several
    maps knows which one was refused."""
    try:
        return fn(*args)
    except Refusal as r:
        r.attrs.setdefault("map", path)
        raise


TICKET = re.compile(r"([A-Z][A-Z0-9]*)-([0-9]+)\Z")


def ticket_key(ticket):
    """A ticket id compared by project, then by number as an integer, so ESAS-9
    sorts before ESAS-11. The schema's ticket pattern guarantees the match."""
    project, number = TICKET.match(ticket).groups()
    return project, int(number)


def stack_order(entries):
    """(index, payload) pairs in page order: most open forks first, then the
    lowest ticket key over all of a map's forks' tickets (a map with no forks
    sorts after every map that has one), then argument order."""
    def key(entry):
        index, payload = entry
        opened = sum(1 for f in payload["forks"] if f["status"]["kind"] == "open")
        tickets = [ticket_key(t) for f in payload["forks"] for t in f["tickets"]]
        lowest = (0, min(tickets)) if tickets else (1, ("", 0))
        return (-opened, lowest, index)
    return sorted(entries, key=key)


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


def render_stack(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    if "out" not in flags:
        raise Refusal("missing-out")
    out = flags["out"]
    try:
        expects = flags.get("expect")
        if not expects:
            raise Refusal("missing-expect")
        if len(expects) != len(positional):
            raise Refusal("expect-count-mismatch", maps=len(positional), expects=len(expects))
        if any(not re.fullmatch(r"[0-9]+", e) for e in expects):
            raise Refusal("malformed-expect")
        if re.search(r"\s", out):
            raise Refusal("out-path-whitespace")
        seen = set()
        entries = []
        for index, (map_path, expected) in enumerate(zip(positional, expects)):
            if same_file(out, map_path):
                raise Refusal("out-is-map", map=map_path)
            payload, _ = naming_map(map_path, counted_payload, map_path, int(expected))
            for fork in payload["forks"]:
                if fork["id"] in seen:
                    raise Refusal("duplicate-fork-id", id=fork["id"], map=map_path)
                seen.add(fork["id"])
            entries.append((index, payload))
        ordered = [payload for _, payload in stack_order(entries)]
        forks = [f["id"] for p in ordered for f in p["forks"]]
        expected = sum(int(e) for e in expects)
        text = page(None, stack=ordered)
        check_page({"forks": []}, expected, text, forks=forks)
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
    return dict(maps=len(ordered), forks=len(forks), expected=expected, page=out)


def render(positional, flags):
    if flags.get("stack"):
        return render_stack(positional, flags)
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


# --- answers ----------------------------------------------------------------

ANSWER_FILE = re.compile(r"([A-Za-z0-9_-]+)\.json\Z")


def load_answers(directory):
    """{forkId: {pick, comment}} from <directory>/<forkId>.json."""
    if not os.path.isdir(directory):
        raise Refusal("answers-dir-missing")
    answers = {}
    for name in sorted(os.listdir(directory)):
        if name.startswith("."):
            continue
        match = ANSWER_FILE.fullmatch(name)
        if not match or not os.path.isfile(os.path.join(directory, name)):
            raise Refusal("answer-unexpected-file", name=re.sub(r"\s", "?", name))
        fid = match.group(1)
        try:
            with open(os.path.join(directory, name), encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            raise Refusal("answer-unreadable", id=fid)
        try:
            doc = json.loads(text)
        except ValueError:
            raise Refusal("answer-unparseable", id=fid)
        pick = doc.get("pick") if isinstance(doc, dict) else None
        comment = doc.get("comment") if isinstance(doc, dict) else None
        owner_map = doc.get("map") if isinstance(doc, dict) else None
        if not isinstance(doc, dict) or not isinstance(pick, (str, type(None))) \
                or not isinstance(comment, (str, type(None))) \
                or ("map" in doc and not isinstance(owner_map, str)):
            raise Refusal("answer-malformed", id=fid)
        answers[fid] = {"pick": pick or None, "comment": (comment or "").strip(), "map": owner_map}
    return answers


def fold(payload, answers, final):
    """Apply answers (and --final) to the forks in place.

    Returns (comments, commented, other_map). An answer naming a map other than
    this map's mapId is skipped before any check and only counted.
    """
    forks = {f["id"]: f for f in payload["forks"]}
    map_id = payload.get("mapId")
    other_map = sum(1 for a in answers.values() if a["map"] is not None and a["map"] != map_id)
    answers = {fid: a for fid, a in answers.items() if a["map"] is None or a["map"] == map_id}
    for fid, answer in answers.items():
        if fid not in forks:
            raise Refusal("unknown-fork", id=fid)
        fork, pick = forks[fid], answer["pick"]
        if fork["status"]["kind"] == "moot" or pick is None:
            continue
        if "card" not in fork:
            raise Refusal("fork-title-only", id=fid)
        if pick not in [o["id"] for o in fork["card"]["options"]]:
            raise Refusal("unknown-pick", id=fid)
    comments = []
    for fork in payload["forks"]:
        answer = answers.get(fork["id"])
        if fork["status"]["kind"] == "moot" or answer is None:
            continue
        if answer["pick"] is not None:
            # The status is replaced whole, so any sibling key on it is dropped
            # here unless it is carried across deliberately. `resolvedBy` — the
            # citation for what settled the fork — survives only where the owner
            # CONFIRMS the option that was already decided: an owner who picks a
            # different option has overturned whatever settled it, and keeping
            # the citation would credit a source that never said this.
            prior = fork["status"]
            status = {"kind": "decided", "source": "owner", "option": answer["pick"]}
            if prior.get("option") == answer["pick"] and "resolvedBy" in prior:
                status["resolvedBy"] = prior["resolvedBy"]
            fork["status"] = status
        if answer["comment"]:
            comments.append((fork, answer["comment"]))
    commented = [f["id"] for f, _ in comments if f["status"]["kind"] == "open"]
    if final:
        for fork in payload["forks"]:
            if fork["status"]["kind"] == "open" and "card" not in fork:
                raise Refusal("title-only-open", id=fork["id"])
        for fork in payload["forks"]:
            if fork["status"]["kind"] == "open":
                fork["status"] = {
                    "kind": "decided", "source": "recommendation",
                    "option": fork["card"]["recommendation"]["option"],
                }
    return comments, commented, other_map


def write_map(path, payload):
    """Replace `path` whole with the payload in the one canonical formatting:
    a temporary file beside it, moved over it, so a reader never sees half a map."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".design-map-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)
    except OSError:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise Refusal("map-unwritable")


def apply_answers(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    if len(positional) < 2:
        raise Refusal("missing-answers")
    map_path, answers_dir = positional[0], positional[1]
    final = flags.get("final", False)
    payload = load_map(map_path)
    validate(payload)
    comments, commented, other_map = fold(payload, load_answers(answers_dir), final)
    validate(payload)
    write_map(map_path, payload)
    for fork, comment in comments:
        sys.stdout.write(f"comment {fork['id']}: {comment.replace(chr(10), ' / ')}\n")
    def count(kind, source=None):
        return sum(1 for f in payload["forks"]
                   if f["status"]["kind"] == kind and (source is None or f["status"].get("source") == source))
    return dict(
        final="true" if final else "false", open=count("open"), owner=count("decided", "owner"),
        recommendation=count("decided", "recommendation"), code=count("decided", "code"),
        moot=count("moot"), otherMap=other_map, commented=",".join(commented) or "none", map=map_path,
    )


def validate_map(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    payload = load_map(positional[0])
    validate(payload)
    return dict(forks=len(payload["forks"]))


# --- candidates / check-plan (ESAS-165 D1-D3, AC2, AC3) ----------------------

def fork_candidates(fork):
    """The candidate lines a decided fork offers, and which counter (if any)
    it is skipped under. testable:false wins over zero-walk when both hold
    (documented precedence; ESAS-165 leaves the tie loose)."""
    status = fork["status"]
    if status["kind"] == "open":
        return [], "open"
    if status["kind"] == "moot":
        return [], "moot"
    # decided: validate() already refused a card-less decided fork
    # (decided-title-only), so fork["card"] is always present here.
    if fork.get("testable") is False:
        return [], "untestable"
    option = next(o for o in fork["card"]["options"] if o["id"] == status["option"])
    if not option["walks"]:
        # Was a silent counter. A decided fork is a choice somebody made, and a
        # choice with no walk is a choice nobody can test — the slice built from
        # it gets an oracle invented downstream from prose, which is the single
        # largest measured cause of rework. Refusing here is the whole point of
        # the verb: it is the last moment the map can still be fixed cheaply.
        raise Refusal("decided-nowalk", outcome="fail", id=fork["id"], option=status["option"])
    lines = []
    for index, walk in enumerate(option["walks"]):
        if walk.get("kind") != "structural" and not all(f in walk for f in ("given", "when", "then")):
            # check_semantics already refused a PARTIAL triple, so this walk
            # carries none of it: prose, the form an executor reads and writes
            # its own rule from. It may be perfectly good prose. It is refused
            # anyway, because "good enough to read" is exactly the judgement
            # that produced 41% oracle-wrong, and the fix is two minutes in the
            # map against a fresh executor context downstream.
            #
            # `walk=<index>`, never the scenario text: every attribute on a
            # verdict line is space-free by contract (the oracle's own matcher
            # is `( [A-Za-z_-]+=[^ ]*)*$`, and /plan reads the line the same
            # way), so free text here would not merely look untidy — it makes
            # the whole line unparseable, and a refusal nobody can parse reads
            # downstream as no refusal at all.
            raise Refusal("walk-unstructured", outcome="fail", id=fork["id"],
                          option=status["option"], walk=index)
        lines.append(
            {"fork": fork["id"], "option": status["option"], "scenario": walk["scenario"],
             "source": status["source"], "example": walk["text"]})
    return lines, None


def candidates(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    payload = load_map(positional[0])
    validate(payload)
    skipped = {"open": 0, "moot": 0, "nowalk": 0, "untestable": 0}
    total = 0
    for fork in payload["forks"]:
        lines, skip = fork_candidates(fork)
        if skip:
            skipped[skip] += 1
            continue
        for line in lines:
            # Fixed key order (documented in the module header), not sorted:
            # fork, option, scenario, source, example.
            sys.stdout.write(json.dumps(line, ensure_ascii=False, sort_keys=False,
                                         separators=(",", ":")) + "\n")
            total += 1
    return dict(forks=len(payload["forks"]), candidates=total,
                **{f"skipped-{k}": v for k, v in skipped.items()})


def check_plan(positional, flags):
    if not positional:
        raise Refusal("missing-plan")
    try:
        import yaml
    except ImportError:
        raise Refusal("yaml-unavailable")
    path = positional[0]
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        raise Refusal("plan-unreadable")
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError:
        raise Refusal("plan-unparseable")
    if not isinstance(doc, dict):
        raise Refusal("plan-unparseable")
    review = doc.get("review")
    raw_candidates = doc.get("candidateOracles") or []
    if not isinstance(raw_candidates, list):
        raise Refusal("plan-unparseable")
    if review == "unattended" and any(
            isinstance(c, dict) and c.get("status") == "confirmed" for c in raw_candidates):
        raise Refusal("unattended-confirmed", outcome="fail")
    # A confirmed candidate's example in an oracle is the attended promotion
    # itself (ESAS-165 D4: "that copy is the promotion"), so only
    # non-confirmed candidates are checked. Unattended confirmed ones were
    # already refused above.
    examples = [c["example"] for c in raw_candidates
                if isinstance(c, dict) and c.get("status") != "confirmed"
                and isinstance(c.get("example"), str) and c["example"]]
    raw_slices = doc.get("slices") or []
    if not isinstance(raw_slices, list):
        raise Refusal("plan-unparseable")
    for sl in raw_slices:
        if not isinstance(sl, dict):
            continue
        # `scenarios:` is searched alongside `oracle:`, not instead of it. The
        # ESAS-165 contract is about a candidate reaching the executor without a
        # human, and a Given/When/Then triple reaches it harder than the prose
        # ever did — so introducing the field without this loop would have left
        # a rename as the whole of the bypass.
        haystacks = [sl.get("oracle")]
        for sc in sl.get("scenarios") or []:
            if isinstance(sc, dict):
                haystacks += [sc.get(f) for f in ("scenario", "text", "given", "when", "then")]
        for haystack in haystacks:
            if not isinstance(haystack, str):
                continue
            for example in examples:
                if example in haystack:
                    slice_id = sl.get("id")
                    raise Refusal("candidate-in-oracle", outcome="fail",
                                  slice="unknown" if slice_id is None else slice_id)
    scened = check_scenarios(raw_slices)
    seams = check_seams(doc, raw_slices)
    return dict(review=review if review else "none", candidates=len(raw_candidates),
                scenarios=scened, seams=seams)


def seam_attr(name):
    """A seam name for a verdict line: whitespace collapsed to `_`.

    A verdict is space-separated `key=value` (ADR-004), and a seam is named in
    prose — "the launcher's verdict line". Emitted raw, the value would end at
    its first space and every parser downstream would read a truncated name as
    if it were the whole one. The truncation is the failure the rest of this
    verb exists to prevent, so it is squashed here rather than hoped about.
    """
    return "_".join(str(name).split()) or "unnamed"


def check_seams(doc, raw_slices):
    """The unit names its seams once, and every slice tests at a named one.

    Pocock's `to-spec` puts this before any test exists: *"Sketch out the seams
    at which you're going to test the feature. Existing seams should be
    preferred to new ones. Use the highest seam possible. The fewer seams
    across the codebase, the better - the ideal number is one."* Our `/plan`
    wrote a per-slice `oracle:` under no pressure toward a shared seam, so
    eight slices invented eight oracle locations and each one was an
    independent chance to test below the level the claim lives at. That is the
    shape of the worst defect in the corpus: the oracle sat at the unit, not at
    the composition root, so both wiring lines could be deleted with `tsc`
    clean and 738 tests green.

    His gate is a human confirm. Fleet lanes are unattended by construction
    (`plan.md:57`), so the content transfers and the gate does not: the seam
    must be *named, justified and recorded*, and checked mechanically.

    Three things are checkable, and only these three:

      * a plan declares `seams:` at all - at least one;
      * every slice names one, and it is one of the declared ones
        (`unnamed-seam`: the slice tests somewhere nobody agreed to);
      * FEWEST is pressure, not a cap. The first seam needs no defence; every
        seam after it, and every `kind: new` seam, carries `why:` - one line
        saying why the already-named seams cannot hold this slice's claim.
        A number cannot be legislated (some units genuinely need two), but an
        unjustified second seam can be refused, and that is the whole of the
        cost of adding one.

    HIGHEST is a judgement and stays one: `at:` records where the seam is so a
    reviewer and the verifier can see it, and the justification is what they
    read. This refuses the *absence* of that record, never the choice.
    """
    raw_seams = doc.get("seams")
    if raw_seams is None or (isinstance(raw_seams, list) and not raw_seams):
        raise Refusal("plan-unseamed", outcome="fail")
    if not isinstance(raw_seams, list):
        raise Refusal("plan-unparseable")
    names = []
    for i, sm in enumerate(raw_seams):
        if not isinstance(sm, dict):
            raise Refusal("plan-unparseable")
        def text(field, where=sm):
            value = where.get(field)
            return isinstance(value, str) and value.strip()
        name = text("name")
        if not name:
            raise Refusal("seam-unstructured", outcome="fail", seam=i, why="no-name")
        if name in names:
            raise Refusal("seam-unstructured", outcome="fail", seam=seam_attr(name), why="duplicate-name")
        if not text("at"):
            # Where the seam IS, checked at HEAD when written - the same rule
            # `/plan` Step 3 already applies to every code-describing field: a
            # gate carries the obligation and the file:line it was checked at,
            # never a remembered one.
            raise Refusal("seam-unstructured", outcome="fail", seam=seam_attr(name), why="no-at")
        kind = sm.get("kind", "existing")
        if kind not in ("existing", "new"):
            raise Refusal("seam-unstructured", outcome="fail", seam=seam_attr(name), why="unknown-kind")
        if (names or kind == "new") and not text("why"):
            raise Refusal("seam-unstructured", outcome="fail", seam=seam_attr(name),
                          why="new-unjustified" if kind == "new" else "extra-unjustified")
        names.append(name)
    for sl in raw_slices:
        if not isinstance(sl, dict):
            raise Refusal("plan-unparseable")
        slice_id = sl.get("id")
        where = "unknown" if slice_id is None else slice_id
        seam = sl.get("seam")
        if not (isinstance(seam, str) and seam.strip()):
            raise Refusal("slice-unseamed", outcome="fail", slice=where)
        if seam.strip() not in names:
            raise Refusal("unnamed-seam", outcome="fail", slice=where, seam=seam_attr(seam))
    return len(names)


def check_scenarios(raw_slices):
    """Every slice carries at least one structured scenario. Returns the count.

    This is the half of the contract that reaches a unit with **no map at all**,
    which is the one that mattered: both measured zero-first-pass-green runs were
    `review: unattended` with no map.json, so the candidate pipeline — the only
    thing binding an oracle to a decided choice — emitted nothing and every
    oracle in fifteen slices was written freehand from prose. Enforcing the walk
    contract only inside `candidates` would have left those runs untouched.

    `oracle:` stays a free-text string and keeps its meaning: the narrative of
    the test. `scenarios:` is what the executor must make true, in a form that
    cannot be quietly re-interpreted.
    """
    count = 0
    for i, sl in enumerate(raw_slices):
        if not isinstance(sl, dict):
            raise Refusal("plan-unparseable")
        slice_id = sl.get("id")
        where = "unknown" if slice_id is None else slice_id
        scenarios = sl.get("scenarios")
        if scenarios is None or (isinstance(scenarios, list) and not scenarios):
            raise Refusal("slice-unscened", outcome="fail", slice=where)
        if not isinstance(scenarios, list):
            raise Refusal("plan-unparseable")
        for sc in scenarios:
            if not isinstance(sc, dict):
                raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                              why="not-a-mapping")
            def text(field):
                value = sc.get(field)
                return isinstance(value, str) and value.strip()
            if not text("scenario"):
                raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                              why="no-scenario")
            kind = sc.get("kind", "behavioral")
            if kind not in ("behavioral", "structural"):
                raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                              why="unknown-kind")
            if kind == "structural":
                # A census assertion, not a walk: "every appender does X, and no
                # module outside <owner> does X". `/plan` already mandates this
                # form for "every X must do Y" rules, and Given/When/Then cannot
                # hold the negative half, so it keeps prose — but it must say so
                # deliberately rather than by omission.
                if not text("text"):
                    raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                                  why="no-text")
                if any(f in sc for f in ("given", "when", "then")):
                    raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                                  why="structural-gwt")
            else:
                missing = [f for f in ("given", "when", "then") if not text(f)]
                if missing:
                    raise Refusal("scenario-unstructured", outcome="fail", slice=where,
                                  why="missing-" + ",".join(missing))
            count += 1
    return count


PROJECT_OK = TOKEN + " outcome=ok verb=project "


def write(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    target = positional[0]
    if not os.path.isdir(os.path.dirname(os.path.abspath(target))):
        raise Refusal("map-dir-missing")
    try:
        text = sys.stdin.buffer.read().decode("utf-8")
    except (OSError, ValueError):
        raise Refusal("map-unparseable")
    # `project | write`: project's stdout is the map and then its own verdict
    # line. A last line that is project's ok verdict is dropped; any other
    # verdict line there means the step upstream did not produce a map.
    lines = text.rstrip("\n").split("\n")
    if lines[-1].startswith(PROJECT_OK):
        text = "\n".join(lines[:-1])
    elif lines[-1].startswith(TOKEN + " "):
        raise Refusal("upstream-refused")
    try:
        payload = json.loads(text)
    except ValueError:
        raise Refusal("map-unparseable")
    validate(payload)
    write_map(target, payload)
    return dict(forks=len(payload["forks"]), map=target)


# --- project / decisions (ESAS-166 D5, D10) ----------------------------------

def project(positional, flags):
    if "ticket" not in flags:
        raise Refusal("missing-ticket")
    ticket = flags["ticket"]
    if not re.fullmatch(r"[A-Za-z0-9-]+", ticket):
        raise Refusal("malformed-ticket")
    if not positional:
        raise Refusal("missing-map")
    inputs = []
    for map_path in positional:
        payload = naming_map(map_path, load_map, map_path)
        naming_map(map_path, validate, payload)
        inputs.append((map_path, payload))
    first = inputs[0][1]
    for map_path, payload in inputs[1:]:
        if payload["grounded"] != first["grounded"]:
            raise Refusal("grounded-mismatch", map=map_path)
        if payload.get("shape") != first.get("shape"):
            raise Refusal("shape-mismatch", map=map_path)
    nodes, seen_forks, forks, links = {}, set(), [], []
    for map_path, payload in inputs:
        for node in payload["nodes"]:
            if node["id"] in nodes and nodes[node["id"]] != node:
                raise Refusal("node-conflict", id=node["id"], map=map_path)
            nodes.setdefault(node["id"], node)
        for fork in payload["forks"]:
            if fork["id"] in seen_forks:
                raise Refusal("duplicate-fork-id", id=fork["id"], map=map_path)
            seen_forks.add(fork["id"])
            if ticket in fork["tickets"]:
                forks.append(fork)
        for link in payload.get("links", []):
            if link not in links:
                links.append(link)
    kept_forks = {f["id"] for f in forks}
    reached = set()
    pending = [f["anchor"] for f in forks if "anchor" in f]
    while pending:
        nid = pending.pop()
        if nid not in reached:
            reached.add(nid)
            pending.extend(nodes[nid]["parents"])
    out = {"structureVersion": 2}
    if "shape" in first:
        out["shape"] = first["shape"]
    out["grounded"] = first["grounded"]
    out["mapId"] = ticket
    out["nodes"] = [n for nid, n in nodes.items() if nid in reached]
    out["forks"] = [dict(f, restsOn=[r for r in f["restsOn"] if r in kept_forks]) for f in forks]
    kept_links = [l for l in links if l["deliverableId"] in reached]
    if kept_links:
        out["links"] = kept_links
    validate(out)
    sys.stdout.write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    return dict(ticket=ticket, forks=len(out["forks"]), nodes=len(out["nodes"]))


def one_line(text):
    return " ".join(text.split())


def decision_entry(fork):
    status = fork["status"]
    if status["kind"] == "open":
        return "open"
    if status["kind"] == "moot":
        return f"moot — {one_line(status['reason'])}"
    label = next(o["label"] for o in fork["card"]["options"] if o["id"] == status["option"])
    word = {"recommendation": "applied on recommendation"}.get(status["source"], status["source"])
    return f"{word} — {status['option']} ({one_line(label)})"


def decisions(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    payload = load_map(positional[0])
    validate(payload)
    by_ticket = {}
    for fork in payload["forks"]:
        for ticket in fork["tickets"]:
            by_ticket.setdefault(ticket, []).append(fork)
    blocks = []
    for ticket in sorted(by_ticket, key=ticket_key):
        entries = "".join(
            f"- {fork['id']} {one_line(fork['title'])}: {decision_entry(fork)}\n" for fork in by_ticket[ticket]
        )
        blocks.append(f"## {ticket}\n\n{entries}")
    sys.stdout.write("\n".join(blocks))
    def count(kind, source=None):
        return sum(1 for f in payload["forks"]
                   if f["status"]["kind"] == kind and (source is None or f["status"].get("source") == source))
    counts = dict(open=count("open"), owner=count("decided", "owner"),
                  recommendation=count("decided", "recommendation"), code=count("decided", "code"),
                  moot=count("moot"))
    if flags.get("closed") and counts["open"] > 0:
        raise Refusal("open-forks", outcome="fail", **counts)
    return counts


LOST_PROVENANCE = re.compile(r"^mapProvenance:[ \t]*lost[ \t]*$", re.MULTILINE)


def lane_lost(path):
    """Stdlib only: a line-anchored `mapProvenance: lost`, never a YAML parse."""
    try:
        with open(path, encoding="utf-8") as fh:
            return bool(LOST_PROVENANCE.search(fh.read()))
    except (OSError, UnicodeDecodeError):
        raise Refusal("lane-unreadable")


def sidecar_path(map_path):
    """`<map>.json` -> `<map>.resolved-by.json`, beside it. Named after its own
    map because a run dir holds one map per subject in one directory."""
    base = map_path[:-5] if map_path.endswith(".json") else map_path
    return base + ".resolved-by.json"


def read_sidecar(path):
    """The fork ids already recorded. Absent is the empty set — nothing has been
    recorded yet. Unreadable or unparseable is a REFUSAL: treating either as
    empty would re-offer every answer the map holds."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        return set()
    except (OSError, UnicodeDecodeError):
        raise Refusal("sidecar-unreadable")
    try:
        loaded = json.loads(text)
    except ValueError:
        raise Refusal("sidecar-unparseable")
    if not isinstance(loaded, dict):
        raise Refusal("sidecar-unparseable")
    return set(loaded)


def record(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    map_path = positional[0]
    payload = load_map(map_path)
    validate(payload)
    side = sidecar_path(map_path)
    recorded = read_sidecar(side)
    counts = dict(forks=len(payload["forks"]), payloads=0, owner=0, recommendation=0,
                  code=0, unresolved=0, nocard=0, already=0)
    items = []
    for fork in payload["forks"]:
        status = fork["status"]
        if status["kind"] != "decided":
            counts["unresolved"] += 1
            continue
        card = fork.get("card")
        if card is None:
            counts["nocard"] += 1
            continue
        if fork["id"] in recorded:
            counts["already"] += 1
            continue
        counts[status["source"]] += 1
        counts["payloads"] += 1
        items.append({
            "forkKey": fork["id"],
            "question": fork["title"],
            "options": [o["label"] for o in card["options"]],
            "chosen": status["option"],
            "chosenLabel": next(o["label"] for o in card["options"] if o["id"] == status["option"]),
            "rationale": card["recommendation"]["why"],
            "source": status["source"],
            "tickets": list(fork["tickets"]),
        })
    sys.stdout.write(json.dumps(items, indent=2) + "\n")
    counts["sidecar"] = side
    return counts


def count(positional, flags):
    if not positional:
        raise Refusal("missing-map")
    path, line = positional[0], flags.get("line")
    lost = "lane" in flags and lane_lost(flags["lane"])
    if not os.path.exists(path):
        if not line:
            raise Refusal("map-not-found")
        sys.stdout.write(("map: owner answers not carried: run dir absent" if lost else "map: none") + "\n")
        return dict(map="none")
    payload = load_map(path)
    validate(payload)
    kinds = [(f["status"]["kind"], f["status"].get("source")) for f in payload["forks"]]
    c = dict(forks=len(kinds), owner=kinds.count(("decided", "owner")), code=kinds.count(("decided", "code")),
             recommendation=kinds.count(("decided", "recommendation")), open=sum(k == "open" for k, _ in kinds),
             moot=sum(k == "moot" for k, _ in kinds))
    if line:
        text = ("map: owner answers not carried: run dir absent" if lost else
                f"{c['owner']} of {c['forks']} forks answered by the owner ({c['code']} by code, "
                f"{c['recommendation']} on recommendation, {c['open']} open, {c['moot']} moot)")
        sys.stdout.write(text + "\n")
    return c


def drift(positional, flags):
    """The outcome travels in the returned attrs (current|drifted|skip); main pops it."""
    if not positional:
        raise Refusal("missing-map")
    if "feed-seq" in flags and flags.get("no-feed"):
        raise Refusal("conflicting-feed")
    if "feed-seq" not in flags and not flags.get("no-feed"):
        raise Refusal("missing-feed")
    feed = None
    if "feed-seq" in flags:
        if not re.fullmatch(r"[0-9]+", flags["feed-seq"]):
            raise Refusal("bad-feed-seq")
        feed = int(flags["feed-seq"])
    payload = load_map(positional[0])
    validate(payload)
    mine = payload.get("feedSeq")
    seqs = dict(mapSeq="none" if mine is None else mine, feedSeq="none" if feed is None else feed)
    if feed is None:
        return dict(outcome="skip", **seqs, reason="no-map-feed")
    return dict(outcome="current" if mine == feed else "drifted", **seqs)


# --- select: the map target (ESAS-174 D1/D2, ADR-009) -----------------------

MAP_TOOLS = ("map_post", "get_map", "start_map_session")


def read_text(path):
    """The file's text, or None when it is absent or unreadable."""
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return None


def read_json_object(path):
    """The file's top-level JSON object, or None for absent, empty, unparseable or non-object."""
    text = read_text(path)
    try:
        value = json.loads(text) if text is not None and text.strip() else None
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def error_code(body):
    """esas spells a tool failure `{ok:false, error:{code}}` (esas-mcp tool-result.ts);
    a top-level `code` is read too."""
    error = body.get("error")
    if isinstance(error, dict) and isinstance(error.get("code"), str):
        return error["code"]
    return body.get("code")


def has_tool(tools, name):
    """A bare name (listTools) or a session-prefixed one (`mcp__<server>__<name>`)."""
    return any(t == name or t.endswith("__" + name) for t in tools)


def cwd_paths(captures):
    """The logical and physical cwd the board's repoPath is compared with:
    pwd.txt's two lines when captured, else this process's $PWD and realpath."""
    text = read_text(os.path.join(captures, "pwd.txt"))
    if text is not None:
        lines = [line for line in text.splitlines() if line]
        if lines:
            return set(lines[:2])
    return {os.environ.get("PWD") or os.getcwd(), os.path.realpath(os.getcwd())}


def probe_rows(captures):
    """Rows 2-8 of the first-match table, over captured files only. The reason
    of the first row that matches, or None when every row passes."""
    tools_text = read_text(os.path.join(captures, "tools.txt"))
    tools = [] if tools_text is None else [t.strip() for t in tools_text.splitlines() if t.strip()]
    if not has_tool(tools, "status"):
        return "no-mcp"
    status = read_json_object(os.path.join(captures, "status.json"))
    caps = status.get("capabilities") if status is not None else None
    families = caps.get("verbFamilies") if isinstance(caps, dict) else None
    if not isinstance(families, list) or "map" not in families:
        return "mcp-no-map"
    if not all(has_tool(tools, name) for name in MAP_TOOLS):
        return "tools-missing"
    if status.get("ok") is not True and error_code(status) != "ESAS_DIR_MISSING":
        return "mcp-error"
    board = read_json_object(os.path.join(captures, "board.json"))
    if board is None:
        return "board-off"
    if board.get("repoPath") not in cwd_paths(captures):
        return "board-other-repo"
    kinds = board.get("boardKinds")
    if not isinstance(kinds, list) or "map" not in kinds:
        return "board-no-map"
    return None


def select(positional, flags):
    """Pure over files: no network, no subprocess. `probe` applies rows 0-8;
    `start` applies rows 0-8 again, then 9-11 over start.json (design.md P2)."""
    phase = flags.get("phase")
    if phase is None:
        raise Refusal("missing-phase")
    if phase not in ("probe", "start"):
        raise Refusal("bad-phase")
    if "captures" not in flags:
        raise Refusal("missing-captures")
    captures = flags["captures"]
    if "map" in flags:
        payload = load_map(flags["map"])
        validate(payload)
        if payload.get("target") == "artifact":
            return dict(target="artifact", reason="pinned", probe="skipped")
    if os.path.exists(flags.get("lane", os.path.join(".work", "lane.yaml"))):
        return dict(target="artifact", reason="fleet-lane", probe="skipped")
    start_path = os.path.join(captures, "start.json")
    if phase == "start" and not os.path.exists(start_path):
        raise Refusal("missing-start")
    reason = probe_rows(captures)
    if reason is not None:
        return dict(target="artifact", reason=reason, probe="done")
    if phase == "probe":
        return dict(target="board-candidate", reason="ok", probe="done")
    start = read_json_object(start_path)
    if start is None or start.get("ok") is not True:
        linked = start is not None and error_code(start) == "LINKED_WORKTREE"
        return dict(target="artifact", reason="linked-worktree" if linked else "start-failed", probe="done")
    return dict(target="board", reason="ok", probe="done")


# --- post (ESAS-174 D7, design.md P3) ----------------------------------------

STATUS_FIELDS = ("kind", "source", "reason", "option")


def status_tuple(status):
    """The parity tuple of one fork status; an absent field is None."""
    return tuple(status.get(field) for field in STATUS_FIELDS)


def readback_forks(path):
    """The forks and mapSeq of a `get_map` tool body `{ok:true, map, mapSeq}`.
    Its map is esas's MapFile (structureVersion 1, no fork `tickets`), so only
    `forks[].status` is read; the plugin's v2 schema is never applied to it."""
    body = read_json_object(path)
    if body is None:
        raise Refusal("readback-unreadable")
    if body.get("ok") is not True:
        raise Refusal("readback-failed", code=error_code(body) or "-")
    payload, seq = body.get("map"), body.get("mapSeq")
    forks = payload.get("forks") if isinstance(payload, dict) else None
    if (not isinstance(forks, list) or not TYPES["integer"](seq)
            or not all(isinstance(f, dict) and isinstance(f.get("status"), dict) for f in forks)):
        raise Refusal("readback-invalid")
    return forks, seq


def post(positional, flags):
    """Pure over two files: the board's store readback against map.json. Fails
    on a fork count other than --expect, or on a different multiset of
    (kind, source, reason, option); `statuses=` prints kind:source only."""
    if "expect" not in flags:
        raise Refusal("missing-expect")
    if not re.fullmatch(r"[0-9]+", flags["expect"]):
        raise Refusal("bad-expect")
    expected = int(flags["expect"])
    if "map" not in flags:
        raise Refusal("missing-map")
    if "readback" not in flags:
        raise Refusal("missing-readback")
    payload = load_map(flags["map"])
    validate(payload)
    forks, seq = readback_forks(flags["readback"])
    tuples = sorted((status_tuple(f["status"]) for f in forks), key=repr)
    local = sorted((status_tuple(f["status"]) for f in payload["forks"]), key=repr)
    attrs = dict(target="board", forks=len(forks), expected=expected, mapSeq=seq,
                 statuses=",".join(sorted(f"{t[0]}:{t[1] or '-'}".replace(" ", "_") for t in tuples)))
    if len(forks) != expected:
        return dict(outcome="fail", reason="count-mismatch", **attrs)
    if tuples != local:
        return dict(outcome="fail", reason="status-mismatch", **attrs)
    return attrs


VERBS = {"validate": validate_map, "write": write, "render": render, "check-page": check,
         "apply-answers": apply_answers, "candidates": candidates, "check-plan": check_plan,
         "project": project, "decisions": decisions, "record": record, "count": count, "drift": drift,
         "select": select, "post": post}
# The flags each verb takes; any other parsed flag is reason=unknown-flag-<name>.
# `candidates` and `check-plan` take positional arguments only, so `--map`
# (the wording ESAS-165's block used) is refused as unknown-flag-map.
FLAGS = {"validate": (), "write": (), "render": ("expect", "out", "stack"), "check-page": ("expect",),
         "apply-answers": ("final",), "candidates": (), "check-plan": (), "project": ("ticket",),
         "decisions": ("closed",), "record": (), "count": ("lane", "line"), "drift": ("feed-seq", "no-feed"),
         "select": ("phase", "captures", "map", "lane"), "post": ("expect", "map", "readback")}


def main(argv):
    verb = argv[1] if len(argv) > 1 else ""
    try:
        if verb not in VERBS:
            raise Refusal("unknown-verb")
        positional, flags = parse_args(argv[2:])
        for name in flags:
            if name not in FLAGS[verb]:
                raise Refusal(f"unknown-flag-{name}")
        attrs = VERBS[verb](positional, flags)
    except Refusal as r:
        return verdict(r.outcome, verb=verb or "none", reason=r.reason, **r.attrs)
    outcome = attrs.pop("outcome", "ok")
    return verdict(outcome, verb=verb, **attrs)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
