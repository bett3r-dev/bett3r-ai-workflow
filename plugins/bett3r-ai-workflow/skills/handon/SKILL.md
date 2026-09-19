---
name: handon
description: "Use when resuming from a handoff: locate it, load its frontmatter and the `.work/` artifacts it references, then continue the named status, command, flow step or artifact reference."
---

Resume from a handoff.

**Locate.** With no path, scan `.work/handoff/` and `.work/multi/*/handoff/`. One match resumes directly; several, ask which, newest first; none, ask for a path.

**Load.** Read the handoff; open referenced artifacts as needed: the design at the `design.md` path it cites, or else the folder `work-docs-path --item <work_item>` names (the design has that one location; if neither resolves, say so); `.work/slices.yaml`; the branch's commits; ADRs. Continue from `status`, honouring `skill-runbook` conditions before inventing a path. A bare `/command` in `status` or the runbook is ambiguous where the host repo has one by that name: prefer the plugin's and say which you picked.

**Place yourself in the flow.** A `flow` block means a pipeline step: confirm the prior steps' state is intact (branch, slice commits, committed design, `.work/`), re-read `.work/slices.yaml` for what already `passes: true` (the flow is idempotent, so done work is skipped), and carry the next-step commitment to the next command as a forecast to reconcile, not a settled contract.

## Everything the handoff measured has expired

Re-derive before planning around it:

- A conflict inventory: re-run `git merge-tree` against the current `origin/<default>` immediately before each merge and diff it against the claim; in a stacked integration every merge invalidates the inventory for every remaining branch. `merge-tree`'s verdict is its exit status, since it prints a tree even when conflicted.
- A `.work/` occupancy or collision warning: for every ticket it names, `git log --all --grep=<ID>` and `grep -c "passes: true"` on the referenced `slices.yaml`; report the verdict rather than acting on the imperative, and preserve any unprocessed `learnings.md` buffer first.
- A recorded `agentId`: verify reachability, and fall back to a fresh dispatch without treating that as an error.
- An undrained `## Durable` region is a loss in progress, like an undrained `.work/learnings.md`: fold it into an ADR or the PR body now, before continuing.

Done when `status` is being executed and every measured claim above has been re-derived or explicitly set aside.
