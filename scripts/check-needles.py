#!/usr/bin/env python3
"""Assert that every hard-won fact absorbed into the plugin artifacts is still there.

These artifacts are prose, and prose has no compiler. The failure this guards is a
*good-faith* edit: someone trims a paragraph, tightens a sentence, or restructures a
file, and a fact that cost a production incident to learn leaves with it. Nothing goes
red. `validate-plugins.py` still passes, every artifact still loads, the description is
still under the cap — the file is simply, quietly, missing a rule it used to carry, and
nobody finds out until the same defect ships a second time.

So each entry in `needles.json` pins one absorbed fact to a short, distinctive literal
string: a coined term, a literal command, a measured number, a noun phrase that could
only survive if the fact survives. If the needle is gone, the fact is gone.

**Presence is asserted in the corpus, not in a file.** A needle passes if it appears at
least once anywhere under `plugins/**/*.md`. That is deliberate and it is the whole point
of the gate. These artifacts are actively restructured — fleet-provisioning prose moves
out of `commands/start-multi.md` into an agent, the four facts every trigger falls out of
were lifted into `EVIDENCE.md` so six artifacts stop restating them — and a per-file
assertion would fire on every one of those moves. It would then be *right* to silence,
which is how a gate dies. Corpus-wide presence lets content relocate freely while proving
the moving truck did not drop anything: a fact that walked from one file into another is
green, a fact that walked out of the repo is red.

The `file:` field opts a single needle back into a per-file assertion, for the rare case
where the location *is* the fact — `EVIDENCE.md`'s numbered headings, which six artifacts
cite as "§1" and "§3". Reach for it almost never; it re-introduces exactly the brittleness
the default avoids.

An absent `needles.json`, an unparseable one, or one with no needles is an ERROR. A gate
whose data file went missing must not report success — that is the same silent-absence
failure one layer up.

Run locally:  python3 scripts/check-needles.py
Positive control (prove it can fire) against a throwaway copy of the corpus:
              python3 scripts/check-needles.py /tmp/corpus-copy/plugins
Exit code is non-zero if any needle is missing, so CI fails the PR.
"""

import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEEDLES = ROOT / "scripts" / "needles.json"

# The corpus root. Overridable so the gate can be positive-controlled against a mutated
# *copy* — proving a deleted fact is actually caught, rather than trusting a check that
# has never been seen to fire. Never point this at the real tree to "test" a deletion.
CORPUS_ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("NEEDLE_CORPUS_ROOT", ROOT / "plugins"))

# A needle this short cannot be distinctive; it would pass by accident and prove nothing.
NEEDLE_MIN_LEN = 4

# A needle matching this many lines is a smell in the other direction: it is common enough
# that its survival says little about the fact's survival. Warn, don't fail — a genuinely
# cross-cutting phrase (a rule restated in six artifacts) legitimately matches often.
MATCH_WARN = 12

errors: list[str] = []
warnings: list[str] = []


def rel(p: pathlib.Path) -> str:
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p)


def corpus_rel(p: pathlib.Path) -> str:
    """A corpus file's path as the needles file spells it (`plugins/…`).

    Relative to the corpus root's *parent*, not to ROOT: under the positive control the
    corpus is a copy living outside the repo, and reporting absolute scratch paths — or
    worse, failing a `file:` pin because of where the copy sits — would make the control
    run disagree with the real one for no reason."""
    try:
        return str(p.relative_to(CORPUS_ROOT.parent))
    except ValueError:
        return rel(p)


def load_needles() -> tuple[list[dict], dict]:
    """Read needles.json. Every failure here is an error — a gate that cannot find its
    own data file has no verdict to give, and reporting success would be the exact
    failure-by-absence this script exists to catch."""
    if not NEEDLES.is_file():
        errors.append(f"{rel(NEEDLES)}: not found — the gate has no facts to assert, which is not a pass.")
        return [], {}
    try:
        data = json.loads(NEEDLES.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        errors.append(f"{rel(NEEDLES)}: invalid JSON — {e}")
        return [], {}

    entries = data.get("needles") if isinstance(data, dict) else None
    if not isinstance(entries, list) or not entries:
        errors.append(f"{rel(NEEDLES)}: no `needles` array, or it is empty — an empty gate is not a green gate.")
        return [], {}

    sources = data.get("_sources", {}) if isinstance(data, dict) else {}
    return entries, sources


def load_corpus() -> dict[pathlib.Path, list[str]]:
    """Every markdown file under the corpus root, split into lines.

    Line-oriented on purpose: a needle is a phrase that lives on one line, so matching
    per line refuses an accidental match spanning a paragraph break in a hard-wrapped
    file, and gives a file:line to report."""
    return {p: p.read_text(encoding="utf-8").splitlines() for p in sorted(CORPUS_ROOT.rglob("*.md"))}


def provenance(entry: dict, sources: dict) -> str:
    """The trail a maintainer follows from a red gate back to why the fact exists."""
    bits = []
    issue = entry.get("issue")
    if issue:
        bits.append(f"issue #{issue}")
    commit = entry.get("commit")
    if commit:
        closes = (sources.get(commit) or {}).get("closes") or []
        closed = f" — closes {' '.join('#' + str(n) for n in closes)}" if closes else ""
        bits.append(f"absorbed by `git show {commit}`{closed}")
    was_in = entry.get("was_in")
    if was_in:
        bits.append(f"last pinned in {was_in} (a hint, not an assertion — it may have legitimately moved)")
    return "\n      ".join(bits)


def main() -> int:
    entries, sources = load_needles()
    if errors:
        report(0, 0)
        return 1

    if not CORPUS_ROOT.is_dir():
        print(f"corpus root does not exist: {CORPUS_ROOT}", file=sys.stderr)
        return 1

    corpus = load_corpus()
    if not corpus:
        errors.append(f"{CORPUS_ROOT}: no .md files found — nothing to assert against, which is not a pass.")
        report(0, 0)
        return 1

    seen: set[str] = set()
    checked = 0

    for i, entry in enumerate(entries):
        needle = entry.get("needle") if isinstance(entry, dict) else None
        if not isinstance(needle, str) or not needle.strip():
            errors.append(f"{rel(NEEDLES)}: entry {i} has no non-empty `needle` string.")
            continue
        if not (entry.get("note") or "").strip():
            errors.append(f"{rel(NEEDLES)}: needle {needle!r} has no `note` — a red gate must say what it guards.")
        if len(needle) < NEEDLE_MIN_LEN:
            errors.append(
                f"{rel(NEEDLES)}: needle {needle!r} is {len(needle)} chars — too short to be distinctive; "
                f"it would pass by accident and prove nothing."
            )
            continue
        if needle in seen:
            errors.append(f"{rel(NEEDLES)}: needle {needle!r} is listed twice — the second entry's note is unreachable.")
            continue
        seen.add(needle)
        checked += 1

        hits = [(p, n) for p, lines in corpus.items() for n, line in enumerate(lines, 1) if needle in line]

        if not hits:
            errors.append(
                f"MISSING from the corpus: {needle!r}\n"
                f"      guards: {entry['note']}\n"
                f"      {provenance(entry, sources)}"
            )
            continue

        if len(hits) > MATCH_WARN:
            warnings.append(
                f"needle {needle!r} matches {len(hits)} lines — common enough that its survival "
                f"says little about the fact's. Consider a more distinctive phrase."
            )

        pinned = entry.get("file")
        if pinned and not any(corpus_rel(p) == pinned for p, _ in hits):
            found = ", ".join(sorted({corpus_rel(p) for p, _ in hits})[:3])
            errors.append(
                f"MOVED out of its pinned file: {needle!r}\n"
                f"      guards: {entry['note']}\n"
                f"      pinned to {pinned} because its location is the fact; found instead in {found}.\n"
                f"      {provenance(entry, sources)}"
            )

    report(checked, len(corpus))
    return 1 if errors else 0


def report(checked: int, files: int) -> None:
    if warnings:
        print(f"\n! {len(warnings)} warning(s):\n", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)

    if errors:
        print(f"\n✗ {len(errors)} problem(s) across {checked} needle(s) / {files} file(s):\n", file=sys.stderr)
        for e in errors:
            print(f"  {e}\n", file=sys.stderr)
        # Only for a genuinely absent fact. A malformed needles.json is a different
        # problem and does not want this advice.
        if not any(e.startswith(("MISSING", "MOVED")) for e in errors):
            return
        print(
            "Each needle above pins a fact that was absorbed from a real failure. A needle goes\n"
            "missing when an edit deleted the fact along with the words carrying it — which is\n"
            "silent everywhere else, because prose has no compiler.\n"
            "\n"
            "The fix is almost never to delete the entry. Restore the fact (it may have moved to\n"
            "another artifact — presence is asserted corpus-wide, so a move is already green), or,\n"
            "if the fact genuinely no longer applies, remove the needle in the same commit that\n"
            "removes the fact and say why in the commit message.\n",
            file=sys.stderr,
        )
        return

    print(f"✓ {checked} needles present across {files} corpus files ({rel(CORPUS_ROOT)})")


if __name__ == "__main__":
    sys.exit(main())
