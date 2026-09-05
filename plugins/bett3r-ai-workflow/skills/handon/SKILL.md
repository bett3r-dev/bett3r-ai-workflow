---
name: handon
description: "Use when resuming from a handoff: locate it, load its frontmatter and referenced `.work/` artifacts, then continue the named status, command, flow step, or artifact reference. A handoff bearing a flow link resumes a step in the pipeline: load the preserved prior state (commits, `.work/design.md`, `.work/slices.yaml`) and treat its next-step commitment as a forecast for the next flow command to reconcile, not assume."
---

Resume from a handoff.

When I give no path, scan `.work/handoff/` (and `.work/multi/*/handoff/` for fleet runs). Resume a single match directly. For several, ask me to choose, sorted by descending modification date. For none, ask for a path.

Read the handoff; load referenced artifacts only as needed (`.work/design.md`, `.work/slices.yaml`, the branch's commits, ADRs). Continue from `status`; honor `skill-runbook` conditions before inventing a path.

If the handoff carries a `flow` block, it is a step in the pipeline: confirm the prior steps' state is intact (the branch, the per-slice commits, and the `.work/` artifacts are preserved for you), re-read `.work/slices.yaml` to see what already `passes: true` (the flow is idempotent — skip done work), and carry its next-step commitment to the next flow command (`/plan`, `/build`, `/verify-build`) as a forecast to reconcile against reality, never as a settled contract.

**Everything the handoff measured has expired — re-derive before you plan around it.**

- **Re-run `git merge-tree` against the current `origin/<default>` immediately before each merge**, and diff the result against the handoff's claim. In a stacked integration *every merge invalidates the inventory for every remaining branch*. Treat any new conflict — a hand-authored one especially — as a signal to re-scope that merge, not to proceed on the inherited plan. Note `merge-tree`'s verdict is its **exit status**, not its output: it prints a tree even when conflicted.
- **Verify agent reachability before planning around it**, and fall back to a fresh dispatch without treating that as an error. Recorded `agentId`s do not survive the session that spawned them.
- **A bare `/command` in a `status` or runbook is ambiguous** where the host repo also has a command by that name. Prefer the plugin skill and say which you picked, rather than silently choosing.
- **An undrained `## Durable` region is a loss in progress**, the same way an undrained `.work/learnings.md` is: if the handoff still has one, fold it into an ADR or the PR body now, before continuing — it will not survive `.work/` being replaced.
