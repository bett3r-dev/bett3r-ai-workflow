#!/usr/bin/env python3
"""Retire every pre-tick `agents.yaml` row by stamping it `tick: 0`.

GH-429 makes `agents.yaml` rows tick-scoped: only the CURRENT tick's rows are
addressable, every earlier row being attribution-only (design risk 2). Rows
written before that rule carry no `tick:`, so a resuming orchestrator reads them
as current and `SendMessage`s `agentId`s whose session died days ago -- and a
message that goes nowhere is indistinguishable from a lane not answering.

`tick: 0` is never a current tick (ticks start at 1), so a stamped row stays
readable for attribution and can never be addressed. This is a ONE-OFF for runs
that predate the rule; the orchestrator stamps its own rows from here on.

Why a line-oriented edit rather than a YAML round-trip:

  * PyYAML is not a dependency of this plugin's scripts -- `fleet-loop.py` says
    so where it hand-rolls one scalar read for the same reason.
  * A round-trip would DESTROY load-bearing comments. Observed in the wild:
    `# Do NOT resolve ESAS-225 to this agent.` and `# SUPERSEDED - killed by
    429, resume did not take`. Those comments are the operator's record of which
    agent must never be messaged; dropping them to add a safety key is a net
    loss of exactly the safety being added.
  * One legacy row carries DUPLICATE `status:` keys in a single mapping, which a
    strict loader rejects and a lenient one silently collapses. Text does not
    care, and this script has no business normalising a file it was asked to
    annotate.

The row test is `agentId:`, NOT the section name. Section keys observed across
six repos: `agents:`, `lanes:`, `provisioners:`, plus `serial: []`. Keying on the
parent would miss two of them. An addressable row is exactly a row that names an
`agentId`, which is also precisely the thing that becomes dangerous.

Usage:
    stamp-legacy-agents.py <run-dir> [<run-dir> ...]   # dry run, prints a diff
    stamp-legacy-agents.py --apply <run-dir> [...]     # writes, after a .bak

Dry run is the default: this mutates state outside any repo, and an unlanded run
is not reproducible if it is damaged.
"""

import difflib
import os
import re
import shutil
import sys

# A flow-mapping row: `- { unitId: X, agentId: abc, ... }` on one line.
FLOW_ROW = re.compile(r"^(?P<indent>\s*)-\s*\{(?P<body>.*)\}\s*$")
# A block-mapping row's FIRST line: `- unitId: X`, its siblings indented below.
BLOCK_ROW_START = re.compile(r"^(?P<indent>\s*)-\s+(?P<key>[A-Za-z_][\w-]*):")
AGENT_ID = re.compile(r"\bagentId:")
HAS_TICK = re.compile(r"\btick:")


def stamp_flow(line, match):
    """Insert `tick: 0` as the last entry of a one-line flow mapping."""
    body = match.group("body").rstrip()
    trailing_comma = body.endswith(",")
    if trailing_comma:
        body = body[:-1].rstrip()
    return "%s- { %s, tick: 0 }" % (match.group("indent"), body.strip())


def stamp_file(path):
    """Return (new_text, stamped, already, skipped_no_agent) for one file."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines(keepends=True)

    out = []
    stamped = already = 0
    index = 0
    while index < len(lines):
        line = lines[index]
        raw = line.rstrip("\n")

        flow = FLOW_ROW.match(raw)
        if flow and AGENT_ID.search(raw):
            if HAS_TICK.search(raw):
                already += 1
                out.append(line)
            else:
                out.append(stamp_flow(raw, flow) + "\n")
                stamped += 1
            index += 1
            continue

        block = BLOCK_ROW_START.match(raw)
        if block and not flow:
            # Collect the whole block row: its first line plus every line
            # indented deeper than the `-`, stopping at the next row or a
            # dedent. Comments inside the row are carried verbatim.
            indent = len(block.group("indent"))
            row = [line]
            probe = index + 1
            while probe < len(lines):
                nxt = lines[probe].rstrip("\n")
                if not nxt.strip():
                    row.append(lines[probe])
                    probe += 1
                    continue
                lead = len(nxt) - len(nxt.lstrip())
                if lead <= indent:
                    break
                row.append(lines[probe])
                probe += 1
            joined = "".join(row)
            if AGENT_ID.search(joined):
                if HAS_TICK.search(joined):
                    already += 1
                else:
                    # Append a sibling at the mapping's own indent: the first
                    # line's `- ` is two columns, so siblings sit at indent + 2.
                    trailing = []
                    while row and not row[-1].strip():
                        trailing.insert(0, row.pop())
                    row.append("%stick: 0\n" % (" " * (indent + 2)))
                    row.extend(trailing)
                    stamped += 1
            out.extend(row)
            index = probe
            continue

        out.append(line)
        index += 1

    return "".join(out), stamped, already


def main(argv):
    args = argv[1:]
    apply_changes = False
    if args and args[0] == "--apply":
        apply_changes = True
        args = args[1:]
    if not args:
        sys.stderr.write(
            "usage: stamp-legacy-agents.py [--apply] <run-dir> [<run-dir> ...]\n"
        )
        return 2

    total_stamped = 0
    for run_dir in args:
        path = os.path.join(run_dir, "agents.yaml")
        if not os.path.isfile(path):
            print("SKIP  %s -- no agents.yaml" % run_dir)
            continue
        new_text, stamped, already = stamp_file(path)
        label = os.path.basename(os.path.normpath(run_dir))
        if stamped == 0:
            print("OK    %-70s nothing to stamp (%d already ticked)" % (label, already))
            continue
        total_stamped += stamped
        print("STAMP %-70s %d row(s) -> tick: 0 (%d already)" % (label, stamped, already))
        if apply_changes:
            shutil.copyfile(path, path + ".bak")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(new_text)
            print("      wrote %s (backup: agents.yaml.bak)" % path)
        else:
            # A real diff, not a zip of two line lists: stamping a block row
            # INSERTS a line, so a positional pairing misreports every line
            # after the first insertion -- in the one output a human reads to
            # decide whether to apply this.
            with open(path, encoding="utf-8") as handle:
                old = handle.read().splitlines()
            for row in difflib.unified_diff(
                old, new_text.splitlines(), lineterm="", n=0
            ):
                if row.startswith(("---", "+++")):
                    continue
                print("      %s" % row[:140])

    if not apply_changes and total_stamped:
        print("\nDRY RUN -- nothing written. Re-run with --apply to write (.bak kept).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
