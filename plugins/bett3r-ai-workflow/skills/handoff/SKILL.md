---
name: handoff
description: "Use when context must be compressed for another session, a compaction or an AFK agent: certainties, open questions, the next move, a skill runbook, references, and the flow's inter-step link."
---

Write `.work/handoff/<slug>.md`, the slug from the ticket id or a short description; in a `/start-multi` fleet, `.work/multi/<run-id>/handoff/<unit>.md`. Create the directory if missing; `.work/` is gitignored.

## Four rules

1. **Reference, never duplicate.** The committed design (`<path>/design.md`, the path as `work-docs-path` prints it), `.work/slices.yaml`, the slice commits, ADRs and the PR are cited by path, id, sha or URL.
2. **Redact** secrets, tokens and personal data.
3. **Tailor** to the argument: what the next session will do decides what goes in.
4. **Mine only what happened.** The flow is its own forward projection and re-earns every forecast (`/build` re-checks each slice), so a projected step is a forecast, not a record.

## Two regions

- **`## Durable`**: invariants still true, decisions with their rejected options, findings a future session would otherwise re-discover, open questions nobody has taken, known gaps. Phrase every line so it survives promotion into an ADR or the PR body: no next-move phrasing, no run-local state.
- Everything else is ephemeral: the next move, dispatch state, slice counts, snapshots, agent ids, and known-unknowns with the execution-time work that closes them (a slice's oracle, an unresolved fork, a verifier `ESCALATE`).

## Route

Name the next move as a command, a flow step to resume, or a reference into an artifact, and list only the runbook entries a future model should follow. Command names are plugin-qualified, `/bett3r-ai-workflow:verify-build`, in `status`, `flow.prev`, `flow.next` and every `skill-runbook` key: a bare `/verify-build` resolves against the host repo's namespace, where a same-named local command may exist. `flow.step` values stay bare; they name pipeline positions.

## Expiry-stamp every measured fact

A handoff is most confident exactly when it is most stale. Every measurement carries the sha, ref or moment it was computed against and what invalidates it:

- A conflict inventory expires on the next sibling merge and says nothing about unmerged siblings; a negative generalisation covers only the branches measured.
- A `.work/` occupancy or collision warning carries its liveness test (`git log --all --grep=<ID>` for merged commits, `passes: true` across the referenced `slices.yaml`) and lists separately what is unrecoverable (an undrained `learnings.md`) from what merged commits already preserve.
- A recorded `agentId` dies with its session; any other session gets `No transcript found`. Carry what re-dispatching fresh needs: worktree, branch, tip sha, procedure, invariants.

## Frontmatter

```yaml
---
readonly: true
origin: "<`{skill}` | conversation> (<session-id>)"
status: "<the next move: a command (`/bett3r-ai-workflow:plan`), a flow step to resume (`/bett3r-ai-workflow:build` at slice N), or @<artifact ref>>"
flow: # only mid-pipeline; links this handoff into the sequence
  step: "<start | design | plan | build | verify-build | capture-learnings>"
  prev: "<prior step or handoff slug, or ~>"
  next: "<next projected step, or ~>"
skill-runbook:
  - `{skill}`: "<condition>"
---
```

The `flow` block lets a resumed session place itself: the step it is at, the prior steps whose commits and `.work/` state are preserved, and the projected next step, which the next command reconciles rather than assumes.

## Finish

A handoff lives in disposable `.work/`: it is consumed with `/handon` before `/start` replaces `.work/`, or its `## Durable` region is folded into ADRs or the PR body first. Git is the record; the handoff is the baton. Done when the file exists with the frontmatter above and a `## Durable` heading.
