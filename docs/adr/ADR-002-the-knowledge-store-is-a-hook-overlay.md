# The knowledge store is a hook overlay, not an edit to the flow

Three tickets — ESAS-85 (capture), ESAS-87 (extraction kick) and ESAS-92 (export
freshness) — each needed an invocation point inside the development flow. All
three attach to the same two events, and none of them could land in the `esas`
repo, because the flow commands live here. The obvious implementation was to
edit `/verify-build` and `/start-multi` to call the store. That was rejected,
and this ADR records what was chosen instead and the invariant the choice
protects.

## The invariant

> **The base flow plugin stays store-agnostic. The store adapts to the flow,
> never the reverse.**

A repo that has never heard of the knowledge store must be completely unaffected
by its existence. That is a hard requirement, not a preference: `bett3r-ai-workflow`
is installed in repos that will never run a store, and every line of store logic
inside `/verify-build` would be a line those repos carry, read, and can be
broken by.

## The decision

A **third plugin**, `plugins/bett3r-knowledge-store/`, declaring its own
`hooks/hooks.json` and shipping nothing else — no command, no skill, no agent.
Hooks are per-plugin and additive, so the overlay attaches its two events with
**zero edits to any existing command**. Enabling the store is enabling a plugin;
disabling it is disabling one. Neither is a diff to the flow.

The plugin attaches to two events on the `Bash` tool:

| event | fires on | capture is |
| --- | --- | --- |
| `PreToolUse` | tokens `worktree` `remove` adjacent in the runtime command | synchronous |
| `PostToolUse` | tokens `gh` `pr` `create` adjacent in the runtime command | detached |

## Four things that look like details and are not

**Inert-by-default is one `test`, on line 2, before anything else.** A
`PreToolUse` hook on `Bash` runs before *every* Bash call in *every* repo where
the plugin is enabled — there is no per-directory matcher. The gate is

```sh
[ -x "${CLAUDE_PROJECT_DIR:-.}/.knowledge-store/capture" ] || exit 0
```

which is the discipline `plugins/bett3r-ai-workflow/hooks/esas-pending.sh`
already established for the same reason, copied deliberately rather than
reinvented. A config-file parse at hook start was rejected: it is I/O paid by
every repo that gains nothing from it.

The sentinel doubles as **the seam**. `.knowledge-store/capture` is a repo-local
executable the store installs, invoked in exactly two shapes
(`capture worktree-remove <path> <cwd>` and `capture pr-create <url> <cwd>`).
This plugin therefore hardcodes no path into `esas`, no package name and no
transport, and the dependency on ESAS-85's CLI is satisfied by an interface
rather than by a location. That is what lets this ticket land while ESAS-85 is
still open.

**Exit 0 on every path, always.** Claude Code reads a `PreToolUse` hook's exit 2
as "block this tool call". A hook that threw would cancel the user's command —
and the command it is most likely to cancel is the `git worktree remove` it
exists to protect, which is strictly worse than not capturing at all. A missed
capture costs artifacts; a non-zero exit costs the command *and* does not save
them. So there is no `set -e`, no `set -u`, no unguarded read, and no exit
status but 0, including on malformed input and an unreachable store.

**Teardown, not "merged".** The originating ticket named "the command that
closes the PR (`/verify-build` or its successor)". No such command exists.
`/verify-build` *opens* PRs, and `gh pr merge`, `--delete-branch`,
`git branch -d` and `git push --delete` return zero matches across the entire
base plugin at `74d6723`. The real destruction point is `/start-multi` step 7,
"Teardown." The rule is to key on *artifacts are about to be destroyed*, never
on *merged* — and a matcher aimed at `gh pr merge` would have fired never, with
nothing to show that it had not.

This threat model fired during the design run that produced the plugin. The
`.work/` census measured 893 files across 6 repos and **101 nine hours later**,
because a fleet worktree holding 818 files was torn down mid-run, destroying
around 30 `*.design-draft.md` and `*.open-forks.md` files with nothing capturing
them.

**Blocking at teardown, non-blocking at PR create.** Teardown is the
irreversible moment: once `git worktree remove` returns there is nothing left to
read, so a capture racing it is a capture that sometimes loses. `PostToolUse`
fires after the PR already exists, so waiting there buys nothing but a stall in
front of the user. The asymmetry is the decision, not an inconsistency.

## What the matcher is, mechanically

`hooks.json`'s `matcher` field selects on the **tool name** (`Bash`) and nothing
else. There is no command-level matcher in the platform. Every rendering of this
design as a table with a "matcher" column reading *"runtime command matches
`git worktree remove`"* describes a mechanism that does not exist; written into
`hooks.json` as a regex it would match no tool and fire never. All of the
discrimination therefore happens **inside the hook**, on `tool_input.command`,
tokenised.

Tokenised, and not by substring, for two measured reasons: `git worktree list &&
echo remove` contains both words and is not a teardown, and
`tool_input.description` is agent-written prose that can say "run git worktree
remove on the stale lane" without anything being removed. Matching the raw
payload sees both. Both are cases in the oracle.

**`git worktree remove` appears in no markdown in the base plugin** — zero hits
across `plugins/`, `docs/` and `scripts/` at `74d6723`. `/start-multi` step 7 is
an instruction an agent executes, not a string to grep for. This is why the
match can only be made at runtime, and why no amount of reading the flow's prose
would have found it.

## The natural key, and why idempotence is free

Each capture's second argument is a natural key: the worktree path as written,
or the PR URL `gh pr create` printed. Both are pure functions of the invocation
— nothing time-, run- or session-derived enters either — so the same event
captured twice produces byte-identical argv and the store dedups on its own key.
A key carrying a timestamp would make every re-run a new record and the
idempotence claim false, which is why the oracle asserts argv identity across
two runs rather than asserting that the store deduped.

## The gate this shipped with, and why it had to

`scripts/test-hooks.sh` is hardcoded to `plugins/bett3r-ai-workflow` and to two
named scripts inside it. **No runner in this repo collected a
`bett3r-knowledge-store` hook**, so this plugin could have shipped with every
check on `validate-plugins.yml` green — and green *correctly*, since none of
those checks observes an artifact that did not exist when they were written.

So `scripts/test-knowledge-store-hooks.sh` ships with the plugin and is wired
into the workflow next to the existing hook step, under `sh`, `dash` and `bash`.
It was positive-controlled before being trusted: deleting the line-2 sentinel,
replacing the tokenised match with a substring match, and detaching the teardown
capture each produced a red suite naming the right case. **A gate list is a list
of runners, not a map of what they observe**, and the difference is invisible
from a green run.

## Releasing

`plugins/bett3r-knowledge-store/.claude-plugin/plugin.json` starts at `0.1.0`.
Per ADR-001 that string is the release contract: the plugin is copied into the
version-keyed cache only when it changes, so any later change to anything under
`plugins/bett3r-knowledge-store/**` — the README included — must bump it or it
reaches nobody. `check-plugin-version-bump.sh` exempts this PR because the
plugin is new against the base and has no previous version to differ from.

`.claude-plugin/marketplace.json` gains the third entry and its `metadata.version`
goes `0.27.0` → `0.28.0`. Per ADR-001 that bump is **repo convention and nothing
more**: it pins no plugin version and propagates nothing, because the marketplace
checkout refreshes by `git pull` regardless of that field. It is recorded here in
that direction on purpose — the failure ADR-001 documents is somebody bumping
`metadata.version` alone and being unable to work out why nothing moved.

## Considered options

- **Edit `/verify-build` and `/start-multi` directly.** The shortest diff and the
  one that breaks the invariant outright: every repo using the flow would carry
  store logic, and the store's failure modes would become the flow's.
- **Fork the base plugin.** Two things to maintain and guaranteed drift; the
  fork stops receiving flow improvements the day it is cut.
- **A wrapper command, `/verify-build-ks`, referencing the base one.** Forces the
  user to type a namespaced command, and silently diverges the moment the base
  command changes — the divergence being silent is the disqualifying part.
- **A `.esas/`-style sentinel without the exit-0 discipline.** The sentinel is
  the cheap part; the discipline is the load-bearing part. A throwing
  `PreToolUse` hook cancels the command it was meant to protect.
- **Git hooks.** `git config core.hooksPath` is empty in the working tree that
  motivated this — `.githooks/` exists and is not active — so a git hook would
  have been a capture that never ran, reporting nothing.
