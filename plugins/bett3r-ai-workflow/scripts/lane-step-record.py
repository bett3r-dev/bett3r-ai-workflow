#!/usr/bin/env python3
"""Write a step's verdict onto its branch, when the brief asks for it.

The verdict's first sink is stdout (ADR-004), which a caller that owns the
process reads. A caller that does not — a scheduler dispatching the step to a
hosted session — cannot read that stdout through any documented surface, and
inferring the outcome from "did a PR appear" collapses `gate-red` and `infra`,
which have opposite handling. Git is the one channel that survives the venue.

So when `.work/lane.yaml` carries `verdictOnBranch: true`, this commits the
marker line to the branch head as an EMPTY commit and pushes it. The line is
the commit message's final line, byte-for-byte, so the reader is the same
`lane-step` parser run over `git log -1 --format=%B <branch>` — there is no
second grammar and no second parser. (The marker is already a well-formed git
trailer: token `LANE-STEP`, value `v1 step=...`.)

Why a script rather than a sentence in five commands:

  * **The message must end with the marker.** A model composing a commit
    message appends its attribution trailers last, and one `Co-Authored-By:`
    after the marker turns the verdict into NO verdict — the final-line rule,
    working as designed, on a transport where nobody sees the message.
    `scripts/fixtures/lane-step/attribution-after-marker-commit.txt` is that
    shape. Hooks are disabled for the same reason: a `prepare-commit-msg` hook
    can append a trailer too.
  * **An empty commit, even when the step pushed nothing else.** A step that
    ends `blocked-on` before it has any work (a `/plan` with no resolved design)
    otherwise leaves no git artifact, and to a git-only reader "no commit" is
    `infra` — so a real question gets retried as a flaky VM and never reaches
    the human it was blocked on. With this, absence on the branch means exactly
    what absence on stdout means.
  * **It refuses a line the reader cannot read**, rather than durably recording
    `outcome=success.` for a scheduler to classify as infra forever.

When the brief does not ask (the local case — `unit-lane` owns the process),
it does nothing and exits 0, so every step can call it unconditionally.

Usage:  lane-step-record '<the LANE-STEP line>'
Exit 0 = recorded and pushed, or not asked for. Exit 2 = the line is not a
verdict `lane-step` would read; nothing written. Exit 1 = git refused (not a
repo, brief names another branch, staged changes, commit, push or read-back
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


def git(*args, stdin=None):
    return subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", *args],
        input=stdin, capture_output=True, text=True,
    )


def refuse(message):
    sys.stderr.write("lane-step-record: %s\n" % message)
    return 1


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
    subject = "lane-step: %s %s" % (attrs.get("step", "?"), attrs.get("outcome", "?"))
    message = "%s\n\n%s\n" % (subject, line)
    commit = git("commit", "--allow-empty", "--cleanup=verbatim", "-F", "-", stdin=message)
    if commit.returncode != 0:
        return refuse("commit failed: %s" % (commit.stderr.strip() or commit.stdout.strip()))

    # Read back through the reader, so what was written is proven readable.
    body = git("log", "-1", "--format=%B")
    if parse(body.stdout) != verdict:
        return refuse("the recorded commit message does not read back as the same verdict")

    push = git("push", "origin", "HEAD")
    if push.returncode != 0:
        return refuse("committed locally but not pushed, so a remote reader sees no verdict: %s" % push.stderr.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
