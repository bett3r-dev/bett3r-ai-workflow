#!/usr/bin/env python3
"""Rule a `concerns.md` and refuse to pass while any hard bar is unmet.

The `concern` skill captures an owner's stated bar the moment it is said,
from any step; `/verify-build` rules each concern with evidence before this
script runs. This script does one thing: read the ruled file and say whether
the unit may land, in ONE line (ADR-004) — never an exit code alone.

    CONCERNS-CHECK:v1 outcome=pass|fail|error hard=<n> soft=<n> unmet=<ids|none> missing=<ids|none> [reason=<reason>] [id=<Cn>] [decision=<Dn>] [field=<name>] [line=<n>] [value=<v>] [path=<p>] [detail=<d>]

`unmet=` names every concern (hard or soft) ruled `partial`, `unmet` or
`cannot-determine` — a soft one there still passes; a hard one there fails
the whole file. `missing=` names every concern still at its unset `verdict:
—`, which fails regardless of bar. A malformed file is `outcome=error`,
never a pass and never a plain fail: something is wrong with the file
itself, not with what it reports, and the line names the entry id or line
number and the defect so nobody has to re-read the whole file to find it.
Exactly one defect is reported: the first structural one (header, content
outside an entry, a non-field line, an unknown/repeated field, a duplicate
id) in file order; failing that, the first field-level one, entry by entry.

Every value written after `=` is percent-escaped (space, tab, `%`, `=` and
control characters become `%XX`), so a key=value reader splits the line on
whitespace and `urllib.parse.unquote` recovers the original — a verdict of
`unmet (see PR)` or a path with spaces cannot break the line.

Path argument, not `--item`: `/verify-build` rules its own unit's
`concerns.md`, resolved earlier via `work-docs-path`. `/merge-multi` rules
*other* units' heads — `git show <sha>:<path>` piped to a temp file, or a
worktree checkout — paths this script has no way to resolve on its own via
an `--item`/work-docs-path lookup (a foreign branch's work-docs root may not
even be checked out). Accepting a file keeps one script serving both callers
without embedding git-ref resolution into a markdown-parsing tool.

Absent file: `outcome=error reason=file-not-found` — fail closed. A missing
file is never read as "no concerns, so pass": a concerns.md that fails to
resolve (bad path, unmerged branch, typo) must never look identical to a
unit that genuinely raised none.

Empty file: `outcome=pass hard=0 soft=0 unmet=none missing=none` ONLY when
the file is empty or whitespace-only after stripping one leading UTF-8 BOM.
No title line is allowed — the `concern` skill never writes one. Anything
else that parses to zero entries is impossible, because every non-blank
line must belong to an entry:

- a line starting with `#` that is not exactly `## C<n> — <label>` (`<n>`
  without a leading zero, `<label>` non-empty) is
  `reason=malformed-header line=<n>` — `### C1`, `## C1 - x`, `## c1 — x`,
  `## Concern 1 — x`, `## C1 —`, `# Concerns` all land here;
- any other non-blank line before the first header is
  `reason=malformed-unrecognised-content line=<n>` — prose, a bullet list;
- inside an entry, a line that is not `<key>: <value>` (prose included) is
  `reason=malformed-entry id=<Cn> line=<n>`, and a key outside the seven
  fields below is `reason=malformed-unknown-field id=<Cn> field=<key>`.

Entry shape (this is the ONE contract; the `concern` skill's SKILL.md ships
the same fenced block and `test-flow-seams.sh` asserts they name the same
`bar:` and `verdict:` enums — a drift between the two files must go red,
not silently accepted by whichever one runs last):

    ## C1 — <label>
    bar: hard                # hard | soft
    raisedBy: <free text>
    quote: "<verbatim>"
    why: <free text>
    verify: <free text>
    verdict: —               # met | partial | unmet | cannot-determine | waived | —
    evidence: <free text>

The `# …` comments above document the enums. On `bar:` and `verdict:` only,
a trailing comment — one word, whitespace, then `#…` — is ignored, so the
example copied literally parses. `verdict: # met` (no word), `verdict: met#x`
(no whitespace) and `bar: hard soft # x` (two words) stay malformed. Free-text
fields are never comment-stripped: `evidence:` legitimately holds `#D3`.

All seven fields are required on every entry — a missing one is
`malformed-missing-field`, a repeated one `malformed-entry`. `bar` must be
`hard` or `soft`; `verdict` one of the six values above (including the
literal placeholder `—`); anything else is `malformed-bar-value` /
`malformed-verdict-value`. A duplicate id (`## C1` twice) is
`malformed-entry`. Non-contiguous ids (`C1`, `C3`, no `C2`) are NOT
malformed — a concern can be retired without renumbering its siblings.

Empty values: `raisedBy`, `quote`, `why` and `verify` must be non-empty on
every entry, and `evidence` on every entry whose verdict is not `—`. A value
is empty when, after stripping one pair of surrounding quotes, it is blank,
`—`, `-`, or a whole `<…>` template placeholder such as `<verbatim>`. An
empty one is `malformed-empty-field id=<Cn> field=<name>`.

`quote:` is ALWAYS the owner's raising quote — the words that stated the
bar — and is never overwritten. A waiver's own verbatim quote is recorded
in a `decisions.md` entry (kind: waiver, decidedBy: human) and cited from
`evidence:`. So `verdict: waived` requires:

- a non-empty raising `quote:` — else `malformed-waived-without-quote`;
- `evidence:` citing the waiver record as `decisions.md#D<n>` — else
  `malformed-waived-without-waiver-record`.

Without `--decisions` the check stops there: a `decisions.md#D<n>`
substring is enough, so `evidence: not decisions.md#D3` and a path-prefixed
`docs/prs/X/decisions.md#D3` both pass. That is the behaviour slice 5
shipped, and it is kept exactly.

`--decisions <decisions.md>` makes the citation an authorisation, verified
against THAT file — the unit's own `decisions.md` (`/verify-build` always
passes it). For every `waived` entry, after the entry's own field checks,
EVERY `decisions.md#D<n>` in its `evidence:` must hold, or the line is
`outcome=error id=<Cn> decision=D<n>` with one of these reasons:

- `waiver-record-foreign-file` — the citation is prefixed by a path or any
  other character (`docs/prs/X/decisions.md#D3`, `./decisions.md#D3`, a
  URL). Only a bare `decisions.md#D<n>` names this unit's own file: it
  follows the start of the value, a space, a tab or `(` — the non-path
  prefixes `WAIVER_RECORD` already accepts.
- `waiver-record-missing` — no `## D<n> — ` entry with that id in the file.
- `waiver-record-ambiguous` — the id heads two entries; neither is picked.
- `waiver-record-not-waiver` (`value=<kind>`) — its `kind:` is not `waiver`.
- `waiver-record-not-human` (`value=<decidedBy>`) — its `decidedBy:` is not
  `human`.
- `waiver-record-other-concern` (`value=<title>`) — the entry's `## D<n> — `
  title does not name this C-entry's id; one concern's waiver never backs
  another. The id matches only whole: `C1` is not in `C12` or `XC1`.
- `waiver-record-empty` — no body: nothing after the header fields, so no
  place for the owner's verbatim waiver quote.
- `waiver-record-no-quote` — the body holds no quoted span: no non-blank
  text between straight double quotes (`"…"`) or curly ones (`“…”`). Single
  quotes do not count — they are apostrophes in prose too often.
- `waiver-decisions-not-found` / `waiver-decisions-unreadable` (`path=`) —
  the `--decisions` file is absent or unreadable while a waived entry needs
  it. The file is read only then: a unit that raised no waiver (and may have
  written no `decisions.md` at all) is ruled exactly as without the flag.

The D-entry grammar is not a second one: it is the header `commands/build.md`
fixes in *The committed record* —

    ## D1 — <one-line decision>
    kind: silent-seam        # ... | waiver
    step: build · slice: 2 · decidedBy: executor    # ... | human
    sources: [...]
    rejected: <option> — <why not>
    supersedes: —
    <prose: why>

An entry runs from its `## D<n> — ` header to the next `## ` line; anything
before the first header (a title, an intro) is ignored. A line starting with
a code fence toggles fenced mode, as the Seam I reader in test-flow-seams.sh
does: the fence line and every line inside it are body, never a header or a
field, so a fenced example of a waiver entry is never read as one. The title
is everything after `— ` on the header line. `kind` is the first
`kind:` line's value, a trailing ` # …` comment removed. `decidedBy` is read
from the first `step:` line's `decidedBy:` segment, its comment removed. The
body is every non-blank line that is not one of the five header fields.

Prose negation is not parsed: `not decisions.md#D3` fails only because D3 is
not a waiver; a negated citation of a real waiver entry still verifies.

Usage: concerns-check [--decisions <decisions.md>] <concerns.md>
Exit 0 on outcome=pass, 1 on outcome=fail, 2 on outcome=error or a usage
error — a coarse cross-check only; read the line.
"""
import os
import re
import sys

TOKEN = "CONCERNS-CHECK:v1"

BAR_VALUES = ("hard", "soft")
VERDICT_VALUES = ("met", "partial", "unmet", "cannot-determine", "waived", "—")
UNMET_VALUES = ("partial", "unmet", "cannot-determine")
REQUIRED_FIELDS = ("bar", "raisedBy", "quote", "why", "verify", "verdict", "evidence")
NON_EMPTY_FIELDS = ("raisedBy", "quote", "why", "verify")
PLACEHOLDERS = ("", "—", "-")
COMMENTED_FIELDS = ("bar", "verdict")
TRAILING_COMMENT = re.compile(r"^(\S+)\s+#.*$")

BOM = "﻿"
HEADER = re.compile(r"^## C([1-9][0-9]*) — \S.*$")
HEADER_LIKE = re.compile(r"^\s*#")
FIELD = re.compile(r"^([A-Za-z]+):\s*(.*)$")
TEMPLATE = re.compile(r"^<[^<>]*>$")
WAIVER_RECORD = re.compile(r"(?:^|[\s/(])decisions\.md#D[1-9][0-9]*\b")

# --decisions: the decisions.md header grammar from commands/build.md.
CITATION = re.compile(r"decisions\.md#D([1-9][0-9]*)\b")
CITATION_OWN_FILE_PREFIX = " \t("
DECISION_HEADER = re.compile(r"^## D([1-9][0-9]*) — (.*)$")
FENCE = "```"
QUOTED = re.compile(r"\"[^\"]*\S[^\"]*\"|“[^”]*\S[^”]*”")
H2 = re.compile(r"^## ")
DECISION_FIELD = re.compile(r"^(kind|step|sources|rejected|supersedes):\s*(.*)$")
DECIDED_BY = re.compile(r"decidedBy:\s*([^\s#·]*)")
COMMENT = re.compile(r"\s+#.*$")


def escape(val):
    out = []
    for ch in str(val):
        if ch in " \t%=" or ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append("%{:02X}".format(ord(ch)))
        else:
            out.append(ch)
    return "".join(out)


def verdict(outcome, **attrs):
    parts = [TOKEN, f"outcome={outcome}"]
    parts += [f"{k}={escape(v)}" for k, v in attrs.items()]
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return {"pass": 0, "fail": 1, "error": 2}[outcome]


def strip_quotes(val):
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
        return val[1:-1]
    return val


def is_empty(val):
    val = val.strip()
    return val in PLACEHOLDERS or bool(TEMPLATE.match(val))


def parse(text):
    """Return (entries, error).

    entries is [(id, fields)] in file order; error is None or a dict of
    verdict attributes for the FIRST structural defect in file order, in
    which case entries must not be ruled.
    """
    entries = []
    seen_ids = set()
    current = None  # (cid, fields) of the entry being read
    for lineno, line in enumerate(text.splitlines(), start=1):
        m = HEADER.match(line)
        if m:
            cid = f"C{m.group(1)}"
            if cid in seen_ids:
                return entries, {"reason": "malformed-entry", "id": cid,
                                 "line": lineno, "detail": f"duplicate id {cid}"}
            seen_ids.add(cid)
            current = (cid, {})
            entries.append(current)
            continue
        if line.strip() == "":
            continue
        if HEADER_LIKE.match(line):
            return entries, {"reason": "malformed-header", "line": lineno}
        if current is None:
            return entries, {"reason": "malformed-unrecognised-content", "line": lineno}
        cid, fields = current
        fm = FIELD.match(line)
        if not fm:
            return entries, {"reason": "malformed-entry", "id": cid, "line": lineno,
                             "detail": "not a key: value line"}
        key, val = fm.group(1), strip_quotes(fm.group(2).strip())
        if key in COMMENTED_FIELDS:
            val = TRAILING_COMMENT.sub(r"\1", val)
        if key not in REQUIRED_FIELDS:
            return entries, {"reason": "malformed-unknown-field", "id": cid,
                             "field": key, "line": lineno}
        if key in fields:
            return entries, {"reason": "malformed-entry", "id": cid, "line": lineno,
                             "detail": f"duplicate field {key}"}
        fields[key] = val
    return entries, None


def parse_decisions(text):
    """Return {id: [record, ...]}; a record is {title, kind, decidedBy, body}."""
    records = {}
    current = None
    fence = False
    for line in text.splitlines():
        if line.startswith(FENCE):
            # As Seam I reads decisions.md: a fence line toggles, and it and
            # everything inside it is body — never a header or a field.
            fence = not fence
            if current is not None:
                current["body"].append(line)
            continue
        if fence:
            if current is not None:
                current["body"].append(line)
            continue
        m = DECISION_HEADER.match(line)
        if m:
            current = {"title": m.group(2), "kind": None, "decidedBy": None, "body": []}
            records.setdefault(f"D{m.group(1)}", []).append(current)
            continue
        if H2.match(line):
            current = None
            continue
        if current is None or line.strip() == "":
            continue
        fm = DECISION_FIELD.match(line)
        if not fm:
            current["body"].append(line)
            continue
        key, val = fm.group(1), COMMENT.sub("", fm.group(2)).strip()
        if key == "kind" and current["kind"] is None:
            current["kind"] = val
        elif key == "step" and current["decidedBy"] is None:
            dm = DECIDED_BY.search(val)
            current["decidedBy"] = dm.group(1) if dm else ""
    return records


def verify_waiver(cid, evidence, records):
    """Return None, or the verdict attributes of the first bad citation."""
    for m in CITATION.finditer(evidence):
        did = f"D{m.group(1)}"
        if m.start() > 0 and evidence[m.start() - 1] not in CITATION_OWN_FILE_PREFIX:
            start = m.start()
            while start > 0 and not evidence[start - 1].isspace():
                start -= 1
            return {"reason": "waiver-record-foreign-file", "id": cid, "decision": did,
                    "value": evidence[start:m.end()]}
        found = records.get(did, [])
        if not found:
            return {"reason": "waiver-record-missing", "id": cid, "decision": did}
        if len(found) > 1:
            return {"reason": "waiver-record-ambiguous", "id": cid, "decision": did}
        rec = found[0]
        if rec["kind"] != "waiver":
            return {"reason": "waiver-record-not-waiver", "id": cid, "decision": did,
                    "value": rec["kind"] or "none"}
        if rec["decidedBy"] != "human":
            return {"reason": "waiver-record-not-human", "id": cid, "decision": did,
                    "value": rec["decidedBy"] or "none"}
        if not re.search(r"(?<![A-Za-z0-9])%s(?![0-9])" % re.escape(cid), rec["title"]):
            return {"reason": "waiver-record-other-concern", "id": cid, "decision": did,
                    "value": rec["title"]}
        if not rec["body"]:
            return {"reason": "waiver-record-empty", "id": cid, "decision": did}
        if not QUOTED.search("\n".join(rec["body"])):
            return {"reason": "waiver-record-no-quote", "id": cid, "decision": did}
    return None


def usage():
    sys.stderr.write("usage: concerns-check [--decisions <decisions.md>] <concerns.md>\n")
    return 2


def main(argv):
    args = argv[1:]
    decisions_path = None
    paths = []
    i = 0
    while i < len(args):
        if args[i] == "--decisions":
            if decisions_path is not None or i + 1 >= len(args):
                return usage()
            decisions_path = args[i + 1]
            i += 2
            continue
        paths.append(args[i])
        i += 1
    if len(paths) != 1:
        return usage()
    path = paths[0]
    if not os.path.isfile(path):
        return verdict("error", reason="file-not-found", path=path)
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        return verdict("error", reason="file-unreadable", path=path)

    if text.startswith(BOM):
        text = text[len(BOM):]
    if text.strip() == "":
        return verdict("pass", hard=0, soft=0, unmet="none", missing="none")

    entries, error = parse(text)
    if error:
        return verdict("error", **error)
    if not entries:
        # Unreachable while parse() rejects every non-blank line outside an
        # entry; kept so a future parser change cannot turn content into a pass.
        return verdict("error", reason="malformed-no-entries")

    decisions = None  # parsed lazily: only a waived entry needs the file
    for cid, fields in entries:
        missing_fields = [f for f in REQUIRED_FIELDS if f not in fields]
        if missing_fields:
            return verdict("error", reason="malformed-missing-field",
                           id=cid, field=missing_fields[0])
        if fields["bar"] not in BAR_VALUES:
            return verdict("error", reason="malformed-bar-value", id=cid, value=fields["bar"])
        if fields["verdict"] not in VERDICT_VALUES:
            return verdict("error", reason="malformed-verdict-value", id=cid, value=fields["verdict"])
        if fields["verdict"] == "waived":
            if is_empty(fields["quote"]):
                return verdict("error", reason="malformed-waived-without-quote", id=cid)
            if not WAIVER_RECORD.search(fields["evidence"]):
                return verdict("error", reason="malformed-waived-without-waiver-record", id=cid)
        for name in NON_EMPTY_FIELDS:
            if is_empty(fields[name]):
                return verdict("error", reason="malformed-empty-field", id=cid, field=name)
        if fields["verdict"] != "—" and is_empty(fields["evidence"]):
            return verdict("error", reason="malformed-empty-field", id=cid, field="evidence")
        if fields["verdict"] == "waived" and decisions_path is not None:
            if decisions is None:
                if not os.path.isfile(decisions_path):
                    return verdict("error", reason="waiver-decisions-not-found",
                                   id=cid, path=decisions_path)
                try:
                    with open(decisions_path, encoding="utf-8") as fh:
                        decisions = parse_decisions(fh.read().lstrip(BOM))
                except (OSError, UnicodeDecodeError):
                    return verdict("error", reason="waiver-decisions-unreadable",
                                   id=cid, path=decisions_path)
            bad = verify_waiver(cid, fields["evidence"], decisions)
            if bad:
                return verdict("error", **bad)

    hard = sum(1 for _, f in entries if f["bar"] == "hard")
    soft = sum(1 for _, f in entries if f["bar"] == "soft")
    unmet_ids = [cid for cid, f in entries if f["verdict"] in UNMET_VALUES]
    missing_ids = [cid for cid, f in entries if f["verdict"] == "—"]
    hard_unmet_ids = [cid for cid, f in entries if f["bar"] == "hard" and f["verdict"] in UNMET_VALUES]

    unmet_str = ",".join(unmet_ids) if unmet_ids else "none"
    missing_str = ",".join(missing_ids) if missing_ids else "none"

    if missing_ids:
        return verdict("fail", hard=hard, soft=soft, unmet=unmet_str,
                       missing=missing_str, reason="missing-verdict")
    if hard_unmet_ids:
        return verdict("fail", hard=hard, soft=soft, unmet=unmet_str,
                       missing=missing_str, reason="hard-unmet")
    return verdict("pass", hard=hard, soft=soft, unmet=unmet_str, missing=missing_str)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
