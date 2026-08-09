#!/usr/bin/env python3
"""Check that the cross-references between published artifacts still point somewhere.

`plugins/bett3r-ai-workflow/EVIDENCE.md` exists so a fact is stated once instead
of six times. That trade buys concision with a new failure mode: **a referenced
file is only as good as the reference being followed.** The risk is not
theoretical — EVIDENCE.md shipped linked from 5 artifacts while it was needed by
8, and the three silent omissions were found by a human reading the tree, not by
a gate. Both failure shapes here are *absent* rather than wrong, so nothing
errors at runtime: a dangling link renders as ordinary link text, and a consumer
that forgot to link simply reads as if the shared fact were never written.

So this checks the two things whose failure mode is a missing edge:

  1. Every relative markdown link under `plugins/` resolves to a real path,
     relative to the file that contains it. Renames and moves break these
     silently.
  2. The reference/backlink contract around EVIDENCE.md holds in **both**
     directions: every consumer its own "Referenced by" line declares really
     links to it (the exact 5-of-8 bug), and every command/agent that links to
     it is named on that line (so a new consumer cannot be added without
     updating the manifest, leaving the file's own account of itself stale).

Check 2 fails loudly when it cannot find the manifest line or parses no names
from it. A gate that silently checks nothing is the reassuring-failing shape
EVIDENCE.md §1 warns about: "a detector that has never been seen to fire is not
evidence of calm."

Run locally:  python3 scripts/check-artifact-links.py [root]
`root` defaults to the repo; pass a fixture tree to exercise the gate itself.
Exit code is non-zero if anything is broken, so CI fails the PR.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Inline markdown links: `[text](target)`, tolerating `<…>` around the target
# and a trailing "title". Reference-style and multi-line links are not used in
# these artifacts; if one appears it is simply not checked, never mis-flagged.
LINK = re.compile(r"""\[[^\]]*\]\(\s*<?([^)>\s]+)>?(?:\s+["'][^"']*["'])?\s*\)""")

# A fenced code block opener/closer, per CommonMark: up to three spaces of
# indent, then three or more backticks or tildes.
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")

# Fenced blocks that are *template examples* rather than real documents. The
# four relative links inside SKILL.md's `# Context Map` block show what
# a generated CONTEXT-MAP.md should look like in a consuming repo — `./sales/`,
# `./invoicing/` and friends are the reader's bounded contexts, not paths in
# this repo. Making them resolve would mean rewriting the template to point at
# something real here, which corrupts the example it exists to be.
#
# Keyed by (file, the block's first content line) so the allowlist stays pinned
# to that one block: real links elsewhere in the same file are still checked,
# and if the block is renamed or removed the entry goes stale *loudly* (see
# `stale allowlist` below) instead of quietly blinding a file forever.
TEMPLATE_EXAMPLE_BLOCKS: dict[str, set[str]] = {
    "plugins/bett3r-ai-workflow/skills/domain-modeling/SKILL.md": {"# Context Map"},
}

EVIDENCE_REL = "plugins/bett3r-ai-workflow/EVIDENCE.md"

# The manifest line EVIDENCE.md opens with. Matched on the phrase alone so the
# sentence around it can be reworded freely; the backtick-quoted names on that
# line *are* the manifest, so nothing else on it should be backticked.
REFERENCED_BY = re.compile(r"^.*\breferenced by\b.*$", re.IGNORECASE | re.MULTILINE)
BACKTICKED = re.compile(r"`([^`]+)`")

errors: list[str] = []
warnings: list[str] = []
checked = 0
links_checked = 0
matched_examples: set[tuple[str, str]] = set()


def rel(p: pathlib.Path) -> str:
    return str(p.relative_to(ROOT))


def markdown_links(path: pathlib.Path, text: str):
    """Yield (line number, raw target) for every inline link in the file,
    skipping fenced blocks the template allowlist covers."""
    key = rel(path)
    allowed = TEMPLATE_EXAMPLE_BLOCKS.get(key, set())
    fence: str | None = None
    heading: str | None = None
    skipping = False

    for n, line in enumerate(text.splitlines(), 1):
        m = FENCE.match(line)
        if m:
            marker = m.group(1)
            if fence is None:
                fence, heading, skipping = marker, None, False
                continue
            if marker[0] == fence[0] and len(marker) >= len(fence):
                fence, heading, skipping = None, None, False
                continue
        if fence is not None:
            if heading is None and line.strip():
                heading = line.strip()
                if heading in allowed:
                    skipping = True
                    matched_examples.add((key, heading))
            if skipping:
                continue
        for lm in LINK.finditer(line):
            yield n, lm.group(1)


def is_relative_target(target: str) -> bool:
    """`./x` and `../x` — the forms these artifacts use — plus a bare `x.md`,
    which is the same edge written without the dot. Everything else (absolute
    URLs, `mailto:`, in-page `#anchor`s, absolute paths) is out of scope."""
    if target.startswith(("./", "../")):
        return True
    if target.startswith(("#", "/")) or re.match(r"\A[a-zA-Z][a-zA-Z0-9+.-]*:", target):
        return False
    return target.split("#", 1)[0].endswith(".md")


def resolve(path: pathlib.Path, target: str) -> pathlib.Path:
    """The path a link in `path` points at, anchor stripped."""
    return (path.parent / target.split("#", 1)[0]).resolve()


def check_links(path: pathlib.Path) -> set[pathlib.Path]:
    """Check every relative link in one file; return the set of paths it links
    to, so check 2 can ask who links to EVIDENCE.md without re-parsing."""
    global checked, links_checked
    checked += 1
    targets: set[pathlib.Path] = set()

    for lineno, target in markdown_links(path, path.read_text(encoding="utf-8")):
        if not is_relative_target(target):
            continue
        links_checked += 1
        dest = resolve(path, target)
        targets.add(dest)
        if not dest.exists():
            errors.append(
                f"{rel(path)}:{lineno}: link `{target}` does not resolve — "
                f"no file at {dest}"
            )
    return targets


def artifact_for(name: str) -> pathlib.Path:
    """`/foo` is a command, a bare name is an agent — the two artifact kinds
    EVIDENCE.md's manifest line names."""
    plugin = ROOT / "plugins" / "bett3r-ai-workflow"
    if name.startswith("/"):
        return plugin / "commands" / f"{name[1:]}.md"
    return plugin / "agents" / f"{name}.md"


def name_for(path: pathlib.Path) -> str:
    """The inverse: how the manifest line must spell this artifact."""
    return f"/{path.stem}" if path.parent.name == "commands" else path.stem


def check_evidence_contract(linkers: dict[pathlib.Path, set[pathlib.Path]]) -> int:
    """Assert EVIDENCE.md's self-declared consumer list matches reality both
    ways. Returns the number of declared consumers; 0 only alongside an error."""
    evidence = ROOT / EVIDENCE_REL
    if not evidence.is_file():
        errors.append(
            f"{EVIDENCE_REL}: missing — every artifact that defers its facts to it "
            f"now links into nothing."
        )
        return 0

    m = REFERENCED_BY.search(evidence.read_text(encoding="utf-8"))
    if not m:
        errors.append(
            f"{EVIDENCE_REL}: no `Referenced by …` line — that line is the manifest this "
            f"check reads, so without it the backlink contract is checked against nothing."
        )
        return 0

    declared: dict[pathlib.Path, str] = {}
    for name in BACKTICKED.findall(m.group(0)):
        name = name.strip()
        if not name:
            continue
        declared[artifact_for(name)] = name
    if not declared:
        errors.append(
            f"{EVIDENCE_REL}: the `Referenced by …` line names no backtick-quoted "
            f"artifacts — it parsed to zero consumers, so this check verified nothing. "
            f"Spell each consumer as `/command` or `agent-name`."
        )
        return 0

    # Forward: does every artifact EVIDENCE.md claims actually link back? This is
    # the 5-of-8 bug — the manifest was right, three of the files were not.
    for path, name in sorted(declared.items(), key=lambda kv: kv[1]):
        if not path.is_file():
            errors.append(
                f"{EVIDENCE_REL}: `Referenced by` names `{name}`, which maps to "
                f"{rel(path) if path.is_relative_to(ROOT) else path} — no such artifact."
            )
            continue
        if evidence.resolve() not in linkers.get(path.resolve(), set()):
            errors.append(
                f"{rel(path)}: EVIDENCE.md declares `{name}` a consumer, but this file "
                f"contains no link to EVIDENCE.md — the shared fact never reaches it."
            )

    # Reverse: is every artifact that links to EVIDENCE.md named on that line?
    # Otherwise a consumer is added and the file's own account of itself goes stale.
    declared_paths = {p.resolve() for p in declared}
    for path in sorted(linkers):
        if path.parent.name not in ("commands", "agents"):
            continue
        if evidence.resolve() not in linkers[path]:
            continue
        if path.resolve() not in declared_paths:
            errors.append(
                f"{EVIDENCE_REL}: `{name_for(path)}` links to EVIDENCE.md but is not named "
                f"on its `Referenced by` line — add it, or the manifest understates its reach."
            )

    return len(declared)


def main(argv: list[str]) -> int:
    global ROOT
    if len(argv) > 1:
        ROOT = pathlib.Path(argv[1]).resolve()

    plugins = ROOT / "plugins"
    if not plugins.is_dir():
        print(f"no plugins/ directory at {ROOT}", file=sys.stderr)
        return 1

    linkers = {path: check_links(path) for path in sorted(plugins.rglob("*.md"))}
    consumers = check_evidence_contract(linkers)

    # A stale allowlist is the same reassuring failure as a stale reference: the
    # block it excused is gone or renamed, so it now excuses nothing while
    # reading as deliberate. Say so rather than letting it rot.
    for file, headings in TEMPLATE_EXAMPLE_BLOCKS.items():
        for heading in headings:
            if (file, heading) not in matched_examples:
                errors.append(
                    f"{file}: allowlisted template block `{heading}` was not found — "
                    f"the allowlist entry is stale and is now excusing nothing. Remove it, "
                    f"or fix the heading it is pinned to."
                )

    if warnings:
        print(f"\n! {len(warnings)} warning(s):\n", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)

    if errors:
        print(f"\n✗ {len(errors)} problem(s) across {checked} file(s):\n", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(
            "\nThese failures are silent at runtime — a dangling link renders as text, and "
            "an artifact that never links the shared fact reads as if it were never written.\n",
            file=sys.stderr,
        )
        return 1

    print(
        f"✓ {links_checked} relative links resolve across {checked} artifacts; "
        f"EVIDENCE.md's {consumers} declared consumers all link back, and no undeclared one links in"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
