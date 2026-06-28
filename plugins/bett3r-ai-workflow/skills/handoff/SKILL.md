---
name: handoff
description: "Use when context must be compressed for another session, a context compaction, or an AFK agent: capture certainties, open questions, the next move, a skill runbook, and references — without duplicating existing `.work/` artifacts. Carries the flow's inter-step link (start → design → plan → build → verify-build) so a resumed session knows where it sits in the pipeline."
---

Mine the session for consolidated context. Do not restate artifacts that already exist — `.work/design.md`, `.work/slices.yaml`, the per-slice commits, ADRs, the PR — reference them by path / id / sha.

A handoff is usually the baton for the immediate next move in the flow. The flow is itself the forward projection: `/plan` **rises** the upcoming work as slices and each command hands off to the next, but those forecasts are re-earned — `/build` re-checks each slice, the flow is idempotent and resumable. Do not mine work that has not happened.

1. **Congeal.**
  - Capture *known-knowns*: the original request / ticket, decisions and accepted tradeoffs (with the rejected options), deferrals, sequence requirements, and artifact paths (`.work/design.md`, `.work/slices.yaml`, branch, commits, ADRs).
  - Capture *known-unknowns*: open questions and what empirical or execution-time work must close them (a slice's oracle, an unresolved grill branch, a verifier ESCALATE).
2. **Route.** Name the next move as a command, a flow step to resume, or a reference into an artifact. Include only runbook entries a future model should actually follow.
3. **Stamp.**
  ```yaml
  ---
  readonly: true
  origin: "<`{skill}` | conversation> (<session-id>)"
  status: "<the next move, in your words: a command to run (`/plan`, `/build`), a flow step to resume (`/build` at slice N), or @<artifact ref: slice id / commit / design section>>"
  flow: # only mid-pipeline; links this handoff into the sequence
    step: "<start | design | plan | build | verify-build | capture-learnings>"
    prev: "<prior step or handoff slug, or ~>"
    next: "<next projected step, or ~>"
  skill-runbook:
    - `{skill}`: "<condition>"   # e.g. grill / critique / domain-modeling / vertical-slicing / record
  ---
  ```
  The `flow` block must let a resumed session resolve its place in the pipeline: the step it is at, the prior steps whose `.work/` state and commits are preserved for it, and the projected next step. The sequence is soft and resumable: the flow re-checks (slices already `passes: true` are skipped), so re-entering may add, drop, or reorder the remaining work.
4. **Finish.** Persist `.work/handoff/<slug>.md` (create `.work/handoff/` if missing — `.work/` is gitignored and ephemeral). Derive `<slug>` from the ticket id or a concise description. In a `/start-multi` fleet run, nest it under the unit: `.work/multi/<run-id>/handoff/<unit>.md`.

Like the `record` buffer, a handoff lives in disposable `.work/`: consume it with `/handon` before `/start` replaces `.work/`, or fold its durable conclusions into ADRs / the PR body first. Git and the PR are the system of record; the handoff is only the baton.
