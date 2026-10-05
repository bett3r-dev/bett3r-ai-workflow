---
description: Routine plan step. Cut the board's agreed blueprint.md into vertical slices unattended and write .work/slices.yaml for /build, every ready scenario copied into the slice that delivers it. Run by /implement; needs .work/lane.yaml.
---

# /routine-plan — slice the agreed design

The routine's `plan` step; its verdict is `LANE-STEP:v1 step=plan outcome=<success|blocked-on> slices=<n>`. It does what `/plan` does, with two differences: the design is the board's `blueprint.md` (the brief's `design:`), not a `design.md`, and the breakdown is never reviewed by a person, by construction.

## Step protocol

**Brief.** `.work/lane.yaml` must exist; take `work_item`, `branch` and `design` from it and ask no one anything. Without it, or without `design:`, end `blocked-on`: this command runs only inside `/implement`. A fact the design states is a claim to verify against the tree before you build on it.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: plan`, `work_item:` and `branch:` carried forward exactly, `updated:` now.

**Verdict.** Your last line is the `LANE-STEP:v1` line above, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it. Printing the line ends this step.

## Step 1 — Read the design

1. Read `<design>` whole. Its sections: Problem, Solution, User Stories, Resolved decision tree (each fork `decided(owner)` or `decided(code)`), Scenarios, Observations, Implementation Decisions, Testing Decisions, Risks. Every decided fork is settled: slice it, never re-open it.
2. Beside it in the same folder: `decisions.md` (the board's decisions, plus any `D<n>` entries an earlier `/build` appended) and `scaffold.json` when present.
3. **The ready scenarios.** Each bullet under `## Scenarios` reads `- <id> — <name> (from <fork>, <status>)` with indented `Given` / `When` / `Then` lines. One whose status is `ready` is agreed on the board and must be delivered; list every other one by id as not taken. Read them from `blueprint.md`, not with `design-map candidates`: the bundle's `blueprint/map.json` is not the schema `design-map` reads (`schema-invalid at=/forks/0/tickets` on TV2-10's map).
4. The area's `CONTEXT.md` and the ADRs the design cites.

Done when the design, its ready scenario ids and the scaffold report (or its absence) are in hand.

## Step 2 — Cut the slices

Call the Skill tool with "vertical-slicing": the method, the adequacy rules and the `slices.yaml` schema live there. Apply it to the design, keeping `/plan` Step 2's discipline:

- **Resolve every symbol at the base** (`git show <base>:<path>` or a repo-wide grep) and record where it resolved. The design's `file:line` citations were true when the board session wrote them; re-check each one a slice relies on, and a citation that no longer holds is a finding the slice records, not a fact to build on.
- **The tracer bullet is the design's.** When Testing Decisions names one, it is slice 1, at the seam it names.
- **Seams** named at the top level (`seams:`); every slice's `seam:` names one.
- **The scaffold report's files are intended files.** When `scaffold.json` exists, each `manifest[].file` and `placed[].file` belongs to the slice that delivers its `node`, that slice's `designs:` lists the node id, and the files count in its `surface:`. `/build` hands the executor those entries and runs no scaffolder.
- `surface:` counted at the base with a positive control on its pathspec; over the cap, split.
- Every Risk the design names is either the oracle of some slice or recorded in the slice that leaves it open.
- `model: sonnet` only where the skill calls a slice mechanical.

## Step 3 — Write `.work/slices.yaml`

Write the slices in the skill's schema (`id`, `name`, `passes: false`, `depends_on`, `behavior`, `oracle`, `seam`, `probe`, `scenarios`, `gates`, `surface`, and where they apply `designs` and `model`), then, after `slices:`, the top-level `review: unattended`. Write no `candidateOracles:` key: no map was read.

**Every ready scenario lands in exactly one slice**, copied verbatim:

```yaml
scenarios:
  - id: <the scenario id, exactly as blueprint.md prints it>
    scenario: <its name>
    given: <its Given line, without "Given ">
    when: <its When line, without "When ">
    then: <its Then line, without "Then ">
    expected_from: spec
    expected_source: <design> scenario <id>
```

A slice's own further scenarios follow the skill's sourcing rules.

Then check, in both directions, and fix until both pass:

```bash
design-map check-plan .work/slices.yaml > "${TMPDIR:-/tmp}/check-plan.txt" 2>&1
```

Read its `DESIGN-MAP:v1` line, not its exit code. On `outcome=fail`, act on `reason=` as `/plan` Step 4 lists (`slice-unprobed`, `scenario-unsourced`, the seam reasons back to Step 2, any other names the field to fix) and re-run. Then confirm every ready id from Step 1 appears as an `id:` in `.work/slices.yaml` exactly once (`grep -c`); a missing one is added to the slice that delivers it.

## Step 4 — Verdict

`success` when `.work/slices.yaml` is written, `check-plan` reports `outcome=ok` and every ready scenario is placed; `slices=` is the number cut. `blocked-on` when the design cannot be sliced without an answer the board did not give: say which fork or scenario, in one line a human can act on. A slice list you would not build is not emitted.

    LANE-STEP:v1 step=plan outcome=<success|blocked-on> slices=<n>

## Boundaries

- `blueprint.md` and the bundle under `blueprint/` are read, never edited.
- `.work/slices.yaml` is working state; nothing here commits.
