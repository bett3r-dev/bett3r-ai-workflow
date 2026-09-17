#!/usr/bin/env python3
"""Group a design-multi run's units into subjects (ESAS-166 D2, D4, Fork 1).

    design-multi-subjects group <units-dir> [--seams <accepted.json>] [--prior <grouping.json>]

Prints the grouping JSON, then ONE verdict line as the last stdout line (ADR-004):

    DESIGN-MULTI-SUBJECTS:v1 outcome=ok subjects=<n> units=<n> fingerprint=<sha256> asked=<n>
    DESIGN-MULTI-SUBJECTS:v1 outcome=error reason=<reason>          (exit 2)

Reasons: unknown-verb, missing-units-dir, unknown-flag-<name>,
missing-flag-value-<name>, units-dir-missing,
no-units, seams-unreadable, seams-malformed, seam-unknown-unit, seam-overlap,
seam-id-collision, prior-unreadable, prior-malformed.

Grouping.
  A unit is every `<id>.ticket.md` in the units dir; <id> is the file name.
  A snapshot is not YAML front matter: it starts `# <KEY> — <title>`, then
  header lines such as `Status: To Do`, then a blank line, then the body.
  The HEADER BLOCK is the lines from the start of the file up to the first
  blank (or whitespace-only) line. The unit's epic is the first header-block
  line matching `^parent: <EPIC>$` exactly (column 0, no YAML parsing);
  /design-multi step 0 writes that line there. An indented line, a line in
  the body (even at column 0), or no line means no epic. Units sharing an
  epic form one subject {id: <EPIC>, basis: epic}; a unit without one is a
  singleton {id: <unit id>, basis: singleton}.

Seam proposals (--seams): a JSON list of {id, units[], basis: "seam"}, only the
  proposals the owner ACCEPTED. Each one becomes a subject {id: <proposal id>,
  basis: seam} holding exactly its units, and those units are removed from
  whatever default subject held them. A default subject left with no units
  disappears; one left with some keeps its id and basis (a split of an epic
  leaves the remainder as the epic subject). Refused: a unit that is not in
  the units dir, a unit in two proposals, a basis other than "seam", an empty
  units list, and a proposal id equal to another proposal's or to a surviving
  default subject's id.

subjectsFingerprint = sha256 hex of the UTF-8 text made of these lines, each
  ending in "\\n":
    unit <id> parent <EPIC or ->            one per unit, sorted by id
    seam <proposal id> <u1>,<u2>,...        one per accepted proposal, sorted
                                            by id, its units sorted
  It covers the inputs (unit ids, parent keys, accepted proposals), not the
  derived subjects, so it is the D4 formula made replayable.

asked (--prior: a grouping this helper printed earlier, i.e. the JSON above
  the verdict): the number of CURRENT subjects for which no prior subject has
  the same id, basis and unit set — new subjects, and subjects that gained or
  lost a member. A prior subject that vanished entirely is not counted (there
  is nothing left to ask about). Without --prior every subject is asked.

`confirmed`/`confirmedAt` belong to run.yaml; its single writer is the
orchestrator, so this helper never writes a file.
"""
import hashlib
import json
import os
import re
import sys

TOKEN = "DESIGN-MULTI-SUBJECTS:v1"
PARENT = re.compile(r"^parent: (\S+)[ \t]*$")
SUFFIX = ".ticket.md"
FLAGS = ("seams", "prior")


class Refusal(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def verdict(outcome, **attrs):
    parts = [TOKEN, f"outcome={outcome}"] + [f"{k}={v}" for k, v in attrs.items()]
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return 0 if outcome == "ok" else 2


def parse_args(args):
    positional, flags, i = [], {}, 0
    while i < len(args):
        arg = args[i]
        if arg.startswith("--"):
            name = arg[2:]
            if name not in FLAGS:
                raise Refusal(f"unknown-flag-{name}")
            if i + 1 >= len(args):
                raise Refusal(f"missing-flag-value-{name}")
            flags[name] = args[i + 1]
            i += 2
        else:
            positional.append(arg)
            i += 1
    return positional, flags


def read_units(units_dir):
    if not os.path.isdir(units_dir):
        raise Refusal("units-dir-missing")
    parents = {}
    for name in sorted(os.listdir(units_dir)):
        if not name.endswith(SUFFIX) or len(name) == len(SUFFIX):
            continue
        with open(os.path.join(units_dir, name), encoding="utf-8") as fh:
            parents[name[: -len(SUFFIX)]] = header_parent(fh.read())
    if not parents:
        raise Refusal("no-units")
    return parents


def header_parent(text):
    for line in text.splitlines():
        if not line.strip():
            return None
        match = PARENT.match(line)
        if match:
            return match.group(1)
    return None


def load_json(path, unreadable, malformed):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        raise Refusal(unreadable)
    try:
        return json.loads(text)
    except ValueError:
        raise Refusal(malformed)


def read_seams(path, parents):
    doc = load_json(path, "seams-unreadable", "seams-malformed")
    if not isinstance(doc, list):
        raise Refusal("seams-malformed")
    seams, seen_ids, seen_units = [], set(), set()
    for p in doc:
        if (
            not isinstance(p, dict)
            or p.get("basis") != "seam"
            or not isinstance(p.get("id"), str)
            or not p["id"]
            or not isinstance(p.get("units"), list)
            or not p["units"]
            or not all(isinstance(u, str) for u in p["units"])
        ):
            raise Refusal("seams-malformed")
        if p["id"] in seen_ids:
            raise Refusal("seam-id-collision")
        seen_ids.add(p["id"])
        units = sorted(set(p["units"]))
        for u in units:
            if u not in parents:
                raise Refusal("seam-unknown-unit")
            if u in seen_units:
                raise Refusal("seam-overlap")
            seen_units.add(u)
        seams.append({"id": p["id"], "units": units})
    return sorted(seams, key=lambda s: s["id"])


def group(parents, seams):
    taken = {u for s in seams for u in s["units"]}
    defaults = {}
    for unit, epic in parents.items():
        if unit in taken:
            continue
        key, basis = (epic, "epic") if epic else (unit, "singleton")
        defaults.setdefault(key, {"id": key, "units": [], "basis": basis})["units"].append(unit)
    subjects = list(defaults.values())
    for s in seams:
        if s["id"] in defaults:
            raise Refusal("seam-id-collision")
        subjects.append({"id": s["id"], "units": s["units"], "basis": "seam"})
    for s in subjects:
        s["units"] = sorted(s["units"])
    return sorted(subjects, key=lambda s: s["id"])


def fingerprint(parents, seams):
    lines = [f"unit {u} parent {parents[u] or '-'}\n" for u in sorted(parents)]
    lines += [f"seam {s['id']} {','.join(s['units'])}\n" for s in seams]
    return hashlib.sha256("".join(lines).encode("utf-8")).hexdigest()


def count_asked(subjects, prior_path):
    if prior_path is None:
        return len(subjects)
    doc = load_json(prior_path, "prior-unreadable", "prior-malformed")
    try:
        known = {(s["id"], s["basis"], tuple(sorted(s["units"]))) for s in doc["subjects"]}
    except (TypeError, KeyError):
        raise Refusal("prior-malformed")
    return sum(1 for s in subjects if (s["id"], s["basis"], tuple(s["units"])) not in known)


def main(argv):
    verb = argv[1] if len(argv) > 1 else ""
    try:
        if verb != "group":
            raise Refusal("unknown-verb")
        positional, flags = parse_args(argv[2:])
        if len(positional) != 1:
            raise Refusal("missing-units-dir")
        parents = read_units(positional[0])
        seams = read_seams(flags["seams"], parents) if "seams" in flags else []
        subjects = group(parents, seams)
        fp = fingerprint(parents, seams)
        asked = count_asked(subjects, flags.get("prior"))
    except Refusal as r:
        return verdict("error", reason=r.reason)
    doc = {"subjects": subjects, "subjectsFingerprint": fp}
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return verdict("ok", subjects=len(subjects), units=len(parents), fingerprint=fp, asked=asked)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
