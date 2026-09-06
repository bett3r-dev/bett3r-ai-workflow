#!/usr/bin/env python3
"""Read a step's transcript and print its `LANE-STEP:v1` verdict, or nothing.

This is **the** implementation of the parse rule specified in
`agents/unit-lane.md` — there is no second copy. The rule was written twice
once already: the oracle carried a reference implementation while nothing
consumed the line, and two parsers nothing runs together is drift that no test
can see. When a caller reads the line, the caller's parser is the only one.

The rule, from the spec block:

    position: the last line of the step's output, at column 0, nothing after it
    parse:    take the last line-anchored match, and require it to be the final line

Every clause is here exactly once, because a clause enforced twice cannot be
killed by a mutation and so is held by nothing:

  * **column 0** is enforced only by `match()`, which anchors at position 0.
    A leading `^` as well would be redundant.
  * **end of line** is enforced only by the trailing `\\s*$`.
  * **last match, and it is the final line** are the two statements below.

Absence of a verdict is not an error and not a failure: ADR-004 makes the
line's ABSENCE the `infra` signal, because a step being OOM-killed cannot be
relied on to say anything. So no verdict exits `3` and prints nothing, and the
caller reads that as `infra`.

**The value grammar is deliberately tighter than "not whitespace".** The
producer is a model, and a model ending its final line with a full stop is
ordinary prose, not a malformed marker: `\\S+` accepts `commits=3.` with the
value `3.`, and the same absorption on `outcome=success.` corrupts the verdict
token itself into a word that is in no vocabulary. A value here is a run of
alphanumerics, joined by single `/`, `.`, `_` or `-` separators that must each
have alphanumerics on both sides — so `3/3`, `verify-build` and `0.42.0` are
values and `3.` is not. A line carrying one fails the token match outright and
yields no verdict, which the caller reads as `infra` and retries. Failing
closed to a retry is the conservative half: the alternative, guessing which
trailing byte was punctuation, invents a verdict nobody emitted.

The version group is captured and **not** consulted: a `vN` line for any N is
parsed by these rules. That is an open question, not an oversight — it is
recorded under "what a `v1` reader does with a `vN` line" in
`docs/adr/ADR-004-a-step-reports-a-line-not-an-exit-code.md`, because deciding
it here would decide it silently and it cannot be decided without knowing
whether callers and steps are deployed together.

Usage:  lane-step <transcript-file>        (or `-`/omitted for stdin)
Prints one `key=value` per attribute, in the order the marker carried them.
Exit 0 = verdict printed. Exit 3 = no verdict. Exit 2 = bad invocation.
"""

import re
import sys

NO_VERDICT = 3

# A single attribute value: alphanumeric runs joined by single separators, each
# of which must have an alphanumeric on both sides. See the module docstring for
# why this is not `\S+`.
VALUE = r"[A-Za-z0-9]+(?:[/._-][A-Za-z0-9]+)*"

# The marker. `match()` supplies the column-0 anchor; `\s*$` is the only
# end-of-line clause. Neither is repeated.
TOKEN = re.compile(r"LANE-STEP:v(\d+)((?:\s+[A-Za-z_][A-Za-z0-9_]*=" + VALUE + r")+)\s*$")

ATTRIBUTE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)=(" + VALUE + r")")


def parse(text: str) -> "list[tuple[str, str]] | None":
    """Return the verdict's attributes, or None for NO VERDICT."""
    lines = text.split("\n")
    # Trailing blank lines are tolerated, following the `design-multi` marker's
    # own rule (`commands/design-multi.md`: readers "tolerate any whitespace
    # between marker and heading", because Jira's round-trip inserts a blank
    # line there). A shell that appends a newline is transport, not the model
    # speaking again.
    while lines and not lines[-1].strip():
        lines.pop()
    hits = [i for i, line in enumerate(lines) if TOKEN.match(line)]
    if not hits:
        return None
    last = hits[-1]
    if last != len(lines) - 1:
        return None
    attributes = TOKEN.match(lines[last]).group(2)
    return [(m.group(1), m.group(2)) for m in ATTRIBUTE.finditer(attributes)]


def main(argv: "list[str]") -> int:
    if len(argv) > 2:
        sys.stderr.write("usage: lane-step [transcript-file]\n")
        return 2
    if len(argv) == 2 and argv[1] != "-":
        with open(argv[1], encoding="utf-8") as handle:
            text = handle.read()
    else:
        text = sys.stdin.read()
    verdict = parse(text)
    if verdict is None:
        return NO_VERDICT
    for key, value in verdict:
        print("%s=%s" % (key, value))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
