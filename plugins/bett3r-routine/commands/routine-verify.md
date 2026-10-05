---
description: Routine verify step. Check the whole built change against the board's blueprint.md — scoped gate, scaffold census, standards and spec review, ripple sweeps — commit verification.md beside the design and push the claude/ branch. Opens no PR. Run by /implement; needs .work/lane.yaml.
---

# /routine-verify — check the whole change

The routine's `verify-build` step; its verdict is `LANE-STEP:v1 step=verify-build outcome=<success|gate-red|blocked-on>`. It is `/verify-build` cut to what an unattended lane with no PR owns: the per-slice gates already ran in `/build`, so this checks what they could not see, the assembled change, and writes the result where the PR's reviewer will find it. Blueprint owns the pull request; this step opens none, posts no commit status and pushes no dashboards.

## Step protocol

**Brief.** `.work/lane.yaml` must exist; take `work_item`, `branch` and `design` from it and ask no one anything. Without it, end `blocked-on`.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: verify-build`, `work_item:` and `branch:` carried forward exactly, `updated:` now.

**Verdict.** Your last line is the `LANE-STEP:v1` line above, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it. Printing the line ends this step.

## Step 1 — Preconditions

`work-docs-path --item <work_item>`; read its last line; `<path>` is its `path=` and is the folder of `<design>`. `<base>` is the sha in `.work/known-baseline-failures.md`.

Every slice in `.work/slices.yaml` is `passes: true` with exactly one slice commit (`git log --format=%H -E --grep '^Slice <id> of <work_item> ' <base>..HEAD`). Otherwise end `blocked-on`: "Slices N… not yet green."

## Step 2 — The gate

Call the Skill tool with "full-gate" and run the repo's **scoped** default (no argument), baseline-diffed; with no scoped mode declared, run `--fast` and say so. Never `--full`. Keep the report block verbatim, `GATE-MODE:` line included. `FAIL` (red here and not on the base) ends the step `gate-red` after Step 6 records it; a step red on the base too is pre-existing, named and left alone; `SKIP` and `INCONCLUSIVE` are named and do not block.

## Step 3 — Scaffold census

`scaffold-commit census --item <work_item>`; read its last line, `SCAFFOLD-COMMIT:v1 verb=census outcome=…`.

- `outcome=blocked`: each `not-implemented: <id>` is an agreed scenario with no implemented test. Implement it as a fix slice (Step 4's rule) or end `blocked-on reason=scenario-not-implemented`, naming each id. An agent's judgement strikes no scenario.
- `outcome=ok` or `skipped`: record the line.
- `outcome=error`, or no line: record it and continue; it is not a pass, and Step 6 says so.

Then the untouched stubs: each `manifest[]` entry of `<path>/scaffold.json` whose file still exists and whose `git hash-object <file>` equals its `blob` is a stub nothing filled. List each as `untouched stub: <file> (<node>)`; it blocks nothing.

## Step 4 — Whole-change review

**Review.** Two read-only sub-agents in one message, both `sonnet`, each briefed in under 400 words with the diff *command* (`git diff <base>...HEAD`), never the diff itself, asking for findings only, each naming file, line and the rule or requirement it breaks:

- *Standards*: against `.claude/rules/` and the repo's own conventions; anything a linter or type checker enforces is skipped.
- *Spec*: against `<design>`: every decided fork and every ready scenario implemented, nothing outside the design shipped, every deviation recorded as a `D<n>` entry in `<path>/decisions.md`.

Aggregate verbatim under two headings. Then the cross-slice question is yours: do the slices compose, and does the whole deliver the design's Solution.

**Ripple sweeps.** Run every sweep in `/verify-build` Step 3's table that this diff triggers (deleted symbols and changed signatures, read-model keys, persisted field names, guards and their stamping surfaces, codegen drift, cross-slice composition), as read-only `sonnet` sub-agents, one row each. A clean verdict is a claim too: say what each sweep ran.

**Resolve.** Disprove every Critical before keeping it: read the call site, `git blame` against `<base>` for pre-existing, construct a failing input. Fix every surviving Critical and Medium as a fix slice appended to `.work/slices.yaml` with `origin: verify-build`, driven through `/build`, then re-run Steps 2 and 3. A Critical you cannot fix ends the step `blocked-on`, naming it.

## Step 5 — Concerns

When `<path>/concerns.md` exists, rule every `## C<n>` entry by its `verify:` instruction exactly as `/verify-build` Step 5a does, then `concerns-check --decisions "<path>/decisions.md" "<path>/concerns.md"` and read its `CONCERNS-CHECK:v1` line. `fail` or `error` on a hard concern ends the step `blocked-on`: with no PR to carry it, the needs-human trailer is how it reaches the owner. Only the owner waives. Absent: `concerns: none recorded`.

## Step 6 — Record and push

Write `<path>/verification.md`; it is what the ticket's PR reviewer reads in place of a PR body:

```markdown
# Verification — <work_item>

<two to four sentences: what shipped against the design>

Breakdown not human-reviewed (unattended /routine-plan).

## Slices
- slice <id> — <name> (<commit>)

## Gate
<Step 2's report block verbatim, GATE-MODE line included; every SKIP, INCONCLUSIVE or un-run tier by name>

## Scaffold census
<the census line verbatim, then each not-implemented:, hold: and untouched stub: line>

## Review
### Standards
### Spec
### Ripple sweeps
<each sweep run and its verdict; how every Critical and Medium was resolved, or "clean">

## Concerns
<Step 5's line>

## For a human to check by hand
<what the slice tests cannot show (UI, a browser smoke, an environment), each with the path and what a pass looks like>
```

Commit it on its own as `docs(record): verify <work_item>`, together with `decisions.md` when this step appended to it. Then `git push -u origin <branch>`, the brief's branch and no other. A refused push ends the step `blocked-on`, quoting git.

## Step 7 — Verdict

`success` when the gate has no `FAIL`, the census is not blocked, every Critical is fixed or disproved and the push landed. `gate-red` when Step 2 stayed `FAIL`. `blocked-on` when a human must decide first.

    LANE-STEP:v1 step=verify-build outcome=<success|gate-red|blocked-on>

## Boundaries

- No pull request, no commit status, no dashboard push, no tracker write: Blueprint owns the PR and moves the ticket from `/implement`'s trailer.
- `blueprint.md` and the bundle under `blueprint/` are read, never edited.
