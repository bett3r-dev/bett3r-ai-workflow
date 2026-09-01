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

Write the approved slices (the `vertical-slicing` skill's schema): `id`, `name`, `passes: false`, `depends_on`, `behavior`, `oracle` (the test that proves it), `gates` (the project invariants the verifier must confirm), `designs` (the design node ids it delivers, when the unit has a design layer). Record the ADR path and branch. Lead each slice with behavior; `touches` (files) is an optional hint only.

**Record which design elements each slice delivers.** If the unit has a design layer
(`.esas/design.json` — an ESAS board session), add a `designs:` list to each slice naming the
**node ids** it builds. This is what lets `/build` scaffold *slice-scoped* instead of dumping the
whole design's stubs into the tracer bullet's commit, and it is the only place in the flow that
knows the mapping: by `/build` the design file is just a blob, and a slice title is not something
to reverse-engineer an id set from. Omit the field for a unit with no design layer — an absent
`designs:` means "nothing designed here", which `/build` reads correctly; a *wrong* one scaffolds
the wrong artifacts. Ids look like `{subdomain}_{abbrev}_{slug}`, e.g.
`sales_pol_buyer-invoice-preference-send-policy`; take them from the design file rather than
composing them by hand, since the slug rule is not obvious.

**Order the slices so a scaffolded artifact's host exists first.** A command is generated into the
aggregate or system that handles it, so a slice proposing both must build the handler before the
command — otherwise the scaffolder blocks, correctly, and the slice stalls on a dependency the
plan could have expressed. Same for an event and the module that owns its namespace.

**Route each slice to a model.** Add `model: sonnet` to the slices whose implementation is *mechanical* — scaffolding an artifact from a framework skill, config or wiring, a test-only or guard-only slice, a prefactor that is a mechanical move. Leave the field **absent** on everything else, which `/build` reads as `opus`: the tracer bullet, any slice touching an invariant or a seam two slices must agree on, and anything the design was thin about. This is the only place in the flow that knows which slices are hard, and an unrouted `slices.yaml` sends the whole build through the most expensive model available. When in doubt, leave it absent — the cost of an over-routed slice is one retry, and `/build` re-dispatches those on `opus` and reports them so the next plan can be marked correctly.

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
