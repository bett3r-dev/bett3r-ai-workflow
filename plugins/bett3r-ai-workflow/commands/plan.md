---
description: Cut the committed design into vertical slices, review the breakdown, and write .work/slices.yaml; --publish also creates Jira sub-tasks.
---

# /plan — cut into vertical slices

This is the `plan` step; its verdict is `LANE-STEP:v1 step=plan outcome=<success|blocked-on> slices=<n>`. It turns the committed `design.md` into `.work/slices.yaml`, the ordered slice list `/build` drives.

**Argument** `$ARGUMENTS`: optional ticket id. `--publish` also creates Jira sub-tasks (Step 5).

## Step protocol

**Brief.** If `.work/lane.yaml` exists you are an unattended lane: take every input (`work_item`, `branch`, `worktree`, `runDir`, `gateDeferred`, `sliceBudget`, `mapProvenance`, `preconditions`, the rest) from it and ask no one anything. A fact it hands down is a claim to verify against the tree before you build on it. Without the file you run attended: inputs come from the user and the working tree.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: <this step>`, `work_item:` and `branch:` carried forward exactly as `/start` recorded them, `updated:` now. The file is replaced, not merged or appended; only `/start` clears it.

**Verdict.** Your last line is `LANE-STEP:v1 step=<this step> outcome=<success|gate-red|blocked-on>` with this step's attributes, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it (it records the verdict on the branch when the brief opts in). Printing the line ends the run: take no turn after it.

## Step 1 — Read the design

1. Mark the mode: `.work/mode.yaml` reads `mode: plan` (*Step protocol*).
2. Run `work-docs-path --item <work_item>` with the `work_item` from `.work/mode.yaml` and read `<path>/design.md` from the verdict line's `path=`. `outcome=error` ends the step `blocked-on` with its `reason=`; there is no second location to try. A folder without `design.md`: say "No design found. Run `/design` first." and end `blocked-on`.
3. If `<path>/map.json` exists, run `design-map candidates <path>/map.json` (positional; `--map` is refused) and read its `DESIGN-MAP:v1` line, not its prose, for the candidate list Step 3 uses. Without `map.json` there are no candidates and the verb is not called.
4. Read the area's `CONTEXT.md` for the ubiquitous language and the ADRs it cites. From the brief: `adrAllocations` (the number the plan's top-level `adr:` takes) and `modelRouting` (what `model:` on a slice must agree with).

Done when the design, the candidate list or its absence, and the brief's inputs are in hand.

## Step 2 — Cut the slices

Call the Skill tool with "vertical-slicing". It is the method's single home: tracer bullet first, prefactor first, seams named before oracles, the adequacy rules, the one-fresh-context rule and the `slices.yaml` schema. Apply it to the design, then before any slice is written down:

- **Resolve every symbol at the base.** Every node, API, helper or symbol a slice tells the executor to adopt, and every input its behaviour reads (a config key, a state-file or frontmatter field, a file another step writes, an id shape a script must accept), resolves against the base (`git show <BASE>:<path>` or a repo-wide grep), and the slice records where: the path, the writer of the field, the script and a real value it accepts. What does not resolve becomes a dependency on the track that owns it, or a design question.
- Where an oracle says "the existing suite", the file exists and its path is recorded.
- A gate carries the obligation, not the derived fact: "assert the stream name at build time and cite where it comes from", not "shares stream X". Every code-describing field (`behavior`, `oracle`, `gates`, `scenarios`, `seams[].at`) is checked against the base at the moment it is written, with the `file:line` it was checked at.
- The host repo's build-enforced guards the slice's file set can trip (a drift check, a phrasing guard, a census fixtures alone can move) are listed as `gates`.
- `surface:` is counted at the base by the probe that finds the files and sites, with a positive control on its pathspec (`EVIDENCE.md`, *Probe hygiene*); over the cap, split as the skill says.
- `seams:` named at the top level as the skill says; every slice's `seam:` names one of them.
- Slice order follows oracle-provability, not the ticket's deploy sequence: an oracle asserting the new behaviour while the old policy is still registered is red by construction. Put the deletion first or split the oracle, and record the deploy sequence in the PR body.
- `designs:` on each slice when the unit has a design layer (`.esas/design.json`): the node ids it builds, copied from the design file (ids look like `{subdomain}_{abbrev}_{slug}`). A scaffolded artifact's host slice comes before the artifact's own: the handler before its command, the module before its event. Without a design layer the field is absent.
- `model: sonnet` only where the skill calls the slice mechanical; absent everywhere else, which `/build` routes as its table does.

Done when every slice has resolved symbols, a seam, sourced scenarios, a probe and a surface within the cap, in dependency order with the tracer bullet first.

## Step 3 — Review the breakdown

Present the slices as a numbered list, leading with the seams (each one's name, `at:`, and the `why:` of every seam after the first). For each slice: title, blocked-by, the behavior it delivers, the seam it tests at, and its **oracle** — followed by that slice's own candidates when a `map.json` existed, with unattached candidates listed last. Ask the user to **confirm, reject, or re-attach each candidate**: only a confirm copies the candidate's example verbatim into the slice's `oracle`. Then ask: is the granularity right; are the dependencies right; should any slice merge or split; for every contract this unit introduces, which slice writes it and which slice reads it? Iterate until approved.

**Unattended branch.** Under a brief, or when the ticket carries a `design-multi:resolved:vN` block (which reviews the design, not its slicing), there is no user to approve, by construction: skip the review, write `review: unattended`, and mark every candidate `status: unconfirmed` without copying one into an `oracle`. Answer the contract question yourself from the slice list.

Done when the breakdown is approved, or the unattended branch has been taken and recorded in the file.

## Step 4 — Write `.work/slices.yaml`

Write the slices in the skill's schema: `id`, `name`, `passes: false`, `depends_on`, `behavior`, `oracle`, `seam`, `probe`, `scenarios` (every slice, at least one; each behavioural one with `expected_from:` and, unless `literal`, `expected_source:`), `gates`, `surface`, and where they apply `designs` and `model`. After `slices:`, always write a top-level `review: human|unattended`. When Step 1 found a `map.json`, also write a top-level `candidateOracles:`, one `{fork, option, scenario, source, example, slice, status}` entry per candidate with `status` one of `confirmed|rejected|unconfirmed`; omit the key entirely otherwise. Both keys go after `slices:`, because `worktree-pool`'s parser stops at the first indent-0 line following it.

Then run `design-map check-plan .work/slices.yaml`, in both branches, and read its line. On `outcome=fail`, act on `reason=` and re-run:

- `reason=candidate-in-oracle` → remove the copied candidate example from that `slice=`'s `oracle`;
- `reason=unattended-confirmed` → reset that candidate to `status: unconfirmed`;
- `reason=slice-unprobed` → name the production line whose deletion turns that oracle red, not the test file;
- `reason=scenario-unsourced` → say where the expected value comes from and cite it; when the honest answer is "from how the code will compute it", the scenario is what to fix;
- `reason=plan-unseamed|slice-unseamed|unnamed-seam|seam-unstructured` → back to Step 2 to name the seam properly, never by adding a `seams:` entry to match what a slice already said;
- any other `reason=` → its name says which field is missing or malformed; fix that slice.

Done when `check-plan` reports `outcome=ok`. `/build`, the executor and the verifier ignore `candidateOracles:`; nothing downstream blocks on the mark.

## Step 5 — `--publish`: Jira sub-tasks

Only with `--publish`. For each slice in dependency order (blockers first, so real ids can be referenced), create a Jira sub-task under the ticket through the Atlassian MCP, in the repo's sub-task type. Body: `## What to build` (the end-to-end behaviour, no file paths), `## Acceptance criteria` (checkboxes), `## Blocked by` (sub-task ids, or "None — can start immediately"). Record each id in the slice's `jira:` field. The parent ticket changes only by gaining the sub-tasks.

Done when every slice carries a `jira:` id.

## Step 6 — Verdict

> Slices ready in `.work/slices.yaml`{ and published as Jira sub-tasks}. Run `/build` to drive them.

Then the verdict line (*Step protocol*):

    LANE-STEP:v1 step=plan outcome=<success|blocked-on> slices=<n>

`success` when `.work/slices.yaml` is written and `check-plan` passed; `slices=` is the number cut. `blocked-on` when the design cannot be sliced without an answer you lack; a slice list you would not build is not emitted. No gate runs here, so `gate-red` is not a value this step emits.

## Boundaries

- `slices.yaml` is written after approval, or after the unattended branch has been taken and `review: unattended` says so; a breakdown nobody reviewed is recorded as unreviewed, not passed off as approved.
- A `check-plan` refusal is fixed at the plan, never proceeded past: a failing plan is paid for in `/build`'s fix rounds.
- `.work/slices.yaml` is working state; the durable record is the slice commits, the work item's committed record and the PR that links it.
