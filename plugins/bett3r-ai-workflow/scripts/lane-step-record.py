#!/usr/bin/env python3
"""Write a step's verdict onto its branch, when the brief asks for it.

The verdict's first sink is stdout (ADR-004), which a caller that owns the
process reads. A caller that does not — a scheduler dispatching the step to a
hosted session — cannot read that stdout through any documented surface, and
inferring the outcome from "did a PR appear" collapses `gate-red` and `infra`,
which have opposite handling. Git is the one channel that survives the venue.

So when `.work/lane.yaml` carries `verdictOnBranch: true`, this puts the marker
line on the branch head as the final line of a commit message, byte-for-byte,
and pushes. The reader is the same `lane-step` parser run over
`git log -1 --format=%B <branch>` — there is no second grammar and no second
parser. (The marker is already a well-formed git trailer: token `LANE-STEP`,
value `v1 step=...`.)

Which commit carries it — three paths, in this order (#371):

  * **folded** — HEAD is a commit this step made and has not pushed (no
    remote-tracking ref contains it) and does not already carry a verdict. Its
    message is rewritten with the marker as the final line — after any
    attribution trailers, and any earlier `LANE-STEP:` line dropped — and the
    branch is pushed. Amending an unpushed commit needs no force-push, and this
    script never force-pushes: a hosted venue refuses one, and a commit anyone
    else can see is never rewritten. Merge-commit repos keep every commit a lane
    makes, so an empty verdict commit per step was pure history noise (TV2-21:
    4 of them per run).
  * **skipped** — `/start` or `/plan` ends `success` with nothing unpushed. Such
    a step has no commit to carry the verdict, and none is needed: the delegated
    scheduler (remote-ai-agents `src/delegated/tick.ts`, `classifyBranchVerdict`)
    reads a tip with no verdict as "not concluded" and keeps waiting, and treats
    any later step's non-final `success` as progress, so no step's own verdict
    is required. That is a dependency on the reader, pinned by Seam C2 in
    `scripts/test-flow-seams.sh`; if the reader ever demands one verdict per
    step, this path is what breaks.
  * **empty** — everything else: the step pushed its last commit already
    (`/verify-build`, which must push to open the PR before it knows its
    verdict), or made no commit and did not succeed. A step that ends
    `blocked-on` before it has any work (a `/plan` with no resolved design)
    otherwise leaves no git artifact, and to a git-only reader "no commit" is
    `infra` — so a real question gets retried as a flaky VM and never reaches
    the human it was blocked on.

Why a script rather than a sentence in five commands:

  * **The message must end with the marker.** A model composing a commit
    message appends its attribution trailers last, and one `Co-Authored-By:`
    after the marker turns the verdict into NO verdict — the final-line rule,
    working as designed, on a transport where nobody sees the message.
    `scripts/fixtures/lane-step/attribution-after-marker-commit.txt` is that
    shape, and the folded path repairs it. Hooks are disabled for the same
    reason: a `prepare-commit-msg` hook can append a trailer too.
  * **It reads back what it wrote**, on every path that writes, and refuses a
    line the reader cannot read, rather than durably recording
    `outcome=success.` for a scheduler to classify as infra forever.

When the brief does not ask (the local case — `unit-lane` owns the process),
it does nothing and exits 0, so every step can call it unconditionally.

Usage:  lane-step-record '<the LANE-STEP line>'
Prints `recorded=<folded|empty|skipped> sha=<head>` when the brief asks.
Exit 0 = recorded and pushed, skipped, or not asked for. Exit 2 = the line is
not a verdict `lane-step` would read; nothing written. Exit 1 = git refused (not
a repo, brief names another branch, staged changes, commit, push or read-back
failed); the message says which, and a verdict that did not reach the remote
reads as `infra` to the scheduler — which is the honest reading.
"""

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

_spec = importlib.util.spec_from_file_location("lane_step_parse", os.path.join(HERE, "lane-step-parse.py"))
_parser = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_parser)
parse = _parser.parse

OPT_IN = re.compile(r"verdictOnBranch:\s*true\s*(#.*)?$")
BRANCH = re.compile(r"branch:\s*(\S+)\s*(#.*)?$")
TRAILER = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*:\s*\S")

# Steps that normally commit nothing, whose `success` may leave no verdict.
SKIPPABLE = ("start", "plan")


def git(*args, stdin=None):
    return subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", *args],
        input=stdin, capture_output=True, text=True,
    )


def refuse(message):
    sys.stderr.write("lane-step-record: %s\n" % message)
    return 1


def unpushed_head():
    """True only when no remote-tracking ref contains HEAD. Unsure reads as pushed."""
    refs = git("for-each-ref", "--contains", "HEAD", "--format=%(refname)", "refs/remotes")
    return refs.returncode == 0 and refs.stdout.strip() == ""


def folded(message, line):
    """The message with `line` as its final line, or None when nothing would be left of it."""
    kept = [l for l in message.rstrip("\n").split("\n") if not l.startswith("LANE-STEP:")]
    while kept and not kept[-1].strip():
        kept.pop()
    if not kept:
        return None
    last = []
    for l in reversed(kept):
        if not l.strip():
            break
        last.append(l)
    # Join an existing trailer block rather than open a paragraph after it, so
    # `Co-Authored-By:` stays a trailer. A one-paragraph message is a subject.
    joins_trailers = len(last) < len(kept) and all(TRAILER.match(l) for l in last)
    return "\n".join(kept) + ("\n" if joins_trailers else "\n\n") + line + "\n"


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: lane-step-record '<the LANE-STEP line>'\n")
        return 2
    line = argv[1].strip("\n")
    verdict = parse(line)
    if verdict is None or "\n" in line:
        sys.stderr.write("lane-step-record: not a verdict lane-step would read; nothing written: %r\n" % line)
        return 2

    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        return refuse("not inside a git work tree")
    brief = os.path.join(top.stdout.strip(), ".work", "lane.yaml")
    try:
        with open(brief, encoding="utf-8") as handle:
            fields = handle.read().splitlines()
    except FileNotFoundError:
        fields = []
    if not any(OPT_IN.match(f) for f in fields):
        return 0

    current = git("symbolic-ref", "--quiet", "--short", "HEAD")
    if current.returncode != 0:
        return refuse("HEAD is detached; a verdict needs a branch to live on")
    current = current.stdout.strip()
    named = [m.group(1) for m in (BRANCH.match(f) for f in fields) if m]
    if named and named[0] != current:
        return refuse("the brief names branch %s but HEAD is %s — not recording onto someone else's branch" % (named[0], current))
    if git("diff", "--cached", "--quiet").returncode != 0:
        return refuse("staged changes would ride into the verdict commit; commit or unstage them first")

    attrs = dict(verdict)
    head = git("rev-parse", "--verify", "--quiet", "HEAD^{commit}")
    message = folded(git("log", "-1", "--format=%B").stdout, line) if head.returncode == 0 else None
    fold = (
        message is not None
        and unpushed_head()
        and parse(git("log", "-1", "--format=%B").stdout) is None
    )

    if fold:
        before = git("rev-parse", "HEAD^{tree}", "HEAD^@").stdout
        commit = git("commit", "--amend", "--cleanup=verbatim", "-F", "-", stdin=message)
        if commit.returncode != 0:
            return refuse("amending the step's last commit failed: %s" % (commit.stderr.strip() or commit.stdout.strip()))
        if git("rev-parse", "HEAD^{tree}", "HEAD^@").stdout != before:
            return refuse("the amended commit's tree or parents changed; not pushing it")
        path = "folded"
    elif attrs.get("outcome") == "success" and attrs.get("step") in SKIPPABLE and not (head.returncode == 0 and unpushed_head()):
        print("recorded=skipped sha=%s" % head.stdout.strip())
        return 0
    else:
        subject = "lane-step: %s %s" % (attrs.get("step", "?"), attrs.get("outcome", "?"))
        commit = git("commit", "--allow-empty", "--cleanup=verbatim", "-F", "-", stdin="%s\n\n%s\n" % (subject, line))
        if commit.returncode != 0:
            return refuse("commit failed: %s" % (commit.stderr.strip() or commit.stdout.strip()))
        path = "empty"

    # Read back through the reader, so what was written is proven readable.
    body = git("log", "-1", "--format=%B")
    if parse(body.stdout) != verdict:
        return refuse("the recorded commit message does not read back as the same verdict")

    push = git("push", "origin", "HEAD")
    if push.returncode != 0:
        return refuse("committed locally but not pushed, so a remote reader sees no verdict: %s" % push.stderr.strip())
    print("recorded=%s sha=%s" % (path, git("rev-parse", "HEAD").stdout.strip()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
