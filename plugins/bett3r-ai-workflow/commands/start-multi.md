---
description: Fleet orchestrator — drive N work units (tickets) through the full flow in parallel, one git worktree each. Resumable, decision-logged into PRs, draft PRs only.
---

# /start-multi — parallel delivery across worktrees

Drive a **list of work units** through the standard flow in parallel, isolating each in its own git worktree. You (the main session) are the **orchestrator**: you dispatch, verify git state with your own commands, collect escalations, and resume. You do **not** implement.

Run state lives in `.work/multi/<run-id>/run.yaml` — ephemeral, gitignored, and the **resumable** source of truth. Re-running the same set resumes it.

## Argument: $ARGUMENTS
Work-unit ids (+ optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--deps "C:P,..."` | Dependencies (child stacks on parent). The only dep source besides asking once. |
| `--dry-run` | Print the wave / worktree / branch-base plan; cut nothing. |
| `--max-parallel N` | Cap concurrent unit agents (default conservative — see Principles). |
| `--no-pr` | Stop after local per-slice commits; don't push / open PRs. |
| `--gate-design` | Pause after `design` on **every** unit (default: only design-heavy ones). |
| `--serial` | No cross-unit parallelism; run each unit's pipeline yourself, dispatching the real `executor`/`verifier`/`test-runner` agents. The rigor path. |
| `--keep-worktrees` · `--fresh` · `--run-id <id>` | Teardown / resume-state controls. |

## Per-unit pipeline
`start → design → plan → build → verify-build` (the standard flow, unattended). Each unit ends at a pushed **draft** PR whose body is the record.

## Steps

**0 — Acquire & snapshot (the only tracker touch).** Resolve `run-id` (default `multi-` + sorted ids). If `run.yaml` exists and not `--fresh` → **resume** (skip to step 4). Else fetch each unit's content from the tracker **once**, snapshot it into the run dir (agents read the snapshot, never the tracker again). Pin the base: `git fetch origin`; `BASE=$(git rev-parse origin/<default-branch>)`. Mark design-heavy units (description markers, or `--gate-design`). Write `run.yaml`, all units `pending`.

**1 — Deps → waves.** Populate deps from `--deps`, or ask **once** if >1 unit. Topologically sort into waves; detect cycles → stop. Never read tracker links (their direction/coupling is unreliable).

**2 — Worktrees & branches.** Per unit (wave order): pick a **clean** worktree (reuse an unassigned one, else `git worktree add --detach`); one unit per worktree; **never a dirty worktree**. Branch base: independent → `BASE`; stacked → the parent's committed tip. Cut the branch, then **verify the base yourself** — independent: `git -C <wt> rev-list --count HEAD..origin/<default>` must be `0`; stacked: `git -C <wt> merge-base --is-ancestor <parent-tip> HEAD`. `--dry-run` prints the resolved plan and stops here.

**3 — Dispatch.** Process **waves in order**; within a wave launch background agents up to `--max-parallel` (queue the rest). A stacked child waits for its parent's **commit**. Each agent is worktree-scoped, runs the per-unit pipeline against its worktree, and writes **only** its own `<run>/units/<id>.state.yaml`. **Single-writer rule:** only you write `run.yaml` (aggregate the per-unit files) — this prevents concurrent-write races. **Failure isolation:** a unit that fails unrecoverably is marked `failed`, the others continue, and any unit stacked on it becomes `blocked`. (`--serial`: run each unit yourself with the real executor/verifier/test-runner agents — full rigor, no cross-unit parallelism.)

**4 — Collect & resume.** Aggregate per-unit state into `run.yaml`. Resume any `in_progress` (dead agent) or escalated unit from its next incomplete step — the flow is idempotent: slices already `passes: true` and committed are skipped. **Batch escalations** and present them together (`AskUserQuestion`, recommendation first). A **design-heavy** unit stops after `design` — surface its `.work/design.md` for review before it proceeds to `plan`.

**5 — Commit & PR.** Per passed unit, ensure the per-slice commits are in place; then (unless `--no-pr`) run `verify-build` to open the **draft** PR — `--base <parent-branch>` if stacked, else the default branch. Record `prUrl`. A stacked child wave may begin once its parent is committed.

**6 — Teardown.** Remove only worktrees **this run created** whose branch is pushed (or whose unit is terminally `failed` and acknowledged). **Never** remove a pre-existing or dirty worktree. Skip if `--keep-worktrees`.

**7 — Report.** Per unit → branch (+ base/stack) → step reached → PR URL (or why not) → unresolved decisions. Show the stack topology and the merge order. Nothing merged; the tracker is untouched after step 0.

## Decisions → PR body + ADRs
Every non-trivial decision (autonomous **and** escalated), with the **rejected** options, must be preserved so an unattended run never silently bakes in a choice. In this flow that record is the **PR body and ADRs**, not a committed log: keep an ephemeral per-unit decision list in `.work/` during the run, and `verify-build` promotes it into each unit's PR body (and into an ADR when the decision is hard-to-reverse **and** surprising **and** a real trade-off).

## run.yaml (ephemeral, gitignored)
```yaml
runId: multi-...
createdBaseSha: <pinned origin/default>
flags: { gateDesign: false, noPr: false, serial: false, maxParallel: 2, keepWorktrees: false }
deps: [ { child: B, parent: A } ]
units:
  - { id: A, wave: 0, worktree: <path>, worktreeCreated: false, branch: A-slug,
      base: <sha | parent-branch>, stackParent: null, designHeavy: true,
      step: build, status: in_progress, prUrl: null }   # step: pending|start|design|plan|build|verify-build|done
```
Orchestrator is the **sole writer** of `run.yaml`; agents write only `units/<id>.state.yaml`. `step` + `status` + the presence of per-slice commits determine where to resume.

## Principles (lessons baked in)
- **Off the freshly-fetched default branch, verified by you.** Never trust an agent's ahead/behind ("74 ahead" was really 74 *behind*). `--dry-run` previews the resolved bases.
- **Tracker once, then never** — the run is self-contained and resumable.
- **Deps in run.yaml** (from `--deps` / one question), not tracker links.
- **Parallel by wave (capped), sequential across deps;** stacked children wait for the committed parent.
- **Mind the two axes.** Each unit's `build` may itself parallelize independent slices — the across-unit and within-unit axes **multiply**, so keep `--max-parallel` conservative and respect the host repo's sandbox/disk limits.
- **Never clobber a dirty worktree; tear down only what this run created.**
- **Resumable** via run.yaml + idempotent steps + per-slice commits.
- **Draft PRs; push is the last step; nothing merged; the tracker is never transitioned.**
- **No silent decisions** — autonomous and escalated alike ride into the PR body / ADRs with their rejected options.
