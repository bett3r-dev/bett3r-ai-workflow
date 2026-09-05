---
name: handoff
description: "Use when context must be compressed for another session, a context compaction, or an AFK agent: capture certainties, open questions, the next move, a skill runbook, and references — without duplicating existing `.work/` artifacts. Carries the flow's inter-step link (start → design → plan → build → verify-build) so a resumed session knows where it sits in the pipeline."
---

Mine the session for consolidated context. Do not restate artifacts that already exist — `.work/design.md`, `.work/slices.yaml`, the per-slice commits, ADRs, the PR — reference them by path / id / sha.

A handoff is usually the baton for the immediate next move in the flow. The flow is itself the forward projection: `/plan` **rises** the upcoming work as slices and each command hands off to the next, but those forecasts are re-earned — `/build` re-checks each slice, the flow is idempotent and resumable. Do not mine work that has not happened.

1. **Congeal**, into two regions — this split is the format's contract, not a naming convention, because content otherwise lands wherever the writer is looking (in practice, a catch-all "Housekeeping" heading at the end):
  - **`## Durable`** — invariants still true, decisions and accepted tradeoffs (with the rejected options), findings a future session would otherwise re-discover, open questions nobody has taken, known gaps/blind spots. This is exactly the material to fold into ADRs / the PR body before the branch dies — everything in this region must be phrased so it survives that promotion (no "next move" phrasing, no run-local state).
  - **Everything else is ephemeral by default**: next move, dispatch state, slice counts, snapshots, `agentId`s, frontmatter. Capture *known-unknowns* here too — open empirical questions and what execution-time work must close them (a slice's oracle, an unresolved grill branch, a verifier ESCALATE) — unless the question itself is durable (route it to `## Durable` instead).
2. **Route.** Name the next move as a command, a flow step to resume, or a reference into an artifact. Include only runbook entries a future model should actually follow.

  **Emit plugin-qualified command names** — `/bett3r-ai-workflow:verify-build`, not `/verify-build` — in `status`, `flow.prev`, `flow.next` and every `skill-runbook` key. A bare slash name resolves against the **host repo's** namespace, which this plugin cannot see or control, and any repo mid-migration from local commands to the plugin has real files with these exact names still sitting in `.claude/commands/`. The collision is silent: both are invocable, and picking the wrong one runs different instructions. It degrades the handoff as a human artifact too — a reader cannot tell which command produced it. Qualifying costs nothing where there is no collision. (`flow.step` values stay bare; they name pipeline *positions*, not invocable commands.)

  **Anything measured is a snapshot — stamp it and say what invalidates it.** A handoff is at its most confident precisely when it is most stale: computed once, in bulk, by an agent with full context, and read as authoritative by the session that inherits it. Two shapes recur:
  - **A conflict inventory expires on the next sibling merge.** Scope it to the master SHA it was computed against and mark it as expiring — not as a property of the branches. Content on an *unmerged* sibling is invisible to the analysis, so a "zero hand-authored conflicts" generalisation is true only of the branches actually measured; never carry a negative generalisation beyond that set. (One inventory predicted one conflict and the merge produced four, two of them the only ones needing real judgement — and a session planning around the inventory would have handed exactly those to a mechanical resolver.)
  - **Recorded `agentId`s are session-scoped.** "Resume the warm agent, it has the context" fails with `No transcript found` from any new session — which is precisely the situation a handoff exists to serve. Record the same-session precondition alongside any agent map, and **carry the context needed to re-dispatch fresh** (worktree, branch, tip SHA, procedure, invariants). If resuming is merely an optimisation the handoff survives its failure; if it is load-bearing, the handoff is broken by construction.
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

Like the `record` buffer, a handoff lives in disposable `.work/`: consume it with `/handon` before `/start` replaces `.work/`, or fold its `## Durable` region into ADRs / the PR body first — `/handon` should prompt on an undrained `## Durable` region the same way the flow already shouts about an undrained `.work/learnings.md`. Git and the PR are the system of record; the handoff is only the baton.
