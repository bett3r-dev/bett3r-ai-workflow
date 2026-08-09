#!/usr/bin/env python3
"""Refuse a split that ships with nothing asserting its pointer is followed.

Splitting an artifact — moving a rule out into a reference file and leaving a
pointer behind — is how the oversized commands and skills here stay legible. It
also trades one failure mode for another: **a referenced file is only as good as
the reference being followed**, and not one gate in `scripts/` can see that.
They all assert *presence*, corpus-wide and deliberately (`check-needles.py`
exists so content can relocate freely), so a rule that moved behind a pointer
stays green whether the pointer is ever opened or not. That bill has been paid
once already: `EVIDENCE.md` shipped linked from 5 artifacts while needed by 8,
every gate green, because both the link and its absence parse fine.

`scripts/eval/` answers the question those gates cannot — it runs real headless
sessions and asserts which file each one actually *opened*. It is deliberately
not in CI: it costs real money, needs an authenticated `claude` CLI, and is
non-deterministic. This is the CI-safe half. **It runs no session.** It asserts
only that every split *has* a scenario, so a split cannot ship unguarded while
the expensive run stays manual and deliberate.

**A split, mechanically.** A registered entrypoint (`commands/*.md`,
`agents/*.md`, `skills/*/SKILL.md` — the files Claude Code loads by their own
trigger) carrying a relative markdown link to a **non-entrypoint** `.md` under
`plugins/`. That pair is exactly the shape whose loading is uncertain: the
support doc has no trigger of its own, so it is read only if the reader follows
the pointer, and nothing observable in the tree says whether it did.

The boundary is drawn there and not wider:

  * *Entrypoint → entrypoint* is not a split. `/design` linking `/plan` is a
    cross-reference between two files that each load on their own; there is no
    uncertain hop to prove, and counting it would bury the real splits under
    dozens of findings nobody can act on — which is how a gate gets silenced.
  * *Support doc → support doc* is not a split either. Whether that chain is
    reached at all is already the question, and it is asked one level up, at the
    entrypoint that starts it.
  * A link that resolves to nothing is not a split — there is no file to open.
    `check-artifact-links.py` owns that finding; reporting it here too would
    give one defect two voices and no owner.
  * Only real markdown links count, never a backticked path in prose — the same
    boundary `check-artifact-links.py` draws, so the two gates never disagree
    about what a pointer is. Stated as this gate's blind spot rather than left
    implicit: a split whose pointer is written as prose is invisible here. Write
    it as a link and both gates see it.

So this checks the two directions of the same contract:

  1. Every split target is named by the `guards_split` field of at least one
     scenario in `scripts/eval/scenarios.json`. An uncovered target is an ERROR,
     reported with its consumers and with what a scenario for it must assert.
  2. The inverse: a `guards_split` naming a `.md` that is no longer in the
     corpus is a **stale** scenario. It is exercising something that moved or was
     deleted, so it is no longer evidence of anything — and a suite whose green
     includes a scenario pointed at nothing is green about less than it says.
     Warns.

**Its own positive control runs first, every time.** The detector is applied to
`SPECIMENS` — link shapes it must call a split and shapes it must not — before it
judges anything real, and a missing/empty/unparseable `scenarios.json`, or a
corpus that yields zero splits while plainly containing the materials for one, is
an ERROR rather than a pass. A gate that silently checks nothing is worse than no
gate: "a detector that has never been seen to fire is not evidence of calm"
(EVIDENCE.md §1).

**What a green run claims, and what it does not.** It claims a scenario exists
for every split. It does not claim the scenario *passes* — only
`scripts/eval/run-behavioral-eval.py` can say that, and only when someone spends
the money. Coverage is the floor, not the verdict.

Run locally:  python3 scripts/check-eval-coverage.py [root]
`root` defaults to the repo; pass a fixture tree (one carrying `plugins/` and
`scripts/eval/scenarios.json`) to exercise the gate itself.
Exit code is non-zero if any split is unguarded, so CI fails the PR.
"""

import json
import pathlib
import posixpath
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# The globs Claude Code registers, as `validate-plugins.py` spells them. Nested
# references/*.md are support docs — that they are *not* here is the whole point:
# they have no trigger, so reaching them depends on a pointer being followed.
ENTRYPOINT_GLOBS = ("commands/*.md", "agents/*.md", "skills/*/SKILL.md")

# Inline markdown links, same shape as `check-artifact-links.py` reads. Kept
# identical on purpose: the two gates must agree on what a link *is*, or a
# pointer could resolve for one and be invisible to the other.
LINK = re.compile(r"""\[[^\]]*\]\(\s*<?([^)>\s]+)>?(?:\s+["'][^"']*["'])?\s*\)""")

# Any `…​.md` path written inside a `guards_split` string. The field is free-form
# prose by design — `commands/design.md -> skills/esas-design/BOARD-SETUP.md`,
# `agents/executor.md (+ EVIDENCE.md §2)` — so staleness is asked of the paths it
# mentions, not of the sentence around them.
MD_TOKEN = re.compile(r"[A-Za-z0-9_./-]+\.md")

# The detector's own controls, asserted before it is trusted on the real tree.
# `(source, a markdown line as an artifact would write it, the split targets that
# line must yield)`. Whole lines rather than bare link targets on purpose: the
# extraction is half the detector, and a `LINK` edited into never matching is the
# cheapest way for this gate to go permanently, silently green. Resolved against
# the synthetic corpus below, so the control touches no filesystem and can never
# be skipped for being slow.
SPECIMEN_ENTRYPOINTS = frozenset({
    "plugins/p/commands/design.md",
    "plugins/p/commands/plan.md",
    "plugins/p/agents/executor.md",
    "plugins/p/skills/ddd/SKILL.md",
})
SPECIMEN_SUPPORT = frozenset({
    "plugins/p/EVIDENCE.md",
    "plugins/p/README.md",
    "plugins/p/skills/ddd/PATTERNS.md",
})
SPECIMENS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    # The shape this gate exists for, in each spelling the corpus uses.
    ("plugins/p/commands/design.md", "Defer to [the shared rules](../EVIDENCE.md).",
     ("plugins/p/EVIDENCE.md",)),
    ("plugins/p/skills/ddd/SKILL.md", "See [patterns](PATTERNS.md) before writing one.",
     ("plugins/p/skills/ddd/PATTERNS.md",)),
    ("plugins/p/skills/ddd/SKILL.md", "See [patterns](./PATTERNS.md).",
     ("plugins/p/skills/ddd/PATTERNS.md",)),
    ("plugins/p/agents/executor.md", "Read [§2](../EVIDENCE.md#2-the-oracle) first.",
     ("plugins/p/EVIDENCE.md",)),
    # Two links on one line, one of each kind — pins the extraction as well as
    # the classification, since a regex that stops at the first match would drop
    # the split and keep the harmless one.
    ("plugins/p/commands/design.md", "Run [/plan](./plan.md), then apply [the rules](../EVIDENCE.md).",
     ("plugins/p/EVIDENCE.md",)),
    # Entrypoint → entrypoint: both load by their own trigger, nothing to prove.
    ("plugins/p/commands/design.md", "Hand off to [/plan](./plan.md) and [executor](../agents/executor.md).", ()),
    # Source is not registered, so its own reachability is the question, and it
    # is asked one level up. Never counted here.
    ("plugins/p/README.md", "Ships with [the shared rules](./EVIDENCE.md).", ()),
    # Dangling — `check-artifact-links.py`'s finding, not this one's.
    ("plugins/p/commands/design.md", "See [gone](../MISSING.md).", ()),
    # Out of scope entirely: not relative, not markdown, not a file.
    ("plugins/p/commands/design.md", "See [upstream](https://example.com/EVIDENCE.md).", ()),
    ("plugins/p/commands/design.md", "See [the hook](../hooks/user-prompt-submit.sh).", ()),
    ("plugins/p/commands/design.md", "See [step 4](#step-4-open-prs).", ()),
    # A backticked path is not a link, and this gate reads links only — the same
    # boundary `check-artifact-links.py` draws, so the two never disagree about
    # what a pointer is. Named here rather than left implicit: it is this gate's
    # blind spot, and a split written as prose (`see ../EVIDENCE.md`) is invisible
    # to it. Write the pointer as a link and both gates see it.
    ("plugins/p/commands/design.md", "The rules live in `../EVIDENCE.md`.", ()),
)

errors: list[str] = []
warnings: list[str] = []


def rel(p: pathlib.Path) -> str:
    """A corpus path as this repo spells it — `plugins/…`, posix, root-relative."""
    return p.relative_to(ROOT).as_posix()


def is_relative_target(target: str) -> bool:
    """`./x`, `../x`, and a bare `x.md` — the forms these artifacts use. Absolute
    URLs, `mailto:`, in-page `#anchor`s and absolute paths are out of scope."""
    if target.startswith(("./", "../")):
        return True
    if target.startswith(("#", "/")) or re.match(r"\A[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        return False
    return target.split("#", 1)[0].endswith(".md")


def split_target(source: str, target: str, entrypoints: frozenset[str], corpus: frozenset[str]) -> str | None:
    """The split this link makes, or None. The definition, in code.

    Pure — resolution is lexical and existence is asked of `corpus` — so the
    specimens above exercise the same function the real run does, rather than a
    paraphrase of it that can drift."""
    if not is_relative_target(target):
        return None
    if source not in entrypoints:
        return None
    dest = posixpath.normpath(posixpath.join(posixpath.dirname(source), target.split("#", 1)[0]))
    if not dest.endswith(".md") or dest not in corpus:
        return None
    if dest in entrypoints:
        return None
    return dest


def splits_in_line(source: str, line: str, entrypoints: frozenset[str], corpus: frozenset[str]) -> tuple[str, ...]:
    """Every split one line of an entrypoint makes. The detector, whole — both
    halves, so the specimens exercise exactly what the real scan runs."""
    found = (split_target(source, m.group(1), entrypoints, corpus) for m in LINK.finditer(line))
    return tuple(d for d in found if d)


def self_check() -> None:
    """Run the detector over SPECIMENS before it is trusted on real input.

    Everything below this is an absence claim — "no split is unguarded" — and an
    absence claim is evidence only if the probe could have produced a positive.
    A `LINK` regex or a resolution rule edited into never matching would
    otherwise report a fully covered corpus forever, in a covered corpus's
    voice."""
    corpus = SPECIMEN_ENTRYPOINTS | SPECIMEN_SUPPORT
    for source, line, expected in SPECIMENS:
        got = splits_in_line(source, line, SPECIMEN_ENTRYPOINTS, corpus)
        if got != expected:
            errors.append(
                f"SELF-CHECK FAILED on {source}, line {line!r}:\n"
                f"      expected {list(expected) or 'no split'}, got {list(got) or 'no split'}.\n"
                f"      The gate cannot judge this tree — its verdict on every real link is "
                f"unreliable in the same direction, and the reassuring direction is silent."
            )


def load_scenarios(path: pathlib.Path) -> list[dict]:
    """Read scenarios.json. Every failure here is an error: a coverage gate that
    cannot find the thing coverage is measured against has no verdict to give,
    and reporting success would be this repo's own failure-by-absence one layer
    up."""
    if not path.is_file():
        errors.append(
            f"{rel(path)}: not found — there are no scenarios to measure coverage against, "
            f"which is not a pass."
        )
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        errors.append(f"{rel(path)}: invalid JSON — {e}")
        return []

    scenarios = data.get("scenarios") if isinstance(data, dict) else None
    if not isinstance(scenarios, list) or not scenarios:
        errors.append(
            f"{rel(path)}: no `scenarios` array, or it is empty — every split would report "
            f"covered by nothing, and an empty gate is not a green gate."
        )
        return []
    return [s for s in scenarios if isinstance(s, dict)]


def find_entrypoints(root: pathlib.Path) -> frozenset[str]:
    """The registered files, per plugin. Everything else under `plugins/` is a
    support doc — reachable only through somebody's pointer, which is the whole
    question this gate asks."""
    entrypoints: set[str] = set()
    for plugin_dir in sorted(p for p in (root / "plugins").iterdir() if p.is_dir()):
        for glob in ENTRYPOINT_GLOBS:
            entrypoints.update(rel(p) for p in sorted(plugin_dir.glob(glob)))
    return frozenset(entrypoints)


def find_splits(root: pathlib.Path, frozen: frozenset[str], corpus: frozenset[str]) -> tuple[dict[str, dict[str, int]], int]:
    """`({split target: {consumer: link count}}, links read)`.

    Sources are entrypoints only, so the scan covers exactly the files whose
    pointers are followed by a reader who arrived through a trigger."""
    splits: dict[str, dict[str, int]] = {}
    links = 0
    for source in sorted(frozen):
        # Line by line, through the same `splits_in_line` the specimens pin. No
        # fence handling: a pointer inside an example block is still a pointer a
        # reader can follow, and it counts only if it resolves to a real support
        # doc anyway — which bounds a phantom's cost to one extra scenario,
        # against a missed split's cost of a silently unread rule.
        for line in (root / source).read_text(encoding="utf-8").splitlines():
            links += len(LINK.findall(line))
            for dest in splits_in_line(source, line, frozen, corpus):
                splits.setdefault(dest, {}).setdefault(source, 0)
                splits[dest][source] += 1
    return splits, links


def naming_suffix(path: str, corpus: frozenset[str]) -> str:
    """The shortest trailing path fragment that identifies `path` uniquely in the
    corpus — `EVIDENCE.md` where the basename is unambiguous, more of the path
    where it is not.

    This is what a `guards_split` has to contain to count as naming the target.
    Requiring the full repo-relative path would make the field unwritable in the
    shorthand every existing scenario already uses; accepting a bare basename
    unconditionally would let one scenario silently cover two same-named files in
    different plugins."""
    parts = path.split("/")
    for i in range(len(parts) - 1, -1, -1):
        candidate = "/".join(parts[i:])
        if sum(1 for c in corpus if c == candidate or c.endswith("/" + candidate)) == 1:
            return candidate
    return path


def names(text: str, suffix: str) -> bool:
    """Does this `guards_split` name that target? Bounded on both sides so
    `MY-EVIDENCE.md` does not count as `EVIDENCE.md`, while a longer, more
    explicit path (`skills/esas-design/BOARD-SETUP.md`) still does."""
    return re.search(rf"(?<![\w.\-]){re.escape(suffix)}(?![\w\-/])", text) is not None


def prescription(target: str, consumers: dict[str, int], suffix: str) -> str:
    """What the person who just went red has to write. Concrete, because the
    scenario that gets written from a vague instruction is the one that opens the
    file and asserts something the model already knew."""
    plugin_rel = "/".join(target.split("/")[2:])
    shown = plugin_rel if len(plugin_rel) >= len(suffix) else suffix
    lead = max(consumers, key=lambda c: (consumers[c], c))
    lead_rel = "/".join(lead.split("/")[2:])
    return (
        f'Add a scenario to scripts/eval/scenarios.json with\n'
        f'        "guards_split": "{lead_rel} -> {shown}",\n'
        f'        "must_open":    ["{shown}"],\n'
        f"      and a prompt that drops a session into {lead_rel} at the exact situation this\n"
        f"      reference is the answer to. Assert a rule that exists ONLY behind the pointer —\n"
        f"      a `must_state` the model could satisfy from its priors proves nothing, because\n"
        f"      the tool call is the evidence and the answer is not."
    )


def check_coverage(splits: dict[str, dict[str, int]], scenarios: list[dict], corpus: frozenset[str]) -> int:
    """Every split target must be named by some scenario's `guards_split`.
    Returns the number of targets found covered."""
    guards = [(s.get("id") or f"scenario #{i}", str(s.get("guards_split") or "")) for i, s in enumerate(scenarios)]
    covered = 0

    for target, consumers in sorted(splits.items()):
        suffix = naming_suffix(target, corpus)
        if any(names(text, suffix) for _, text in guards):
            covered += 1
            continue
        listed = ", ".join(f"{c} ({n} link{'s' if n > 1 else ''})" for c, n in sorted(consumers.items()))
        errors.append(
            f"{target}: split with no scenario guarding it.\n"
            f"      pointed at by: {listed}\n"
            f"      Nothing proves this pointer is followed. Every other gate is green whether the\n"
            f"      reader opens this file or not — that is what makes them tolerate a move, and\n"
            f"      it is exactly what they cannot tell apart from a rule nobody reads.\n"
            f"      {prescription(target, consumers, suffix)}"
        )
    return covered


def check_stale(scenarios: list[dict], corpus: frozenset[str]) -> None:
    """The inverse. A `guards_split` naming a file the corpus no longer has is a
    scenario testing something that moved or was deleted — it still runs, still
    reports, and is evidence of nothing. Warned rather than failed: the eval
    suite is not in CI, so a stale scenario blocks no one, but a green run that
    quietly includes it is green about less than it claims."""
    for i, scenario in enumerate(scenarios):
        sid = scenario.get("id") or f"scenario #{i}"
        text = str(scenario.get("guards_split") or "").strip()
        if not text:
            warnings.append(
                f"scripts/eval/scenarios.json: `{sid}` has no `guards_split` — it cannot count "
                f"toward any split's coverage, so whatever it proves, it proves invisibly here."
            )
            continue
        for token in MD_TOKEN.findall(text):
            probe = token.lstrip("./")
            if not any(c == probe or c.endswith("/" + probe) for c in corpus):
                warnings.append(
                    f"scripts/eval/scenarios.json: `{sid}` guards `{token}`, which is not in the "
                    f"corpus — the artifact moved or was deleted and the scenario went stale with "
                    f"it. Repoint it at where the content lives now, or drop it; a scenario aimed "
                    f"at nothing is not evidence of anything."
                )


def report(splits: int, covered: int, scenarios: int, entrypoints: int, links: int) -> None:
    if warnings:
        print(f"\n! {len(warnings)} warning(s):\n", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)

    if errors:
        print(
            f"\n✗ {len(errors)} problem(s) across {splits} split(s) / {scenarios} scenario(s):\n",
            file=sys.stderr,
        )
        for e in errors:
            print(f"  {e}\n", file=sys.stderr)
        print(
            "A split is a rule that stopped being read and started being *referred to*, and the\n"
            "reference is only as good as its being followed. No presence gate can see that gap:\n"
            "they assert corpus-wide by design, so a move is green either way. The scenario is the\n"
            "only artifact that asks whether the file was opened — write it in the same pass that\n"
            "makes the split, while you still know what the pointer was for.\n"
            "\n"
            "This gate runs no session. It only refuses the unguarded split; proving the pointer\n"
            "actually holds is `python3 scripts/eval/run-behavioral-eval.py`, run by hand.\n",
            file=sys.stderr,
        )
        return

    # The blind spot goes in the same breath as the verdict (EVIDENCE.md §1): a
    # green here is "a scenario exists", never "the split works".
    print(
        f"✓ {covered}/{splits} splits guarded by {scenarios} scenario(s) — "
        f"{links} links across {entrypoints} entrypoints; self-check: {len(SPECIMENS)} specimens "
        f"({sum(1 for _, _, e in SPECIMENS if e)} yield a split, {sum(1 for _, _, e in SPECIMENS if not e)} must not)\n"
        f"  Coverage only: no session was run. Whether each pointer is actually followed is "
        f"scripts/eval/run-behavioral-eval.py, which costs money and is manual."
    )


def main(argv: list[str]) -> int:
    global ROOT
    if len(argv) > 1:
        ROOT = pathlib.Path(argv[1]).resolve()

    # First, and unconditionally.
    self_check()
    if errors:
        report(0, 0, 0, 0, 0)
        return 1

    plugins = ROOT / "plugins"
    if not plugins.is_dir():
        print(f"no plugins/ directory at {ROOT}", file=sys.stderr)
        return 1

    corpus = frozenset(rel(p) for p in sorted(plugins.rglob("*.md")))
    frozen = find_entrypoints(ROOT)
    entrypoints = len(frozen)
    splits, links = find_splits(ROOT, frozen, corpus)
    scenarios = load_scenarios(ROOT / "scripts" / "eval" / "scenarios.json")

    # Zero splits in a corpus that has the materials for one — registered
    # entrypoints and support docs sitting beside them — means the detector
    # stopped seeing rather than the repo stopped splitting. Reporting a clean
    # sweep there is the reassuring-failing shape: it costs nothing to
    # investigate and is simply believed.
    if not splits and entrypoints and len(corpus) > entrypoints:
        errors.append(
            f"{rel(plugins)}: {entrypoints} entrypoints and {len(corpus) - entrypoints} non-entrypoint "
            f".md file(s), and not one split detected — this gate just checked nothing.\n"
            f"      Either every reference was inlined back (say so in the commit and this line can "
            f"go), or link detection broke and every split in the tree is now unguarded and green."
        )

    covered = check_coverage(splits, scenarios, corpus) if scenarios else 0
    check_stale(scenarios, corpus)

    report(len(splits), covered, len(scenarios), entrypoints, links)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
