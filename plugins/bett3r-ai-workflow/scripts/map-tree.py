#!/usr/bin/env python3
"""Render a ticket's decisions from map.json into a generated, hashed region.

The decision text of a design.md (and, from ESAS-163 slice 2, a Jira ticket
block) is a per-ticket projection of map.json: the forks whose `tickets` hold
the ticket, in map order. It lives between a marker pair carrying two hashes
(ESAS-163 D2/D3):

    <!-- map-tree:v1 ticket=<KEY> gen=1 src=sha256:<hex> out=sha256:<hex> -->
    `map-tree:v1 ticket=<KEY> gen=1 src=sha256:<hex> out=sha256:<hex>`
    <body>
    `/map-tree:v1`
    <!-- /map-tree:v1 -->

`src` is the sha256 of the projection's canonical JSON (sorted keys, compact
separators, UTF-8), so an overturned fork reads `stale`. `out` is the sha256 of
the body normalised (LF, trailing whitespace stripped per line, no leading or
trailing blank lines), so a hand edit inside the region reads `tampered`. A
region whose `gen` differs from GEN is re-rendered, never counted as tampered.

Usage:
    map-tree render --map <map.json> --ticket <KEY> [--dialect md]
    map-tree check  --map <map.json> --ticket <KEY> <file> [--dialect md]
    map-tree write  --map <map.json> --ticket <KEY> <file> [--dialect md]
                    [--insert-after <heading>] [--on-tamper refuse|displace]

The map is validated first by the SIBLING launcher `<plugin>/bin/design-map
validate` (never the copy on PATH, which may be an older plugin cache), read
through its `DESIGN-MAP:v1` verdict line.

The last line printed is the verdict (ADR-004); the exit code is a cross-check:
    MAP-TREE:v1 outcome=ok verb=render ticket=<K> forks=<n> owner=<n> code=<n> recommendation=<n> open=<n> moot=<n>
    MAP-TREE:v1 outcome=fresh|stale|tampered verb=check ... path=<file>          exit 0 | 1 | 1
    MAP-TREE:v1 outcome=written|displaced|tampered verb=write ... path=<file>    exit 0 | 0 | 1
    MAP-TREE:v1 outcome=error verb=<v> ticket=<K> [counts] reason=<reason>      exit 2
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

TOKEN = "MAP-TREE:v1"
GEN = 1
DIALECTS = ("md", "jira")
PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN_MAP = os.path.join(PLUGIN, "bin", "design-map")

START_COMMENT = re.compile(r"^<!-- map-tree:v1((?: [^\s=]+=\S+)*) -->$")
START_INLINE = re.compile(r"^`map-tree:v1((?: [^\s=`]+=[^\s`]+)*)`$")
END_INLINE = "`/map-tree:v1`"
END_COMMENT = "<!-- /map-tree:v1 -->"
COUNT_KEYS = ("forks", "owner", "code", "recommendation", "open", "moot")


class Refusal(Exception):
    def __init__(self, reason, exit_code=2, **attrs):
        super().__init__(reason)
        self.reason, self.exit_code, self.attrs = reason, exit_code, attrs


def verdict(outcome, verb, ticket, counts, **extra):
    parts = [TOKEN, f"outcome={outcome}", f"verb={verb}", f"ticket={ticket or 'none'}"]
    if counts:
        parts += [f"{k}={counts[k]}" for k in COUNT_KEYS]
    parts += [f"{k}={v}" for k, v in extra.items() if v is not None]
    print(" ".join(parts))


# --- map ---------------------------------------------------------------------

def validate(map_path):
    run = subprocess.run(["sh", DESIGN_MAP, "validate", map_path], capture_output=True, text=True)
    lines = [l for l in run.stdout.splitlines() if l.strip()]
    last = lines[-1] if lines else ""
    if not last.startswith("DESIGN-MAP:v1 outcome=ok verb=validate"):
        raise Refusal("map-invalid")


def project(payload, ticket):
    return [f for f in payload["forks"] if ticket in f["tickets"]]


def counts_of(forks):
    c = dict.fromkeys(COUNT_KEYS, 0)
    c["forks"] = len(forks)
    for fork in forks:
        status = fork["status"]
        if status["kind"] == "moot":
            c["moot"] += 1
        elif "card" not in fork or status["kind"] == "open":
            c["open"] += 1
        else:
            c[status["source"]] += 1
    return c


def src_hash(forks):
    canon = json.dumps(forks, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(canon.encode("utf-8")).hexdigest()


def normalise(body):
    lines = [l.rstrip() for l in body.replace("\r\n", "\n").split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def out_hash(body):
    return "sha256:" + hashlib.sha256(normalise(body).encode("utf-8")).hexdigest()


# --- rendering (D8) ----------------------------------------------------------

def option_label(card, option_id):
    for opt in card["options"]:
        if opt["id"] == option_id:
            return opt["label"]
    return option_id


def rejected_line(opt):
    line = f"Rejected — {opt['label']}: {opt.get('rejectedBecause', 'no reason recorded')}"
    if opt.get("evidence"):
        line += f" ({', '.join(opt['evidence'])})"
    return line


def render_md(forks):
    """One `###` section per fork: heading, status tag, why, rejected options."""
    out = []
    for fork in forks:
        status, card = fork["status"], fork.get("card")
        if status["kind"] == "moot":
            out += [f"### {fork['id']} — {fork['title']}", "", f"moot — {status['reason']}", ""]
            continue
        if card is None:
            waits = ", ".join(fork["restsOn"]) or "an unrecorded fork"
            out += [f"### {fork['id']} — {fork['title']}", "", f"LOCKED — waits on {waits}", ""]
            continue
        if status["kind"] == "open":
            rec = option_label(card, card["recommendation"]["option"])
            out += [f"### {fork['id']} — {fork['title']}", "",
                    f"OPEN — recommended: {rec}", "", f"Why: {card['recommendation']['why']}", ""]
            continue
        out += [f"### {fork['id']} — {fork['title']}: {option_label(card, status['option'])}", "",
                f"decided({status['source']})", "", f"Why: {card['recommendation']['why']}", ""]
        rejected = [o for o in card["options"] if o["id"] != status["option"]]
        if rejected:
            out += [f"- {rejected_line(o)}" for o in rejected] + [""]
    return normalise("\n".join(out))


RENDERERS = {"md": render_md}


def render_body(forks, dialect):
    if dialect not in RENDERERS:
        raise Refusal("dialect-not-implemented")
    return RENDERERS[dialect](forks)


def region_text(ticket, src, body):
    attrs = f"ticket={ticket} gen={GEN} src={src} out={out_hash(body)}"
    return f"<!-- map-tree:v1 {attrs} -->\n`map-tree:v1 {attrs}`\n{body}\n{END_INLINE}\n{END_COMMENT}\n"


# --- region parsing (D3) -----------------------------------------------------

def attrs_of(raw):
    return dict(tok.partition("=")[::2] for tok in raw.split())


def find_region(lines, ticket):
    """(start, end, attrs, body) with `start`/`end` line indexes of the comment
    markers, or None when the file holds no region for the ticket."""
    found = []
    for i, line in enumerate(lines):
        m = START_COMMENT.match(line.rstrip("\r\n"))
        if m and attrs_of(m.group(1)).get("ticket") == ticket:
            found.append(i)
    if not found:
        return None
    if len(found) > 1:
        raise Refusal("multiple-regions")
    start = found[0]
    comment = attrs_of(START_COMMENT.match(lines[start].rstrip("\r\n")).group(1))
    twin = START_INLINE.match(lines[start + 1].rstrip("\r\n")) if start + 1 < len(lines) else None
    if twin is None or attrs_of(twin.group(1)) != comment:
        raise Refusal("twin-mismatch")
    for j in range(start + 2, len(lines) - 1):
        if lines[j].rstrip("\r\n") == END_INLINE:
            if lines[j + 1].rstrip("\r\n") != END_COMMENT:
                raise Refusal("twin-mismatch")
            return start, j + 1, comment, "".join(lines[start + 2:j])
    raise Refusal("region-unterminated")


def classify(region, src):
    _, _, attrs, body = region
    if attrs.get("gen") != str(GEN):
        return "stale"
    if attrs.get("out") != out_hash(body):
        return "tampered"
    return "fresh" if attrs.get("src") == src else "stale"


# --- verbs -------------------------------------------------------------------

def parse_args(argv):
    flags, positional, i = {}, [], 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("--"):
            if i + 1 >= len(argv):
                raise Refusal(f"missing-value-{arg[2:]}")
            flags[arg[2:]] = argv[i + 1]
            i += 2
        else:
            positional.append(arg)
            i += 1
    return positional, flags


FLAGS = {"render": ("map", "ticket", "dialect"),
         "check": ("map", "ticket", "dialect"),
         "write": ("map", "ticket", "dialect", "insert-after", "on-tamper")}


def main(argv):
    verb = argv[1] if len(argv) > 1 else ""
    ticket, counts, path = None, None, None
    try:
        if verb not in FLAGS:
            raise Refusal("unknown-verb")
        positional, flags = parse_args(argv[2:])
        ticket = flags.get("ticket")
        for name in flags:
            if name not in FLAGS[verb]:
                raise Refusal(f"unknown-flag-{name}")
        for name in ("map", "ticket"):
            if name not in flags:
                raise Refusal(f"missing-{name}")
        dialect = flags.get("dialect", "md")
        if dialect not in DIALECTS:
            raise Refusal("unknown-dialect")
        on_tamper = flags.get("on-tamper", "refuse")
        if on_tamper not in ("refuse", "displace"):
            raise Refusal("unknown-on-tamper")
        if verb != "render":
            if len(positional) != 1:
                raise Refusal("missing-file")
            path = positional[0]
        if not os.path.isfile(flags["map"]):
            raise Refusal("map-unreadable")
        validate(flags["map"])
        with open(flags["map"], encoding="utf-8") as fh:
            forks = project(json.load(fh), ticket)
        counts = counts_of(forks)
        if not forks:
            raise Refusal("no-forks")
        body = render_body(forks, dialect)
        src = src_hash(forks)

        if verb == "render":
            print(body)
            verdict("ok", verb, ticket, counts)
            return 0

        try:
            with open(path, "rb") as fh:
                raw = fh.read()
        except OSError:
            raise Refusal("file-unreadable")
        lines = raw.decode("utf-8").splitlines(keepends=True)
        region = find_region(lines, ticket)

        if verb == "check":
            if region is None:
                raise Refusal("no-region")
            state = classify(region, src)
            verdict(state, verb, ticket, counts, path=path)
            return 0 if state == "fresh" else 1

        new = region_text(ticket, src, body)
        if region is None:
            heading = flags.get("insert-after")
            if heading is None:
                raise Refusal("no-region")
            at = next((i for i, l in enumerate(lines) if l.rstrip("\r\n") == heading), None)
            if at is None:
                raise Refusal("heading-not-found")
            if not lines[at].endswith("\n"):
                lines[at] += "\n"
            lines[at + 1:at + 1] = ["\n", new]
            outcome = "written"
        else:
            start, end, _, old_body = region
            outcome = "written"
            if classify(region, src) == "tampered":
                if on_tamper == "refuse":
                    verdict("tampered", verb, ticket, counts, path=path)
                    return 1
                if dialect == "jira":
                    raise Refusal("displace-not-allowed-jira")
                outcome = "displaced"
                today = datetime.date.today().isoformat()
                new += f"\n### Displaced from generated section ({today})\n\n{old_body}"
                if not new.endswith("\n"):
                    new += "\n"
            lines[start:end + 1] = [new]
        out = "".join(lines).encode("utf-8")
        if out != raw:
            with open(path, "wb") as fh:
                fh.write(out)
        verdict(outcome, verb, ticket, counts, path=path)
        return 0
    except Refusal as r:
        verdict("error", verb or "none", ticket, counts, reason=r.reason, path=path)
        return r.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
