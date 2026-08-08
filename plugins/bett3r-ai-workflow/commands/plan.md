---
description: Cut the resolved design into vertical slices (tracer bullet first, prefactor first), review the breakdown with the user, and write .work/slices.yaml. --publish also creates Jira sub-tasks.
---

# /plan — cut into vertical slices

Turn `.work/design.md` into an ordered set of **vertical slices** using the `vertical-slicing` skill. Default: write them to `.work/slices.yaml` (local). With `--publish`: also publish each slice as a Jira sub-task for team / AFK-agent pickup.

## Argument: $ARGUMENTS
Optional ticket id. Flags: `--publish` (also create Jira sub-tasks).

---

## Step 1 — Read the design

Read `.work/design.md` (if absent: "No design found. Run `/design` first."). Read the relevant `CONTEXT.md` so slice names use the **ubiquitous language**, and respect existing ADRs in the area you're touching.

## Step 2 — Look for prefactoring

"Make the change easy, then make the easy change." Identify any reshaping of existing code that would make the feature drop in cleanly. If found, it becomes the **earliest slice(s)** — done before the feature slices.

## Step 3 — Draft the slices (use the `vertical-slicing` skill)

Cut the design into tracer-bullet vertical slices, each a thin but COMPLETE path through every layer it touches, independently verifiable. **Slice 1 is the tracer bullet** through the riskiest gate-less seam from the design's risk section. Name each slice in the ubiquitous language; describe **behavior, not file paths**.

## Step 4 — Review the breakdown with the user

Present the proposed slices as a numbered list. For each: **title**, **blocked-by**, and the **behavior** it delivers. Ask:

- Does the granularity feel right (too coarse / too fine)?
- Are the dependencies correct?
- Should any slices merge or split?

**Iterate until the user approves.** Do not write `slices.yaml` or publish until approved.

**Unattended branch.** Inside a `/start-multi` fleet run there is **no user to approve, by construction** — this step reads as a hard gate with no exit, so an agent must decide on its own whether the instruction applies to it, and a literal one stalls here. When invoked by an unattended agent (or the ticket carries a `design-multi:resolved:vN` block, whose slicing the human already reviewed): **skip the review pass, write `slices.yaml`, and record in the file that the breakdown was not human-reviewed**, so `/verify-build` and the PR body can say so. `/design` already has this shape for its own interview; this is its counterpart.

## Step 5 — Write `.work/slices.yaml`

Write the approved slices (the `vertical-slicing` skill's schema): `id`, `name`, `passes: false`, `depends_on`, `behavior`, `oracle` (the test that proves it), `gates` (the project invariants the verifier must confirm). Record the ADR path and branch. Lead each slice with behavior; `touches` (files) is an optional hint only.

## Step 6 — `--publish` (optional): Jira sub-tasks

Only when `--publish` is passed. For each approved slice, in dependency order (blockers first, so real ids can be referenced), create a **Jira sub-task** under the ticket via the Atlassian MCP. Use the repo's sub-task type (for Teselly: **`Subtarea`**). Body template:

```
## What to build
{end-to-end behavior of this slice — not layer-by-layer, no stale file paths.
 Exception: a decision-rich snippet from a prototype (state machine / schema / type) is fine.}

## Acceptance criteria
- [ ] ...

## Blocked by
{sub-task id(s), or "None — can start immediately"}
```

Record each created sub-task id back into `.work/slices.yaml` (a `jira` field per slice) so `/build` and `/verify-build` can reference them. Do not modify the parent ticket beyond adding the sub-tasks.

## Step 7 — Hand off

> Slices ready in `.work/slices.yaml`{ and published as Jira sub-tasks}. Run `/build` to drive them.

## Principles

- Vertical, never horizontal; tracer bullet first; prefactor before feature.
- The breakdown is reviewed and approved before anything is written or published.
- `slices.yaml` is ephemeral; the durable record is the per-slice commits + the PR (and the Jira sub-tasks, if published).
