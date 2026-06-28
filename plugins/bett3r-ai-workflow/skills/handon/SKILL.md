---
name: handon
description: "Use when resuming from a handoff: locate it, load its frontmatter and referenced `.work/` artifacts, then continue the named status, command, flow step, or artifact reference. A handoff bearing a flow link resumes a step in the pipeline: load the preserved prior state (commits, `.work/design.md`, `.work/slices.yaml`) and treat its next-step commitment as a forecast for the next flow command to reconcile, not assume."
---

Resume from a handoff.

When I give no path, scan `.work/handoff/` (and `.work/multi/*/handoff/` for fleet runs). Resume a single match directly. For several, ask me to choose, sorted by descending modification date. For none, ask for a path.

Read the handoff; load referenced artifacts only as needed (`.work/design.md`, `.work/slices.yaml`, the branch's commits, ADRs). Continue from `status`; honor `skill-runbook` conditions before inventing a path.

If the handoff carries a `flow` block, it is a step in the pipeline: confirm the prior steps' state is intact (the branch, the per-slice commits, and the `.work/` artifacts are preserved for you), re-read `.work/slices.yaml` to see what already `passes: true` (the flow is idempotent — skip done work), and carry its next-step commitment to the next flow command (`/plan`, `/build`, `/verify-build`) as a forecast to reconcile against reality, never as a settled contract.
