---
description: Cut the resolved design into vertical slices (tracer bullet first, prefactor first), review the breakdown with the user, and write .work/slices.yaml. --publish also creates Jira sub-tasks.
---

# /plan — cut into vertical slices

Turn the committed design (`design.md` in the folder `work-docs-path` names) into an ordered set of **vertical slices** using the `vertical-slicing` skill. Default: write them to `.work/slices.yaml` (local). With `--publish`: also publish each slice as a Jira sub-task for team / AFK-agent pickup.

## Argument: $ARGUMENTS
Optional ticket id. Flags: `--publish` (also create Jira sub-tasks).

---

## Step 0 — Read your brief, if there is one

**If `.work/lane.yaml` exists, read it before anything else.** It is this unit's whole brief — written into the worktree from the outside — and it is where your inputs come from, not the caller. Take from it: the ticket, `adrAllocations` (the ADR number a slice's `adr:` field takes, already reserved for this lane), and `modelRouting`, which is what `model:` on a slice must agree with. Its **absence is a valid state** (a single `/start` flow has no brief), so say which of the two you ran under rather than defaulting silently: a missing brief and a unit that legitimately has none are indistinguishable, and that is exactly how a lane runs on the wrong defaults with nothing red.

Never accept these facts at the invocation instead. A step that learns a fact from whoever called it is a step **the other caller cannot run** — the per-step surface exists so that a step invoked on its own, by a caller it never spoke to, behaves identically.

## Step 1 — Read the design

**Record the mode first.** Overwrite `.work/mode.yaml` with `mode: plan` and the current work item (`work_item:` carried forward exactly as `/start` recorded it — read it from the existing `.work/mode.yaml` before the rewrite; never re-dated or re-derived from the branch) before reading anything else — full rewrite, never an append, so the marker names the command running now instead of the one that ran last on this branch.

Resolve the design's folder with `work-docs-path`, passing the work item exactly as `/design` Step 4 does, and read `<path>/design.md` from its verdict line's `path=` (if absent: "No design found. Run `/design` first."). An `outcome=error` line stops the step with its `reason=`; there is no second location to try. Read the relevant `CONTEXT.md` so slice names use the **ubiquitous language**, and respect existing ADRs in the area you're touching.

**Check for a resolved map.** If `<path>/map.json` exists, run `design-map candidates <path>/map.json` (positional — `--map` is refused) and read its `DESIGN-MAP:v1` line, never its prose, to get the candidate list for Step 4. If `<path>/map.json` is absent, there are no candidates and the verb is not called at all.

## Step 2 — Look for prefactoring

"Make the change easy, then make the easy change." Identify any reshaping of existing code that would make the feature drop in cleanly. If found, it becomes the **earliest slice(s)** — done before the feature slices.

## Step 3 — Draft the slices (use the `vertical-slicing` skill)

Cut the design into tracer-bullet vertical slices, each a thin but COMPLETE path through every layer it touches, independently verifiable. **Slice 1 is the tracer bullet** through the riskiest gate-less seam from the design's risk section. Name each slice in the ubiquitous language; describe **behavior, not file paths**.

**A slice is cuttable only when everything it names resolves at the base.** Before a slice is written:

- **Resolve every node, API, helper or symbol it tells the executor to adopt — and every input its behaviour reads: a config key, a state-file or frontmatter field, a file another step writes, an id shape a script must accept** — against the integration base (`git show <BASE>:<path>` or a repo-wide grep) and **record where each resolves in the slice**: the symbol's path, the writer of the field, the script and a real value it accepts. What does not resolve is not a gap the lane fills by inventing it — the slice becomes a dependency on the track that owns it, or a design question. Data inputs are the case this skips, because a field or an id shape reads as a *requirement*, not a symbol: one slice read an epic field `run.yaml` never had and a run id the path script rejected, and all of it surfaced at the verifier. Four of seven lanes in another fleet found their slice's premise false in under a minute each, on symbols a grep at cut time would have shown absent.
- **"Every X must do Y" over a set of call sites needs a STRUCTURAL oracle, not a behavioural one.** The trigger phrasing is worth matching verbatim, because it is what makes the rule fire: *"all N call sites"*, *"every appender"*, *"no module outside X"*. A behavioural test covers the writers that exist the day it is written and is *right* about every one of them; the defect is the writer added afterwards, and its signature is absence. Write a test that **enumerates the call sites from source** (walk the package, collect the matches), asserts the census, and asserts the **negative** form too — *"no module outside `<owner>` performs `<operation>`"*. Updating the census must be a deliberate edit and the failure message must name the new file — one such guard caught a sibling lane's N+1th appender days later. Such a guard matches source text, so it must **exclude comments** — one flagged two files that mention the token only in prose, one of them arguing *for* the seam.
- **Where the oracle says "the existing suite", confirm the file exists and record its path.** Three slices once named suites that did not exist (the rules had pin JSON, no `.test.ts`), which turned a "run the tests" slice into a "write the tests" slice mid-flight and changed its size.
- **A gate text carries the OBLIGATION, never the derived fact.** "Assert the stream name at build time and cite where it comes from" — not "shares the `InboundMessages-<id>` stream" (it did not exist); "grep every declaration site and report the count you observed" — not "declared in THREE places" (there were four, and the fourth was a closed-enum runtime defect); "cite the in-repo source for any external-standard claim" — not an observation number from memory. A specific-looking claim in a gate is the one an executor is least likely to re-check. **The rule covers every code-describing field in `slices.yaml`** — `behavior`, `oracle`, `gates` and any hint — **including anything an orchestrator writes into it after this step**: re-check it against HEAD at the moment it is written and record the `file:line` it was checked at, and derive a list of "every writer of X" by grepping the setter, never from the design. A mid-run hint written from the design's intent ("a property, not a literal") once contradicted a test an earlier slice had already committed (`toHaveLength( 199 )`).
- **Enumerate the host repo's build-enforced guards the slice's file set can trip, as gates** — a nav-taxonomy drift check that fires on a two-of-three-file edit, a phrasing-uniqueness guard, a census that test fixtures alone can move. An unbriefed guard reads as a mysterious mid-slice failure and costs a fix round.
- **Measure each slice's surface, and split a sweep too big to fix.** Record `surface:` on the slice — the files it touches and, for a mechanical sweep, the call or string sites — counted at the base by the probe that finds them, with a positive control on its pathspec (`EVIDENCE.md`, *Probe hygiene*); never estimated from the design. **Above 10 files or 200 sites, split it** into ordered sub-slices with their own oracles, by namespace or directory, and independent wherever they share no file so `/build` can run them together. The cap exists for the fix round, not the first pass: a ~26-file, ~1,140-call-site billing sweep ran 3 h 20 m and escalated on two small findings, where six sub-slices would have escalated one. A slice over the cap that cannot compile half-done — one atomic rename — keeps its size and says why in `surface.atomic:`.
- **Name the unit's seams BEFORE its oracles — fewest, highest, existing over new.** Write down the seams this unit will test at, as a top-level `seams:` block, and let every slice's `seam:` point at one of them. **The ideal number is one.** Prefer an existing seam to a new one, and the highest one that can still observe the claim — the slice's oracle then lands where the behaviour is *composed*, not where a unit happens to be convenient. Left unpressured, eight slices invent eight oracle locations and each is an independent chance to assert below the level the claim lives at: the worst defect in the corpus is exactly that — the oracle sat at the unit rather than the composition root, so **both wiring lines could be deleted with `tsc` clean and 738 tests green.** Record each seam's `at:` (the `file:line` it resolves to at the base, checked when written — the same rule as every other code-describing field above) and its `kind:` (`existing` or `new`). **The first seam is free; every seam after it, and every `kind: new` one, owes a one-line `why:`** — why the already-named seams cannot hold this slice's claim. `check-plan` refuses a plan with no `seams:` (`reason=plan-unseamed`), a slice with no `seam:` (`slice-unseamed`), a slice naming a seam the unit never declared (`unnamed-seam`), and an undefended extra or new seam (`seam-unstructured why=extra-unjustified|new-unjustified`). *Highest* stays a judgement — what is mechanical is that the choice is written down, defended and reviewable instead of being made eight times in silence.
- **Slice order follows oracle-provability, not the ticket's deploy sequence.** A ticket that ships the new mechanism first and deletes the old one later is describing production risk; a slice whose oracle asserts the new behaviour while the old policy is still registered is structurally red (both restore → double). Put the deletion before the oracle run, or split the oracle so each slice asserts only what is provable with both live — and record the deploy sequence in the PR body, not the slice order.

## Step 4 — Review the breakdown with the user

Present the proposed slices as a numbered list. Lead with the unit's **seams** — each one's name, where it is, and why any seam after the first exists — because that is the decision the oracles all inherit and the cheapest one to correct here. For each slice: **title**, **blocked-by**, the **behavior** it delivers, the **seam** it tests at, and its **oracle** — followed by that slice's own candidates (if a map.json existed), listed under it; then any candidates not yet attached to a slice, listed last. For each candidate ask the user to **confirm, reject, or re-attach each candidate**: only a confirm copies that candidate's example verbatim into the slice's `oracle` (the promotion); a reject or re-attach never copies. Ask:

- Does the granularity feel right (too coarse / too fine)?
- Are the dependencies correct?
- Should any slices merge or split? (A slice over the Step 3 surface cap is already split — that is not a question for this review.)
- **For every contract this unit introduces, which slice writes it and which slice reads it?** A unit that ships one side is green by construction, and no single slice's gate can see it (`vertical-slicing`, anti-patterns). Answer it in the unattended branch too — it is answerable from the slice list alone.

**Iterate until the user approves.** Do not write `slices.yaml` or publish until approved.

**Unattended branch.** Inside a `/start-multi` fleet run there is **no user to approve, by construction** — this step reads as a hard gate with no exit, so an agent must decide on its own whether the instruction applies to it, and a literal one stalls here. When invoked by an unattended agent (or the ticket carries a `design-multi:resolved:vN` block — a resolved block reviews the design, not its slicing): **skip the review pass, write `slices.yaml`, write `review: unattended`, and mark every candidate `status: unconfirmed` without ever copying one into an `oracle`** — record in the file that the breakdown was not human-reviewed, so `/verify-build` and the PR body can say so. `/design` already has this shape for its own interview; this is its counterpart.

## Step 5 — Write `.work/slices.yaml`

Write the approved slices (the `vertical-slicing` skill's schema): `id`, `name`, `passes: false`, `depends_on`, `behavior`, `oracle` (the test that proves it), `seam` (the unit's seam it tests at — one of the top-level `seams:`, Step 3), `scenarios` (below — **every slice, no exceptions**), `gates` (the project invariants the verifier must confirm), `designs` (the design node ids it delivers, when the unit has a design layer). Record the ADR path and branch. Lead each slice with behavior; `touches` (files) is an optional hint only. Add `surface` (Step 3) to every slice, and **before writing, check each one against the cap**: a slice over it without `surface.atomic:` is refused — split it, then write.

**Every slice carries `scenarios:` — at least one, and `check-plan` refuses the plan without it.** `oracle:` keeps its job: the narrative of the test, in prose. `scenarios:` is the same thing in the form the executor cannot re-interpret, and it is what an owner reads to confirm the slice is aimed at the right behaviour before a line is written.

```yaml
    scenarios:
      - scenario: an epic with two designed children is admitted as one run
        given: an epic dragged to Ready For Implementation with two designed children
        when: the trigger runs
        then: one epic_runs row exists, and each child has a held runs row carrying epic_run_id
      - scenario: nothing outside the ledger inserts a run
        kind: structural
        text: >
          every INSERT into runs is in src/ledger/runs.ts, and no module outside it inserts —
          asserted by walking the package, with the negative form and the census both checked
```

- **Behavioural is the default and needs all three halves.** A `given` and a `when` with no `then` is refused (`why=missing-then`): it reads exactly like a finished scenario and yields an oracle asserting a setup rather than an outcome.
- **`kind: structural` keeps prose on purpose**, for the "every X must do Y" rules Step 3 above already mandates a structural oracle for. Given/When/Then has no room for the negative half — *"and no module outside `<owner>`…"* — and that negative half is what caught the worst defect in the corpus: a composition root whose two wiring lines could both be deleted with `tsc` clean and 738 tests green. A structural scenario carrying Given/When/Then as well is refused; one of the two is decoration and nobody can tell which.
- **Where a candidate was confirmed, its walk *is* the scenario** — the promotion copies it. Where there is no `map.json`, write the scenarios yourself: that is the case this rule exists for. Both zero-first-pass-green runs on record were `review: unattended` with no map, so every oracle in fifteen slices was written freehand and 41% of all fix rounds since have been `oracle-wrong`.
- **A scenario is checked against HEAD like every other code-describing field** (Step 3's rule about obligations, not derived facts). A `then:` asserting a specific count or literal is exactly the claim an executor will not re-check.

**After `slices:`, always write a top-level `review: human|unattended`.** When Step 1 found a `<path>/map.json`, also write a top-level `candidateOracles:` — a list of `{fork, option, scenario, source, example, slice, status}`, one entry per candidate, `slice` set when attached and `status` one of `confirmed`, `rejected`, `unconfirmed`. Omit `candidateOracles:` entirely when there was no map.json. Both keys go **after** `slices:`, since `worktree-pool`'s `parse_slices` stops at the first indent-0 line following it.

**Then run `design-map check-plan .work/slices.yaml`** in both the attended and the unattended branch. On `outcome=fail`, act on its `reason=` and re-run: `reason=candidate-in-oracle` → remove the copied candidate example from that `slice=`'s `oracle`; `reason=unattended-confirmed` → reset that candidate's status back to `status: unconfirmed`; `reason=plan-unseamed` / `slice-unseamed` / `unnamed-seam` / `seam-unstructured` → go back to Step 3 and name the seam properly, **never by inventing a `seams:` entry to match whatever a slice already said** — that reverses the contract and re-buys the eight-oracle-locations failure with one extra line of YAML. Never proceed on a failing plan. `/build`, the executor and the verifier all ignore `candidateOracles:` — nothing in the build or its gates blocks on the mark.

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

**Route each slice to a model.** Add `model: sonnet` to the slices whose implementation is *mechanical* — scaffolding an artifact from a framework skill, config or wiring, a test-only or guard-only slice, a prefactor that is a mechanical move. Leave the field **absent** on everything else, which `/build` reads as `opus`: the tracer bullet, any slice touching an invariant or a seam two slices must agree on, and anything the design was thin about. This is the only place in the flow that knows which slices are hard, and an unrouted `slices.yaml` sends the whole build through the most expensive model available. When in doubt, leave it absent — the cost of an over-routed slice is one fix round, and `/build` re-dispatches those on `opus` and reports them so the next plan can be marked correctly.

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

`success` when `.work/slices.yaml` is written; `slices=` is the number cut. `blocked-on` when the design cannot be sliced without an answer you do not have — do not emit a slice list you would not build. No gate runs here, so never `gate-red`. **Immediately before printing it**, run `lane-step-record '<the identical line>'`: it writes the verdict onto your branch when `.work/lane.yaml` carries `verdictOnBranch: true` and does nothing otherwise — a `success` with nothing committed writes nothing, a `blocked-on` writes an empty commit; a non-zero exit is reported in your prose, never by changing the line. Never emit `infra` — its signal is the line's absence. The format contract is stated once in [unit-lane](../agents/unit-lane.md); do not restate it here.

## Principles

- Vertical, never horizontal; tracer bullet first; prefactor before feature.
- The breakdown is reviewed and approved before anything is written or published.
- `slices.yaml` is ephemeral; the durable record is the per-slice commits, the work item's committed record beside the code (`design.md`, `decisions.md`, `concerns.md`, `build-summary.md`) and the PR that links it (and the Jira sub-tasks, if published).
