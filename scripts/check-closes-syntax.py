#!/usr/bin/env python3
"""Refuse a closing line that claims N issues and closes one.

GitHub's issue-closing keywords bind to exactly **one** reference each. A line
reading `Closes #56 #62 #63 #78 #139` closes `#56`; the other four are parsed as
ordinary mentions — they get a cross-reference link on the issue and stay open.
Nothing warns. The commit is well-formed, the PR merges, every gate is green,
and the only tell is a backlog count nobody had a reason to look at. Seven such
lines shipped in one PR here: 80 references produced 7 closures, 73 issues
stayed open under a PR reporting MERGED, and they were closed by hand afterwards
by someone who happened to count.

That is the reassuring-failing shape `plugins/bett3r-ai-workflow/EVIDENCE.md` §1
names — the identical defect in an *alarming* check costs a minute to
investigate, and in a success check it is simply believed. The correct syntax
repeats the keyword per issue (`Closes #56, closes #62, closes #63`), and this
gate keeps the wrong one out of the two places it lives:

  1. **The commit messages on this branch** (`<merge-base>..HEAD`), which is
     where the defect actually shipped.
  2. **The markdown under this repo**, where such a line is *instructional
     example text*. A command that shows `Closes #12 #13` is how the model
     learns the syntax that produced (1) — the wrong example is the upstream of
     the defect, not a cosmetic copy of it. Every `.md` outside dot-directories
     is read, not just `plugins/**`: a wrong example teaches equally well from
     `docs/` or a README.

**The boundary.** A finding needs both halves of the claim: a closing keyword,
and more than one issue reference bound to it.

    Closes #12                    fine — one keyword, one issue, one closure.
    Closes #12, closes #13        fine — the correct form. Each reference
                                  carries its own keyword, so each one closes.
    Closes #12 #13                FINDING — `#13` is a mention wearing a
    Closes #12, #13               closure's clothes. The comma changes nothing:
    Closes #12 and #13            GitHub stops at the first reference either way.
    Closes #12 (see #13)          fine, deliberately. Once the list is broken by
                                  anything but a separator, the trailing
                                  reference is prose that never claimed to close.

**The one exemption, markdown only.** Writing the rule down requires quoting the
broken form — "`Closes #12 #13` closes #12; write `Closes #12, closes #13`" is
the only shape the rule can take, and a gate that refused it would make the rule
unwriteable. So a markdown line that *also* carries the adjacent correct form is
read as a **contrast** and passes, and the count of such lines is printed with
the verdict rather than hidden. Two unrelated single-keyword quotes on one line
do not qualify: a paragraph that names the defect twice and never shows the fix
is still teaching the defect. Commit messages get no exemption at all — a commit
message has no reason to contrast two syntaxes, so one that quotes the broken
form *is* the broken form.

A bare `#12 #13` on a line carrying **no** closing keyword is **out of scope**,
and that is a decision rather than an oversight. Such a line promises nothing —
a mention that stays a mention is exactly what it says it is, so there is no gap
between what it claims and what it does, and therefore nothing that can fail in
the reassuring direction. Scoping to keyword lines is also what keeps the gate
survivable: this repo's own reports, notes and provenance strings list issue
numbers by the dozen, and a gate that fired on those would be *right* to silence
within a week, which is how a gate dies.

**Its own positive control runs first, every time.** An absence claim is
evidence only if the probe could have produced a positive (§1), so before
judging anything real the detector is run over `SPECIMENS` — malformed lines it
must flag and correct ones it must not — and a disagreement is an error, not a
pass. Without it, a regex edited into never matching would report a clean tree
forever, in the exact voice of a clean tree.

Run locally:  python3 scripts/check-closes-syntax.py [base-ref] [root]
`base-ref` defaults to `origin/master`, falling back to `master`. `root`
defaults to this repo; pointing it at a throwaway checkout runs both halves —
commits and markdown — against a tree you can safely make wrong.
Exit code is non-zero if any malformed line is found, so CI fails the PR.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Every keyword GitHub honours. All three tenses of each verb are live — `fixed`
# in a past-tense body closes exactly as `fixes` does — so a set trimmed to the
# forms this repo happens to use would miss the malformed line that mattered.
KEYWORDS = (
    "close", "closes", "closed",
    "fix", "fixes", "fixed",
    "resolve", "resolves", "resolved",
)

# `#12`, `owner/repo#12`, and the placeholder forms artifacts write in examples
# (`#N`, `#NN`). The placeholders are in on purpose: `Closes #N #M` in a command
# is the wrong syntax being *taught*, which is the case this gate cares most
# about. Uppercase-only, and never case-folded, so `#the` in prose is not a
# reference.
ISSUE_REF = r"(?:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#(?:\d+|[A-Z]{1,3}\d*)"

# A keyword and the one reference it binds to. The separator must be a colon or
# real whitespace — `closes the window` has neither a reference nor a claim, and
# `preclosed #12` is not a keyword, which is what the `\b` on the left is for.
# Case-insensitivity is scoped to the keyword alternation alone; widening it to
# the whole pattern would let `[A-Z]{1,3}` swallow ordinary words.
KEYWORD_REF = re.compile(rf"(?i:\b(?:{'|'.join(KEYWORDS)})\b)(?::|\s)\s*({ISSUE_REF})")

# The list tail: what may follow a bound reference and still be read by a human
# as "…and these too". Separator-or-nothing only. A parenthesis, a full stop, a
# dash, a word — anything else — ends the list, which is the whole of the
# false-positive boundary documented above.
#
# Deliberately *not* anchored with `\A`: this is applied with `.match(line, pos)`,
# and `\A` means the true start of the string regardless of `pos`, so anchoring
# it would make the tail scan match nothing, ever — a gate green on the exact
# line it was written for. `.match()` already anchors at `pos`.
TAIL_REF = re.compile(rf"[ \t]*(?:,|;|&|\+|and\b)?[ \t]*({ISSUE_REF})")

# The correct form, spelled out: a bound reference, a separator, and a reference
# that brought its own keyword. Its presence on a line is what tells a *contrast*
# line — one that quotes the broken form in order to forbid it — apart from one
# that models it. See `is_contrast_line`.
WELL_FORMED_MULTI = re.compile(
    rf"{KEYWORD_REF.pattern}[ \t]*(?:,|;|&|\+|and\b)[ \t]*(?={KEYWORD_REF.pattern})"
)

# The gate's own positive and negative controls, asserted before it judges
# anything. `fires` is what the detector must say about each line.
SPECIMENS: tuple[tuple[str, bool], ...] = (
    ("Closes #56 #62 #63 #78 #139", True),      # the line that cost 73 issues
    ("Closes #12, #13", True),                  # a comma is not a keyword
    ("Fixes #12 and #13", True),                # neither is a conjunction
    ("resolved: #12 #13", True),                # colon form, past tense
    ("Closes #N #M", True),                     # the same defect as an example
    ("Closes owner/repo#12 #13", True),         # cross-repo first reference
    ("Closes #12", False),                      # one keyword, one issue
    ("Closes #56, closes #62, closes #63", False),   # the correct form
    ("Closes #12 (see #13)", False),            # a mention, never claimed closed
    ("Closes #12. Fixes #13", False),           # two claims, each well-formed
    ("Collapsed #12 #13 into one ticket", False),    # no keyword, out of scope
    ("closes the window a redelivery opens", False),  # prose, no reference
)

# The markdown-only contrast exemption, controlled in both directions. `True`
# means the line shows the correct form adjacently and is excused; `False` means
# it does not and stays flagged. An exemption nobody can see firing wrongly is
# how a gate is disabled by a rewording.
CONTRAST_SPECIMENS: tuple[tuple[str, bool], ...] = (
    ("`Closes #12 #13` closes #12 only — write `Closes #12, closes #13`.", True),
    ("Never `Closes #56, #62`; repeat it: `Closes #56, closes #62, closes #63`.", True),
    ("`Closes #56 #62 #63` closes the first and the rest stay open.", False),
    ("A bare `Closes #12 #13` is wrong, and so is `Closes #56, #62`.", False),
)

errors: list[str] = []
warnings: list[str] = []
refs_checked = 0


def rel(p: pathlib.Path, root: pathlib.Path) -> str:
    try:
        return str(p.relative_to(root))
    except ValueError:
        return str(p)


def orphan_refs(line: str) -> tuple[list[str], int]:
    """`(the references this line claims and does not close, how many it names)`.

    An empty first element is a well-formed line, which is what makes the
    caller's "no findings" mean something. The second is reported alongside, so
    a finding reads `4 of 5` — the ratio is the whole defect."""
    global refs_checked
    orphans: list[str] = []
    bound = 0

    for m in KEYWORD_REF.finditer(line):
        bound += 1
        pos = m.end()
        while True:
            tail = TAIL_REF.match(line, pos)
            if not tail:
                break
            orphans.append(tail.group(1))
            pos = tail.end()

    refs_checked += bound + len(orphans)
    return orphans, bound + len(orphans)


def is_contrast_line(line: str) -> bool:
    """Is this a line that quotes the broken form in order to *forbid* it?

    Documenting the rule requires writing the wrong syntax down — "`Closes #12
    #13` closes #12 and leaves #13 open; write `Closes #12, closes #13`" is the
    only shape the rule can take, and a gate that refused it would make the rule
    unwriteable, which is a worse outcome than the false negative below.

    The discriminator is the *adjacent* correct form — a bound reference,
    a separator, then a reference carrying its own keyword. Two unrelated
    single-keyword quotes on one line do not qualify, which matters: a paragraph
    that names the defect twice and never shows the fix is still teaching the
    defect, and stays flagged.

    Its cost, stated rather than hidden: a contrast line could carry a *third*,
    genuinely malformed reference and be excused. That is accepted only here, in
    markdown. Commit messages get no such exemption — a commit message has no
    reason to contrast two syntaxes, so one that quotes the broken form *is* the
    broken form."""
    return bool(WELL_FORMED_MULTI.search(line))


def finding(orphans: list[str], total: int) -> str:
    """The two sentences a reader needs at the moment the gate goes red."""
    named = ", ".join(f"`{o}`" for o in orphans)
    return (
        f"{len(orphans)} of {total} references are NOT closed by this line — {named}. "
        f"The keyword bound to the first reference only; the rest are ordinary mentions, "
        f"which is silent everywhere: the commit is well-formed and the PR still merges. "
        f"Repeat the keyword per issue — `Closes #12, closes #13` — a comma alone does not help."
    )


def self_check() -> None:
    """Run the detector over SPECIMENS before it is trusted on real input.

    A detector that has never been seen to fire is not evidence of calm — and a
    gate over prose is the easy case to break silently, because a regex that
    matches nothing looks exactly like a repo with nothing wrong."""
    for line, should_fire in SPECIMENS:
        fired = bool(orphan_refs(line)[0])
        if fired != should_fire:
            errors.append(
                f"SELF-CHECK FAILED on {line!r}: expected the detector "
                f"{'to fire' if should_fire else 'to stay silent'}, and it did not. "
                f"The gate cannot judge this tree — its verdict on every real line is "
                f"unreliable in the same direction."
            )

    for line, should_excuse in CONTRAST_SPECIMENS:
        if is_contrast_line(line) != should_excuse:
            errors.append(
                f"SELF-CHECK FAILED on the contrast exemption for {line!r}: expected it "
                f"{'to be excused' if should_excuse else 'to stay flagged'}, and it was not. "
                f"An exemption that has drifted either blinds the markdown half entirely or "
                f"makes the rule impossible to write down."
            )


def git(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True, text=True, check=False,
    )


def resolve_base(root: pathlib.Path, requested: str) -> str | None:
    """The requested base, else `master`. A branch cut locally before any fetch
    has no `origin/master`, and refusing there would train people to skip the
    gate; refusing when *neither* resolves is the honest failure."""
    for ref in (requested, "master"):
        if git(root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}").returncode == 0:
            return ref
    return None


def check_commits(root: pathlib.Path, base: str) -> int:
    """Every commit message this branch adds. Returns the number examined.

    The range is `<merge-base>..HEAD`, not `<base>..HEAD`: a branch behind its
    base would otherwise re-judge commits that are not this PR's, and the point
    of the gate is to stop the malformed line *before* it merges, not to
    re-litigate the ones already on master."""
    if git(root, "rev-parse", "--git-dir").returncode != 0:
        errors.append(f"{root}: not a git checkout — the commit half of this gate cannot run at all.")
        return 0

    resolved = resolve_base(root, base)
    if resolved is None:
        errors.append(
            f"cannot resolve the base ref `{base}` (nor `master`).\n"
            f"      In CI this means the checkout is shallow — actions/checkout needs `fetch-depth: 0`.\n"
            f"      Locally, `git fetch origin` first, or name a base ref:\n"
            f"        python3 scripts/check-closes-syntax.py <ref>"
        )
        return 0

    merge_base = git(root, "merge-base", resolved, "HEAD")
    if merge_base.returncode != 0 or not merge_base.stdout.strip():
        errors.append(
            f"no merge base between `{resolved}` and HEAD — unrelated histories, "
            f"so there is no set of commits this branch added to judge."
        )
        return 0

    log = git(
        root, "log",
        "--format=format:%H%x1f%s%x1f%B%x1e",
        f"{merge_base.stdout.strip()}..HEAD",
    )
    if log.returncode != 0:
        errors.append(f"`git log` failed over {resolved}..HEAD — {log.stderr.strip()}")
        return 0

    commits = [r for r in log.stdout.split("\x1e") if r.strip()]
    for record in commits:
        sha, subject, body = (record.strip("\n").split("\x1f", 2) + ["", ""])[:3]
        for n, line in enumerate(body.splitlines(), 1):
            orphans, total = orphan_refs(line)
            if orphans:
                errors.append(
                    f"{sha[:9]} ({subject}), message line {n}:\n"
                    f"      {line.strip()}\n"
                    f"      {finding(orphans, total)}\n"
                    f"      Amend the message while the branch is unmerged; once it has merged the "
                    f"only remedy left is `gh issue close` by hand, one issue at a time."
                )
    return len(commits)


def markdown_files(root: pathlib.Path):
    """Every `.md` in the tree, minus dot-directories (`.git` above all). No
    fence handling: a malformed example inside a ``` block is exactly the
    instructional text this half exists to catch."""
    for p in sorted(root.rglob("*.md")):
        if any(part.startswith(".") for part in p.relative_to(root).parts):
            continue
        yield p


def check_markdown(root: pathlib.Path) -> tuple[int, int]:
    """Instructional example text. Returns `(files examined, lines exempted)`."""
    files = list(markdown_files(root))
    exempted = 0
    for path in files:
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            orphans, total = orphan_refs(line)
            if orphans and is_contrast_line(line):
                exempted += 1
                continue
            if orphans:
                errors.append(
                    f"{rel(path, root)}:{n}: this example teaches the syntax that closes one issue "
                    f"and reads as several.\n"
                    f"      {line.strip()}\n"
                    f"      {finding(orphans, total)}\n"
                    f"      A wrong example in a command is how the model learns the wrong syntax "
                    f"in the first place — fix the example, not just the commits it produced.\n"
                    f"      If the line is *forbidding* this syntax rather than modelling it, show "
                    f"the correct form on the same line (`Closes #12, closes #13`) — that is what "
                    f"marks it as a contrast, and a rule that never shows the fix is half a rule."
                )
    return len(files), exempted


def report(commits: int, files: int, exempted: int = 0) -> None:
    if warnings:
        print(f"\n! {len(warnings)} warning(s):\n", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)

    if errors:
        print(
            f"\n✗ {len(errors)} problem(s) across {commits} commit message(s) / {files} markdown file(s):\n",
            file=sys.stderr,
        )
        for e in errors:
            print(f"  {e}\n", file=sys.stderr)
        print(
            "A closing keyword binds to exactly one reference. `Closes #12 #13` closes #12 and\n"
            "leaves #13 open as a mention — no error, no warning, the commit well-formed and the\n"
            "PR MERGED. The fix is the repeated keyword, not a comma: `Closes #12, closes #13`.\n"
            "\n"
            "And because the merge itself reports success either way, /verify-build asserts the\n"
            "referenced issues actually reached CLOSED after the merge. This gate only stops the\n"
            "malformed line from being written.\n",
            file=sys.stderr,
        )
        return

    # Both counts are part of the verdict, not decoration. "0 closing references"
    # is a green run that judged nothing, and the exemptions are this gate's
    # named blind spot — a verdict that hides how much it declined to judge is
    # the thing EVIDENCE.md §1 refuses (§1: state the blind spot in the same
    # breath as the verdict).
    blind = f"; {exempted} contrast line(s) exempted (markdown only)" if exempted else ""
    print(
        f"✓ {refs_checked} closing reference(s) well-formed across {commits} commit message(s) "
        f"and {files} markdown file(s){blind}; self-check: {len(SPECIMENS)} specimens "
        f"({sum(1 for _, f in SPECIMENS if f)} fire, {sum(1 for _, f in SPECIMENS if not f)} clean) "
        f"+ {len(CONTRAST_SPECIMENS)} contrast controls "
        f"({sum(1 for _, e in CONTRAST_SPECIMENS if e)} excused, "
        f"{sum(1 for _, e in CONTRAST_SPECIMENS if not e)} flagged)"
    )


def main(argv: list[str]) -> int:
    base = argv[1] if len(argv) > 1 and argv[1] else "origin/master"
    root = pathlib.Path(argv[2]).resolve() if len(argv) > 2 else ROOT

    if not root.is_dir():
        print(f"no such root: {root}", file=sys.stderr)
        return 1

    # First, and unconditionally. Everything below is an absence claim.
    self_check()
    if errors:
        report(0, 0)
        return 1

    # The specimens are the gate's own input, not the tree's — leaving their
    # references in the count would make the reported number the one thing it
    # must never be: non-zero on a run that read nothing real.
    global refs_checked
    refs_checked = 0

    commits = check_commits(root, base)
    files, exempted = check_markdown(root)

    if not files:
        errors.append(f"{root}: no .md files found — nothing to assert against, which is not a pass.")

    report(commits, files, exempted)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
