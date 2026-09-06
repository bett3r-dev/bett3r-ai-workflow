# bett3r-knowledge-store

A **capture overlay** for the `bett3r-ai-workflow` flow. It ships two hooks, no
commands and no skills, and in a repo that has not opted in it does nothing at
all.

## The invariant this plugin exists to preserve

> **The base flow plugin stays store-agnostic. The store adapts to the flow,
> never the reverse.**

Three tickets (ESAS-85 capture, ESAS-87 extraction, ESAS-92 export freshness)
each needed an invocation point inside the development flow, and all three
attach to the same two events. The obvious implementation — editing
`/verify-build` and `/start-multi` to call a store — was rejected: it would make
every repo using the flow carry store logic it has no use for. Hooks are
per-plugin and additive, so this plugin adds its two events with **zero edits to
any existing command**.

## Opting in: one executable

Everything below the first line of each hook is gated on a single test:

```sh
[ -x "${CLAUDE_PROJECT_DIR:-.}/.knowledge-store/capture" ] || exit 0
```

`.knowledge-store/capture` is a repo-local adapter **you** install. Make it
executable and the repo is configured; delete it and the repo is not. There is
no config file, no environment variable and no registry — the sentinel is the
seam. That is deliberate on both counts:

* **Cost.** A `PreToolUse` hook on `Bash` runs before *every* Bash call in
  *every* repo where the plugin is enabled. One `stat` against a path that does
  not exist is the entire cost in all of them. A config parse at hook start was
  considered and rejected for exactly this reason.
* **Coupling.** This plugin hardcodes no path into esas, no package name and no
  transport. If the capture CLI moves, is renamed or is reimplemented, nothing
  here changes.

### The contract your `capture` must satisfy

It is invoked in exactly two shapes:

```
.knowledge-store/capture worktree-remove <worktree-path> <cwd>
.knowledge-store/capture pr-create       <pr-url>        <cwd>
```

and it must be **idempotent on its second argument**. That argument is the
natural key, and it is a pure function of the invocation — a worktree path as
the user wrote it, or the PR URL `gh pr create` printed. Nothing time-, run- or
session-derived enters it, which is what makes **a double capture free**. A key
carrying a timestamp would make every re-run a new record and the idempotence
claim false.

Exit non-zero to report failure. You will never be able to block the flow by
doing so.

## The two events

| event | fires on | capture is |
| --- | --- | --- |
| `PreToolUse` on `Bash` | tokens `worktree` `remove` adjacent in the runtime command | **synchronous** |
| `PostToolUse` on `Bash` | tokens `gh` `pr` `create` adjacent in the runtime command | **detached** |

**Blocking at teardown, non-blocking at PR create.** Teardown is the
irreversible moment — once `git worktree remove` returns there is nothing left
to read, so a capture racing it is a capture that sometimes loses. PR creation
is neither irreversible nor racing anything: `PostToolUse` fires after the PR
already exists, so waiting would buy nothing but a stall in front of the user.

### Why teardown, and not "the PR was merged"

The originating ticket named "the command that closes the PR". **No such command
exists.** `/verify-build` *opens* PRs, and `gh pr merge`, `--delete-branch`,
`git branch -d` and `git push --delete` return zero matches across the entire
base plugin. The destruction point is `/start-multi` step 7, "Teardown."
Key on *artifacts are about to be destroyed*, never on *merged*.

This threat model fired during the design run that produced the plugin: the
`.work/` census measured 893 files across 6 repos and **101 nine hours later**,
because one fleet worktree holding 818 files was torn down mid-run — destroying
around 30 `*.design-draft.md` and `*.open-forks.md` files with nothing capturing
them.

## Two rules the hooks obey without exception

**Exit 0 on every path.** Claude Code reads a `PreToolUse` hook's exit 2 as
"block this tool call". A hook that threw would cancel the user's command — and
the command it is most likely to cancel is the teardown it exists to protect,
which is worse than not capturing at all. A missed capture costs artifacts; a
non-zero exit costs the command *and* does not save them.

**The match is on the runtime invocation, never on prose.** `git worktree
remove` appears in **no** markdown in the base plugin; `/start-multi` step 7 is
an instruction an agent executes, not a string to grep for. `hooks.json`'s
`matcher` field selects on the **tool name only**:
**there is no command-level matcher in the platform**, whatever a design table
may render it as. So all of the discrimination happens inside the hook, on
`tool_input.command`, tokenised. Not by substring: `git worktree list && echo
remove` contains both words and is not a teardown, and `tool_input.description`
is agent-written prose that can say anything.

## Oracle

`scripts/test-knowledge-store-hooks.sh`, at the repo root, driven in CI under
`sh`, `dash` and `bash`. There is no other runner in this repo that collects
these hooks — `scripts/test-hooks.sh` is hardcoded to the base plugin — so a
change here that the oracle does not cover is a change nothing observes.

## Releasing

The version in `.claude-plugin/plugin.json` is the release contract, not
metadata: the plugin is copied into the version-keyed cache only when that
string changes. See `docs/adr/ADR-001-plugin-version-is-a-release-contract.md`
and `docs/adr/ADR-002-the-knowledge-store-is-a-hook-overlay.md`.
