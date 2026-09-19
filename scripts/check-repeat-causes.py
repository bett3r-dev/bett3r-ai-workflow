#!/usr/bin/env python3
"""A fix-round cause that keeps recurring must have a DISPOSITION, not a tally.

Every fix round in this flow is already classified before it is dispatched
(`/build` step 3): `oracle-wrong`, `design-silent`, `ripple`, `invariant`,
`mis-routed`, `flake`. Each one is written into the unit's `build-summary.md`.
Then nothing happened to them. The numbers were quoted in retros, and the same
cause produced the same fix round in the next run.

Pocock's `retro` names the missing step, and it is a disposition rule:

    Classify the violation first: a **mechanical** one (a fixed syntactic
    pattern, a banned API, an import shape, a file-location rule) gets a
    deterministic check, full stop... **Default to building the check over
    writing the rule.** Reserve CODING_STANDARDS.md for genuine judgement calls.

So this guard reads the corpus of recorded fix rounds, and refuses when a cause
has recurred at or above REPEAT_AT without an entry in `docs/causes.md` saying
what was DONE about it — a check that now fires, or an explicit judgement that
no check can. Writing the rule down a second time is not a disposition; that is
the outcome this exists to make visible.

Why a guard rather than a paragraph in `/capture-learnings`: the same reason the
rule itself gives. A disposition somebody has to remember to make is not a
control, and this repo's own answer to that is `scripts/`. A ledger entry is
cheap; the thing that makes it happen is that the gate is red until it exists.

WHAT IT READS

  docs/prs/*/build-summary.md — two recorded shapes, both counted:
      fixRounds: [{cause: oracle-wrong, executor: fresh}, ...]
      retries: [design-silent, invariant, "human-authorised: ...", ...]
  A parser that read only the first shape would silently under-count: one unit
  recorded three `invariant` rounds in `retries:` alone. Quoted entries in a
  `retries:` list are not causes (they are human-authorisation notes) and are
  skipped deliberately; a bare token that is not in the taxonomy is an ERROR,
  so the vocabulary cannot drift by typo into a cause nobody counts.

  docs/causes.md — the ledger. One `## <cause>` section per disposed cause:
      - classification: mechanical | judgement
      - check: <repo-relative path>     (mechanical only; must exist)
      - why: <one line>                 (judgement only)
  A `check:` naming a path that does not exist is an ERROR — that is what stops
  the ledger degrading into the prose it was built to replace.

POSITIVE CONTROLS. A guard that reads nothing passes vacuously, and this one
walks a glob over documents nobody compiles. It therefore refuses an empty
corpus, refuses a corpus in which neither recorded shape appears, and runs a
self-check over synthesized specimens (fire + clean) on every invocation, so a
green line is evidence the guard can still go red.

Run locally:  python3 scripts/check-repeat-causes.py
Exit code is non-zero on any error, so the gate fails the PR.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORPUS = ROOT / "docs" / "prs"
LEDGER = ROOT / "docs" / "causes.md"

# `/build` step 3's closed set. A cause outside it is an error, not a new row:
# the tally is only worth acting on if everyone spells the causes the same way.
TAXONOMY = ("oracle-wrong", "design-silent", "ripple", "invariant", "mis-routed", "flake")

# Three occurrences across the whole recorded corpus. Two is a coincidence and a
# disposition written against it is guesswork; three is the pattern the rule is
# about. Raising this hides work; lowering it files noise.
REPEAT_AT = 3

CAUSE_RE = re.compile(r"cause:\s*([a-z][a-z-]*)")
RETRIES_RE = re.compile(r"retries:\s*\[([^\]]*)\]")
SECTION_RE = re.compile(r"^##\s+([a-z][a-z-]*)\s*$", re.MULTILINE)
FIELD_RE = re.compile(r"^\s*-\s*(classification|check|why):\s*(.+?)\s*$", re.MULTILINE)


def causes_in(text):
    """Every recorded cause in one build-summary, both shapes, with its errors."""
    found, bad = [], []
    for name in CAUSE_RE.findall(text):
        (found if name in TAXONOMY else bad).append(name)
    for body in RETRIES_RE.findall(text):
        for raw in body.split(","):
            token = raw.strip()
            # A quoted entry is a human-authorisation note, not a cause.
            if not token or token[0] in "\"'":
                continue
            (found if token in TAXONOMY else bad).append(token)
    return found, bad


def read_ledger(text):
    """{cause: {field: value}} — the sections of docs/causes.md."""
    entries = {}
    bounds = [(m.group(1), m.start(), m.end()) for m in SECTION_RE.finditer(text)]
    for i, (name, _, end) in enumerate(bounds):
        stop = bounds[i + 1][1] if i + 1 < len(bounds) else len(text)
        entries[name] = dict(FIELD_RE.findall(text[end:stop]))
    return entries


def audit(summaries, ledger_text, exists):
    """The whole rule, over data — so the self-check can drive it without files.

    `summaries` is an iterable of (label, text); `exists` answers whether a
    repo-relative path is present, which is what the self-check varies.
    """
    errors = []
    tally = {}
    shapes = {"cause": 0, "retries": 0}
    for label, text in summaries:
        found, bad = causes_in(text)
        if CAUSE_RE.search(text):
            shapes["cause"] += 1
        if RETRIES_RE.search(text):
            shapes["retries"] += 1
        for name in found:
            tally[name] = tally.get(name, 0) + 1
        for name in bad:
            errors.append(f"UNKNOWN CAUSE `{name}` in {label} — not one of {', '.join(TAXONOMY)}")

    ledger = read_ledger(ledger_text)
    for name, entry in sorted(ledger.items()):
        if name not in TAXONOMY:
            errors.append(f"LEDGER names `{name}`, which is not a fix-round cause")
            continue
        kind = entry.get("classification")
        if kind not in ("mechanical", "judgement"):
            errors.append(f"LEDGER `{name}`: classification must be mechanical or judgement")
            continue
        if kind == "mechanical":
            check = entry.get("check")
            if not check:
                errors.append(
                    f"LEDGER `{name}`: classified mechanical and names no `check:` — "
                    "a mechanical cause gets a deterministic check, and 'we wrote it down' is not one"
                )
            elif not exists(check):
                errors.append(f"LEDGER `{name}`: `check: {check}` does not exist")
        elif not entry.get("why"):
            errors.append(f"LEDGER `{name}`: classified judgement and says no `why:`")

    for name, count in sorted(tally.items(), key=lambda kv: (-kv[1], kv[0])):
        if count >= REPEAT_AT and name not in ledger:
            errors.append(
                f"NO DISPOSITION for `{name}` — {count} recorded fix rounds, no entry in "
                f"{LEDGER.relative_to(ROOT)}. Classify it: mechanical gets a deterministic "
                "check, full stop; judgement says why no check can catch it."
            )
    return errors, tally, shapes


SPECIMENS = [
    # (label, summaries, ledger, expected-to-fire)
    ("a thrice-recorded cause with no ledger entry",
     [("a", "fixRounds: [{cause: ripple, executor: fresh}]"),
      ("b", "retries: [ripple, ripple]")], "", True),
    ("the same cause, disposed with a check that exists",
     [("a", "fixRounds: [{cause: ripple, executor: fresh}]"),
      ("b", "retries: [ripple, ripple]")],
     "## ripple\n- classification: mechanical\n- check: scripts/real.py\n", False),
    ("a mechanical disposition whose check does not exist",
     [("a", "retries: [ripple, ripple, ripple]")],
     "## ripple\n- classification: mechanical\n- check: scripts/gone.py\n", True),
    ("a mechanical disposition naming no check at all",
     [("a", "retries: [ripple, ripple, ripple]")],
     "## ripple\n- classification: mechanical\n", True),
    ("a judgement disposition with its why",
     [("a", "retries: [ripple, ripple, ripple]")],
     "## ripple\n- classification: judgement\n- why: it is a design call, not a pattern\n", False),
    ("a cause below the threshold needs no entry",
     [("a", "retries: [ripple, ripple]")], "", False),
    ("a misspelled cause is not silently uncounted",
     [("a", "fixRounds: [{cause: oracle_wrong, executor: fresh}]")], "", True),
    ("a quoted human-authorisation note is not a cause",
     [("a", 'retries: [ripple, "human-authorised: ripple ripple ripple"]')], "", False),
]


def self_check():
    """Drive the rule over synthesized specimens. Returns the failures, not a count."""
    bad = []
    for label, summaries, ledger, should_fire in SPECIMENS:
        errors, _, _ = audit(summaries, ledger, lambda p: p == "scripts/real.py")
        if bool(errors) != should_fire:
            bad.append(f"SELF-CHECK `{label}`: expected {'a refusal' if should_fire else 'no refusal'}, "
                       f"got {errors or 'none'}")
    return bad


def main():
    failures = self_check()
    if failures:
        print("✗ the guard's own self-check failed — its verdict on the corpus means nothing:\n",
              file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1

    summaries = [(str(p.relative_to(ROOT)), p.read_text(encoding="utf-8"))
                 for p in sorted(CORPUS.glob("*/build-summary.md"))]
    if not summaries:
        print(f"✗ no build-summary.md under {CORPUS.relative_to(ROOT)} — a guard that reads "
              "nothing is not a guard", file=sys.stderr)
        return 1

    ledger_text = LEDGER.read_text(encoding="utf-8") if LEDGER.exists() else ""
    errors, tally, shapes = audit(summaries, ledger_text, lambda p: (ROOT / p).exists())

    if not shapes["cause"] or not shapes["retries"]:
        errors.append(
            "POSITIVE CONTROL: the corpus no longer contains both recorded shapes "
            f"(`cause:` in {shapes['cause']} file(s), `retries:` in {shapes['retries']}). "
            "One of the two readers is now unexercised and could have rotted silently."
        )

    if errors:
        print(f"✗ {len(errors)} problem(s) across {len(summaries)} build summaries:\n", file=sys.stderr)
        for e in errors:
            print(f"  {e}\n", file=sys.stderr)
        print("A recurring cause is the flow telling you the same thing every run. The rule is\n"
              "to classify it first: a MECHANICAL one — a fixed syntactic pattern, a banned API,\n"
              "an import shape, a file-location rule — gets a deterministic check, full stop, and\n"
              "the ledger names it. Reserve prose for genuine judgement calls, and say why.\n",
              file=sys.stderr)
        return 1

    counted = sum(tally.values())
    repeats = sum(1 for c in tally.values() if c >= REPEAT_AT)
    print(f"✓ {counted} recorded fix rounds across {len(summaries)} build summaries; "
          f"{repeats} cause(s) at or above {REPEAT_AT}, all disposed; "
          f"self-check: {len(SPECIMENS)} specimens "
          f"({sum(1 for s in SPECIMENS if s[3])} fire, {sum(1 for s in SPECIMENS if not s[3])} clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
