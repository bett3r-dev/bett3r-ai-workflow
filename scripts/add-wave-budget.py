#!/usr/bin/env python3
"""Add `waveBudget` / `spendToDate` to a run.yaml that predates the wave yield.

Both are top-level keys the yield needs and NO unit can supply: `waveBudget` is a
policy input (owner-set: 3 waves / $30), and `spendToDate` is an accumulator the
rule says is never re-derived. A legacy run has neither.

`spendToDate` starts at 0 WITH a note, not silently: the real prior spend is
unrecoverable (no run.yaml here records a dollar figure), so a bare 0 would read
as "this run has cost nothing" instead of "the accumulator starts here".
Idempotent -- a file that already has waveBudget is left alone.
"""
import sys

WAVES, CEILING = 3, 30


def patch(path):
    with open(path, encoding="utf-8") as h:
        lines = h.read().splitlines(keepends=True)
    if any(l.startswith("waveBudget:") for l in lines):
        return None, "already has waveBudget"

    block = [
        "waveBudget: { waves: %d, ceiling: %d }   # owner-set 2026-09-19: max waves one tick may dispatch, USD ceiling\n"
        % (WAVES, CEILING),
        "spendToDate: 0   # BASELINE, not a total: this run predates the accumulator and its\n",
        "                 # pre-2026-09-19 spend is unrecoverable. Addends start at the next\n",
        "                 # wave boundary, so the first resumed tick's figure is not the run's.\n",
    ]

    # After the `flags:` line if there is one -- that is where the schema shows
    # these keys -- else after integrationPr / landedAt / runId, whichever comes
    # first, so the key never lands inside someone else's nested block.
    for anchor in ("flags:", "integrationPr:", "landedAt:", "runId:"):
        for i, l in enumerate(lines):
            if l.startswith(anchor):
                lines[i + 1 : i + 1] = block
                return "".join(lines), "inserted after `%s`" % anchor
    return None, "no anchor key found -- not touched"


if __name__ == "__main__":
    for p in sys.argv[1:]:
        new, why = patch(p)
        print("  %-60s %s" % (p.split("/")[-2][:60], why))
        if new:
            with open(p + ".bak2", "w", encoding="utf-8") as h, open(p, encoding="utf-8") as o:
                h.write(o.read())
            with open(p, "w", encoding="utf-8") as h:
                h.write(new)
