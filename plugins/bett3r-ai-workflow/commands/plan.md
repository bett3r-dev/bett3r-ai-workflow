---
description: Cut the resolved design into vertical slices (tracer bullet first, prefactor first), review the breakdown with the user, and write .work/slices.yaml. --publish also creates Jira sub-tasks.
---

# /plan — cut into vertical slices

Turn `.work/design.md` into an ordered set of **vertical slices** using the `vertical-slicing` skill. Default: write them to `.work/slices.yaml` (local). With `--publish`: also publish each slice as a Jira sub-task for team / AFK-agent pickup.

## Argument: $ARGUMENTS
Optional ticket id. Flags: `--publish` (also create Jira sub-tasks).

---

## Step 1 — Read the design

**Record the mode first.** Overwrite `.work/mode.yaml` with `mode: plan` and the current work item before reading anything else — full rewrite, never an append, so the marker names the command running now instead of the one that ran last on this branch.

Read `.work/design.md` (if absent: "No design found. Run `/design` first."). Read the relevant `CONTEXT.md` so slice names use the **ubiquitous language**, and respect existing ADRs in the area you're touching.

## Step 2 — Look for prefactoring

"Make the change easy, then make the easy change." Identify any reshaping of existing code that would make the feature drop in cleanly. If found, it becomes the **earliest slice(s)** — done before the feature slices.

## Step 3 — Draft the slices (use the `vertical-slicing` skill)

Cut the design into tracer-bullet vertical slices, each a thin but COMPLETE path through every layer it touches, independently verifiable. **Slice 1 is the tracer bullet** through the riskiest gate-less seam from the design's risk section. Name each slice in the ubiquitous language; describe **behavior, not file paths**.

**A slice is cuttable only when everything it names resolves at the base.** Before a slice is written:

- **Resolve every node, API, helper or symbol it tells the executor to adopt** against the integration base (`git show <BASE>:<path>` or a repo-wide grep) and **record the resolving path in the slice**. A symbol that does not resolve is not a gap the lane fills by inventing it — the slice becomes a dependency on the track that owns it. Four of seven lanes in one fleet found their slice's premise false in under a minute each, on symbols a grep at cut time would have shown absent, and one slice's rewrite would have *introduced* the bug it claimed to fix.
- **Where the oracle says "the existing suite", confirm the file exists and record its path.** Three slices once named suites that did not exist (the rules had pin JSON, no `.test.ts`), which turned a "run the tests" slice into a "write the tests" slice mid-flight and changed its size.
- **A gate text carries the OBLIGATION, never the derived fact.** "Assert the stream name at build time and cite where it comes from" — not "shares the `InboundMessages-<id>` stream" (it did not exist); "grep every declaration site and report the count you observed" — not "declared in THREE places" (there were four, and the fourth was a closed-enum runtime defect); "cite the in-repo source for any external-standard claim" — not an observation number from memory. A specific-looking claim in a gate is the one an executor is least likely to re-check.
- **Enumerate the host repo's build-enforced guards the slice's file set can trip, as gates** — a nav-taxonomy drift check that fires on a two-of-three-file edit, a phrasing-uniqueness guard, a census that test fixtures alone can move. An unbriefed guard reads as a mysterious mid-slice failure and costs a retry.
- **Slice order follows oracle-provability, not the ticket's deploy sequence.** A ticket that ships the new mechanism first and deletes the old one later is describing production risk; a slice whose oracle asserts the new behaviour while the old policy is still registered is structurally red (both restore → double). Put the deletion before the oracle run, or split the oracle so each slice asserts only what is provable with both live — and record the deploy sequence in the PR body, not the slice order.

## Step 4 — Review the breakdown with the user

Present the proposed slices as a numbered list. For each: **title**, **blocked-by**, and the **behavior** it delivers. Ask:

- Does the granularity feel right (too coarse / too fine)?
- Are the dependencies correct?
- Should any slices merge or split?
- **For every contract this unit introduces, which slice writes it and which slice reads it?** A unit that ships one side is green by construction, and no single slice's gate can see it (`vertical-slicing`, anti-patterns). Answer it in the unattended branch too — it is answerable from the slice list alone.

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

## Step 8 — Report the outcome

End your output with this line, at column 0, as the **final** line — nothing after it, not even a closing remark, and no trailing punctuation (`success.` is a value in no vocabulary, and a step that punctuates its marker reports no verdict at all):

    LANE-STEP:v1 step=plan outcome=<success|blocked-on> slices=<n>

`success` when `.work/slices.yaml` is written; `slices=` is the number cut. `blocked-on` when the design cannot be sliced without an answer you do not have — do not emit a slice list you would not build. No gate runs here, so never `gate-red`. Never emit `infra`: its signal is the line's **absence**, which costs nothing from a step being killed underneath. The format contract — attributes, the parse rule, `:vN` — is stated once in [unit-lane](../agents/unit-lane.md); do not restate it here.

## Principles

- Vertical, never horizontal; tracer bullet first; prefactor before feature.
- The breakdown is reviewed and approved before anything is written or published.
- `slices.yaml` is ephemeral; the durable record is the per-slice commits + the PR (and the Jira sub-tasks, if published).
