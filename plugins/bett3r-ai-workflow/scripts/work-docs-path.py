#!/usr/bin/env python3
"""Name the folder a work item's committed record lives in. One rule, one place.

`/design` writes and commits `<root>/<id>/design.md`, and every reader of the
design reaches it through this script instead of restating the rule in prose.
It resolves a path and says so in ONE line; it creates, writes and commits
nothing — that is the calling command's job.

    WORK-DOCS-PATH:v1 outcome=ok root=<root> id=<id> path=<root>/<id> source=<default|config> exists=<true|false> [owner=<none|self|other|unowned>]
    WORK-DOCS-PATH:v1 outcome=error reason=<reason> [key=value ...]

Read the line, never the exit code alone (ADR-004): 0 for ok, 2 for error, and
no line at all means the script died before concluding. An error line carries
no `path=`, on purpose — a caller that reads `path=` first must find nothing to
write to. Every path printed is relative to the repository root.

Usage (from anywhere inside the repository):

  work-docs-path --item <work_item> [--repo DIR]
  work-docs-path --item <work_item> --owner-branch <branch>   (the writer, `/design`)

The work item is `.work/mode.yaml`'s `work_item:`, passed through untouched —
the calling command never classifies it, re-dates it or rewrites it:

  --item TV1-2400              a Jira key, used as-is                  -> <root>/TV1-2400
  --item '#268'                a GitHub issue (`gh-268` is accepted)  -> <root>/gh-268
  --item 2026-09-12-add-widget no id: the date `/start` ran + a slug   -> <root>/2026-09-12-add-widget
  --item multi-ESAS-93-94      a fleet run id (`run.yaml`'s runId)     -> <root>/multi-ESAS-93-94

  A fleet run id is the lower-case prefix `multi-`, then the unit ids joined
  by `-`, as written: letters (either case) and digits in dash-separated words.
  The folder is the run id exactly, never case-folded. It names the run-level
  folder `/merge-multi` writes decisions.md into. `multi-`, `multi--x`,
  `multi-x-` or `multi-x_y` is reason=malformed-item, and upper-case `MULTI-7`
  stays a Jira key (that shape is checked first).

  A Jira key is upper-case letters/digits/underscore, a dash, digits. A no-id
  work item is `<yyyy-mm-dd>-<slug>`: a real calendar date in exactly that shape
  (reason=malformed-date otherwise), then a slug of lower-case letters and
  digits in dash-separated words (reason=malformed-slug otherwise, a bare date
  included). Anything else (`tv1-2400`, `#abc`, `TV1-`, an undated `add-widget`)
  is reason=malformed-item.

  The date is fixed ONCE, by `/start`, and carried in `work_item:` by every
  later command, so the folder is a pure function of the value: this script
  never reads the clock and never looks for an existing folder. A lookup that
  "resumed" the one existing `<date>-<slug>` folder is how a branch name reused
  months later for unrelated work landed in — and overwrote — the old design.
  The flags that allowed an undated slug and a separate date were removed; a
  caller still passing them gets reason=unknown-flag-<name>.

The repository root is git's top-level for the current directory
(`git rev-parse --show-toplevel`, so a linked worktree resolves to itself), or
--repo DIR used as-is. Outside a repository: reason=not-a-git-repo.

The root is `docs/prs` unless `<repo>/.claude/bett3r-ai-workflow.json` sets
`{"workDocsRoot": "<path>"}` (source=config). That file is this plugin's own —
never another tool's config (ADR-003). A file without the key keeps the
default; a file that is present but unusable is an error, never a silent
default, because a design written under the default is invisible to every
reader configured for the override:

  config-unparseable        not valid JSON (or not readable as UTF-8)
  config-unreadable         present but cannot be read
  config-not-object         JSON, but not an object
  config-root-not-string    workDocsRoot is not a string
  config-root-empty         empty, or normalises to the repository root itself
  config-root-whitespace    contains whitespace (verdict values never do)
  config-root-absolute      an absolute path — the root must be repo-relative,
                            because the folder is committed with the code
  config-root-escapes-repo  a relative path that normalises outside the repo
  config-root-in-work       under `.work/`, which is gitignored: a record
                            there is not committed

The check is lexical (normpath); a symlink inside the repository that points
outside it is not followed.

Ownership (`--owner-branch <branch>`, asked by the writer only). A slug is not
unique over time, and git history cannot say which work item wrote a folder —
a stacked child, a feature that merged an unmerged parent, or a branch cut past
a stale `origin` all reach another item's design through their own commits. So
ownership is recorded IN the artifact: `/design` writes a frontmatter block at
the top of `<path>/design.md` on every pass,

    ---
    work_item: <the work item as .work/mode.yaml records it>
    branch: <the branch that wrote it>
    ---

and this script reads that block and nothing else — no git history. The
verdict gains `owner=`:

  none      the folder does not exist: nothing to own, a fresh write is safe
  self      the header's work_item is this work item AND its branch is exactly
            <branch>. The header value is normalised like --item (`#268` and
            `gh-268` are one issue); a dated id is compared exactly, so a
            header naming an undated slug, or the same slug on another date,
            is another work item. Same branch rule for every kind. A branch
            name deleted and recreated on the SAME day for unrelated work gets
            the same dated id and reads as self: the accepted residual, since
            a day is the date's resolution.
  other     a complete header naming another work item or another branch
  unowned   the folder exists but proves no owner: no design.md, no header on
            line 1, a header never closed, an unparseable line, a duplicated
            key, or an empty/missing work_item or branch (a design written
            before headers existed lands here)

Only `self` licenses an overwrite; `other` and `unowned` both mean stop. The
header grammar is `key: value` lines; other keys are ignored, a value may be
quoted, and ` #…` after a value is a comment (a branch name has no whitespace).
An empty or whitespace-bearing --owner-branch is reason=malformed-owner-branch
(`git branch --show-current` prints nothing on a detached HEAD). Without
--owner-branch the verdict carries no `owner=`, and an error verdict never does.
"""
import datetime
import json
import os
import posixpath
import re
import subprocess
import sys

TOKEN = "WORK-DOCS-PATH:v1"
DEFAULT_ROOT = "docs/prs"
CONFIG = os.path.join(".claude", "bett3r-ai-workflow.json")
KNOWN_FLAGS = ("--item", "--repo", "--owner-branch")

JIRA_KEY = re.compile(r"[A-Z][A-Z0-9_]*-[0-9]+")
GH_ISSUE = re.compile(r"(?:#|gh-)([1-9][0-9]*)")
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
# A fleet run id (`run.yaml`'s `runId:`): the lower-case prefix `multi-`, then
# the unit ids as written — mixed-case letters and digits in dash-joined words.
# Checked after the Jira key and GitHub issue shapes, so `MULTI-7` stays a key.
RUN_ID = re.compile(r"multi-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*")
# A no-id work item: the date half, then (after one dash) whatever claims to be
# the slug. A value that is a date alone, or a date then `-`, is a dated id,
# well-formed or not (`2026-09-12x` is not one: malformed-item).
DATED = re.compile(r"([0-9]{4}-[0-9]{2}-[0-9]{2})(?:-(.*))?", re.S)


class Refusal(Exception):
    def __init__(self, reason, **attrs):
        super().__init__(reason)
        self.reason = reason
        self.attrs = attrs


def verdict(outcome, **attrs):
    parts = [TOKEN, f"outcome={outcome}"]
    parts += [f"{key}={val}" for key, val in attrs.items()]
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return 0 if outcome == "ok" else 2


def parse_flags(args):
    flags, i = {}, 0
    while i < len(args):
        a = args[i]
        if not a.startswith("--"):
            raise Refusal("unexpected-argument")
        if a not in KNOWN_FLAGS:
            raise Refusal(f"unknown-flag-{re.sub(r'[^a-z0-9-]', '', a[2:]) or 'empty'}")
        if i + 1 >= len(args):
            raise Refusal(f"missing-value-{a[2:]}")
        flags[a] = args[i + 1]
        i += 2
    return flags


def work_item_id(flags):
    """The folder name, validated: `.work/mode.yaml`'s work_item, normalised."""
    item = flags.get("--item")
    if item is None:
        raise Refusal("missing-work-item")
    return normalise_item(item)


def normalise_item(item):
    if JIRA_KEY.fullmatch(item):
        return item
    gh = GH_ISSUE.fullmatch(item)
    if gh:
        return f"gh-{gh.group(1)}"
    if RUN_ID.fullmatch(item):
        return item
    dated = DATED.fullmatch(item)
    if dated:
        date, slug = dated.group(1), dated.group(2)
        try:
            datetime.date.fromisoformat(date)
        except ValueError:
            raise Refusal("malformed-date")
        if slug is None or not SLUG.fullmatch(slug):
            raise Refusal("malformed-slug")
        return item
    raise Refusal("malformed-item")


def repo_root(flags):
    if "--repo" in flags:
        repo = flags["--repo"]
        if not os.path.isdir(repo):
            raise Refusal("repo-not-a-directory")
        return repo
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except OSError:
        raise Refusal("not-a-git-repo")
    if r.returncode != 0 or not r.stdout.strip():
        raise Refusal("not-a-git-repo")
    return r.stdout.strip()


def work_docs_root(repo):
    """(root, source) — the configured root, or the default when no key is set."""
    path = os.path.join(repo, CONFIG)
    if not os.path.lexists(path):
        return DEFAULT_ROOT, "default"
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except UnicodeDecodeError:
        raise Refusal("config-unparseable")
    except OSError:
        raise Refusal("config-unreadable")
    try:
        data = json.loads(text)
    except ValueError:
        raise Refusal("config-unparseable")
    if not isinstance(data, dict):
        raise Refusal("config-not-object")
    if "workDocsRoot" not in data:
        return DEFAULT_ROOT, "default"
    raw = data["workDocsRoot"]
    if not isinstance(raw, str):
        raise Refusal("config-root-not-string")
    if raw.strip() == "":
        raise Refusal("config-root-empty")
    if re.search(r"\s", raw):
        raise Refusal("config-root-whitespace")
    if posixpath.isabs(raw) or os.path.isabs(raw):
        raise Refusal("config-root-absolute")
    root = posixpath.normpath(raw)
    if root == ".":
        raise Refusal("config-root-empty")
    if root == ".." or root.startswith("../"):
        raise Refusal("config-root-escapes-repo")
    if root.split("/", 1)[0] == ".work":
        raise Refusal("config-root-in-work")
    return root, "config"


def owner_branch(flags):
    """The asking branch, or None when ownership was not asked for."""
    if "--owner-branch" not in flags:
        return None
    branch = flags["--owner-branch"]
    # Empty is what `git branch --show-current` prints on a detached HEAD: no
    # branch can own anything, and "" must never compare equal to a header.
    if branch == "" or re.search(r"\s", branch):
        raise Refusal("malformed-owner-branch")
    return branch


def header_fields(design):
    """(work_item, branch) from design.md's frontmatter, or None when the file
    carries no complete, well-formed ownership header. Never raises."""
    try:
        with open(design, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return None
    if not lines or lines[0].strip() != "---":
        return None
    fields = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        text = re.sub(r"\s+#.*$", "", line).strip()
        if not text:
            continue
        m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*):(?:\s+(.*))?", text)
        if not m:
            return None
        key, val = m.group(1), (m.group(2) or "").strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
            val = val[1:-1]
        if key in fields:
            return None
        fields[key] = val
    else:
        return None  # never closed
    work_item, branch = fields.get("work_item", ""), fields.get("branch", "")
    if not work_item or not branch:
        return None
    return work_item, branch


def ownership(repo, path, fid, branch):
    """none | self | other | unowned — from `<path>/design.md`'s header only."""
    folder = os.path.join(repo, path)
    if not os.path.isdir(folder):
        return "none"
    fields = header_fields(os.path.join(folder, "design.md"))
    if fields is None:
        return "unowned"
    work_item, header_branch = fields
    try:
        same_item = normalise_item(work_item) == fid
    except Refusal:
        return "other"
    return "self" if same_item and header_branch == branch else "other"


def main(argv):
    try:
        flags = parse_flags(argv[1:])
        fid = work_item_id(flags)
        branch = owner_branch(flags)
        repo = repo_root(flags)
        root, source = work_docs_root(repo)
    except Refusal as r:
        return verdict("error", reason=r.reason, **r.attrs)
    path = f"{root}/{fid}"
    exists = "true" if os.path.isdir(os.path.join(repo, path)) else "false"
    attrs = dict(root=root, id=fid, path=path, source=source, exists=exists)
    if branch is not None:
        attrs["owner"] = ownership(repo, path, fid, branch)
    return verdict("ok", **attrs)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
