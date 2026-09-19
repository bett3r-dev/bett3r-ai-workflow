---
description: Land the work. One whole-PR review across all slices, the dev checklist, ADRs, the ruled concerns and the measured run, then the PR that links the committed record.
---

# /verify-build — land the work

This is the `verify-build` step; its verdict is `LANE-STEP:v1 step=verify-build …`. It checks the assembled change the per-slice `verifier` could not, completes the committed record `work-docs-path` locates, and opens the PR that links it.

## Argument: $ARGUMENTS

Optional ticket id. Default: the active work in `.work/slices.yaml`.

## Step protocol

**Brief.** If `.work/lane.yaml` exists you are an unattended lane: take every input (`work_item`, `branch`, `worktree`, `runDir`, `gateDeferred`, `sliceBudget`, `mapProvenance`, `preconditions`, the rest) from it and ask no one anything. A fact it hands down is a claim to verify against the tree before you build on it. Without the file you run attended: inputs come from the user and the working tree.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: <this step>`, `work_item:` and `branch:` carried forward exactly as `/start` recorded them, `updated:` now. The file is replaced, not merged or appended; only `/start` clears it.

**Verdict.** Your last line is `LANE-STEP:v1 step=<this step> outcome=<success|gate-red|blocked-on>` with this step's attributes, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it (it records the verdict on the branch when the brief opts in). Printing the line ends the run: take no turn after it.

## Step 1 — Preconditions

Resolve the record folder: `work-docs-path --item <work_item>`, the reader form, no `--owner-branch`, with `work_item` from `.work/mode.yaml` untouched. Read its last line, `WORK-DOCS-PATH:v1 …`, never its exit code; `<path>` is its `path=`. On `outcome=error`, say so and carry on without a record folder: Steps 5a, 5a2 and 5b leave their files unwritten and carry `outcome=error reason=<its reason>` (5b writes `concerns: null`, 6b posts `failure`); the PR still opens.

Read `.work/slices.yaml` and `<path>/design.md`. Every slice is `passes: true` with one slice commit per slice (`git log --format=%H -E --grep '^Slice <id> of <work_item> ' <base>..HEAD` finds exactly one); otherwise stop: "Slices N… not yet green — run `/build` first." Done when `<path>` resolved and every slice is green and committed.

## Step 2 — Run the gate

`Call the Skill tool with "full-gate"`. It owns discovery, the `GATE-STEP:` contract and the report block; read the verdict as `full-gate` does. The mode:

- **`.work/lane.yaml` exists and carries `gateDeferred: true`** → run **`--fast`** only; `/merge-multi` runs the branch-wide check once. The PR body records "Gate deferred to the fleet gate, run `<runId>`." and "Version bump deferred to the fleet merge, run `<runId>`." (the version-bump step reports `SKIP reason=deferred-to-merge-multi`; a `FAIL` there is still a `FAIL`).
- **No brief, or one that does not defer** → the repo's scoped default (no argument), baseline-diffed; with no scoped mode declared, run `--fast` and say so.

Record the report block verbatim, `GATE-MODE:` line included, for the PR body. A `FAIL` blocks Step 6; a step red on the base too is pre-existing, named and left alone; `SKIP` and `INCONCLUSIVE` steps are named and do not block. Done when the report block is recorded with its mode and verdict.

## Step 3 — Whole-PR review

**Resolve the base.** When the diff's file count is several times the union of `touches:` in `.work/slices.yaml`, `git branch -r --contains <first-branch-commit>` names the parent and `git merge-base <candidate> HEAD` is `<resolved-base>` for every later step.

**Review.** `Call the Skill tool with "code-review"` over `git diff <resolved-base>...HEAD`: fixed point `<resolved-base>`, spec source `<path>/design.md`, standards sources `${CLAUDE_PROJECT_DIR}/.claude/rules/`. Its issue-tracker lookup and setup pointer do not apply here: when it asks for either, run its two axes over that diff with those sources, ask nothing, and route both sub-agents to `sonnet`. Then the cross-slice questions: do the slices compose, is one undone by a later one, does the whole deliver the resolved design, deviations recorded.

**Ripple sweeps.** A mechanical third pass, run rather than eyeballed, against `HEAD` even after `/build`'s own ripple check. When a diff redefines a value's semantics, sweep its readers. Dispatch the sweeps as read-only subagents routed as `/build`'s table does, one row each; where the work carries a safety-direction invariant (may only widen, must never lose), each brief asks the invariant's question. Adjudicate rather than re-run. A clean verdict is a claim too ([EVIDENCE.md](../EVIDENCE.md) §3).

| When the diff… | Sweep | A hit means |
|---|---|---|
| deletes a symbol, route, config field or subsystem, or changes an exported signature | grep every repo for callers, including `*.integration.test.ts`, e2e and fixtures outside the default run (a sibling package compiles fine with a broken one); run those suites or name them un-run | fix the caller here; name the un-run suite |
| changes a read model's key or what `readById` or a pushed-down filter resolves | `grep -rn "<table_name>"` outside the owning module; check each consumer's access shape | one shared helper plus a guard test on the old shape |
| deletes or redefines a credential, header, auth mode or env contract | grep the templates that emit code using it (`.claude/skills/**`, plugin skills, scaffolding) | point the template at a helper |
| adds a reader of an already-persisted table, index or collection | enumerate every other writer; prove this key space cannot select their rows | narrow the query |
| touches event schemas, persisted field names or idempotency records | an upcaster or version bump per rename; a test on a row written before this diff | add it, or name the untested path |
| adds migrate-on-read or a reversible operation | both directions on the real adapter, tested; legacy migrates on write, newer refuses typed | one direction untested |
| adjusts a total, count or threshold | grep every other comparison against the unadjusted value; collapse duplicate computations into one exported function | fix both |
| introduces a mechanical guard | name the field its condition reads; enumerate every surface that can set it (tool schemas, HTTP bodies, payloads, defaults) | stamp at that surface |
| ships an "operate over my rows" endpoint | the tenant comes from the authenticated user into the filter; build the two-tenant repro | a body field or a system-wide scan |
| adds endpoints, operations, policies or registry nodes | the repo's own codegen or drift gate (`generate:check`) | drift; on a false assertion suspect a stale compiled `.js` before editing source |
| corrects a claim or removes a duplication | sweep synonyms of the belief; re-sweep every file this PR edited | a surviving copy |
| merges another branch in | `git diff --diff-filter=A --name-only <base>...<theirs>` ∩ files this side modified; read every added test's assertions there | an added oracle testing a replaced API |
| removes, in a later slice, a protection an earlier slice made unnecessary | state what the earlier slice covers and what the removal applies to | a non-empty difference |
| asserts a reason: a framework mechanism behind a guarantee, a blocker behind a skipped, `xfail` or tracer block | verify each against the framework's source or against `HEAD` | correct the reason, or uncover the path |
| always: cross-slice composition | enumerate the invariants, cursors and floors more than one slice touches; reason pairwise where one advances what another reads or trims against | two correct slices with a defect in the seam: a real finding |
| always: `Bin` in the diff-stat on a hand-authored path | `git diff --numstat` prints `-\t-\t<path>`; locate with `grep -aPn '[\x00-\x08\x0e-\x1f]'`; `grep` returning nothing on a file you just edited is a binary-classification symptom, so run `file` | a hard finding |

Where the plan names a tier the widest gate excludes, run it or say in the PR body that it was not run.

**Disprove every Critical before reporting it**: read the call site, not the hunk; `git blame` for pre-existing on `<resolved-base>`; construct a failing input; drop or downgrade what fails any of the three. Fix Critical and Medium before the PR, inline or as a fix slice appended to `.work/slices.yaml` with `origin: verify-build` and driven through `/build`; anything shipped unresolved carries a recommendation. The conclusions go into the PR body, except the counts Step 5b records. Done when every Critical is disproved or fixed and the counts by severity are noted.

## Step 4 — Dev verification checklist

One lean list of what a human confirms by hand because the slice tests cannot (UI, a browser smoke, environment), for the PR body. Done when each item names the path and what a pass looks like.

## Step 5 — ADRs

Every decision the resolved design owes an ADR is written now; deferring is an escalation. `Call the Skill tool with "domain-modeling"` for the format and the numbering.

- Re-measure the design's figures against the built code; quote the command and result.
- Re-resolve every path and symbol the ADR cites before committing.
- A deferral naming a sibling unit (`deferred to <UNIT>`, a grep over your resolved block) is done only once tracked where the sibling reads.
- A composition finding that traces to text the design or an ADR also asserts amends that text in the same fix.
- A rule true beyond this ticket goes into the ADR's Principle section or, for the flow, through `/capture-learnings`.
- A PR that adds an enforcement mechanism states which commit is its first live proof, or why none is: a gate that never fired is indistinguishable from a gate that cannot fire. A worked example the suite does not consume becomes a fixture, or says at its top that it is unexecutable.

Done when every owed ADR is committed and each citation resolves.

## Step 5a — Rule every concern

`concerns.md` is in `<path>`; when absent, this unit raised none: say so and write an empty `concerns.md` there, so "no concerns recorded" is a committed record.

**Rule each `## C<n>` entry** by its `verify:` instruction: `verdict:` is one of `met | partial | unmet | cannot-determine | waived`; `evidence:` is what you checked and saw in this run (a test result, a `file:line`, a measurement with its command); a `passes:` flag is not evidence, and the unchecked is `cannot-determine` with why. `quote:` stays the raising quote, `bar:` stays what the owner said, entries keep their ids.

**Only the owner waives.** A C-entry is `waived` only on the owner's own words, from this run, this conversation or the ticket; an agent's judgement or a paraphrase is not a waiver, and an unwaived hard concern keeps its ruling. To record one: append a D-entry to `<path>/decisions.md` in `/build`'s grammar with `kind: waiver`, `decidedBy: human`, `sources: [human]` and the next id. Its title names every C-entry it waives by id (`## D<n> — The owner waives C<n>: <label>`) and its body carries the owner's verbatim waiver quote. The C-entry then gets `verdict: waived`, and its `evidence:` cites it as `decisions.md#D<n>`, written without backticks or a path.

**Check it**, with `--decisions` as the first argument:

```bash
concerns-check --decisions "<path>/decisions.md" "<path>/concerns.md" > "${TMPDIR:-/tmp}/concerns-check.txt" 2>&1
```

Read its last line, `CONCERNS-CHECK:v1 outcome=pass|fail|error …`, never the exit code. `pass`: continue. `fail` or `error`: `/verify-build` opens the PR either way; the entries fill the body's *Unmet hard concerns* section and Step 6b posts `failure`. `outcome=error` is not-success, exactly like `outcome=fail`: neither a pass nor "no concerns". A verdict written from evidence stands; the line goes green only through new evidence or an owner waiver. `/merge-multi` is the hard block.

Commit `concerns.md`, plus `decisions.md` when a waiver was appended, on its own: `docs(record): rule the concerns`. Done when every entry carries a verdict and evidence and the verdict line is recorded for Steps 5b and 6b.

## Step 5a2 — Map drift

Each outcome is one line in the PR body's `### Record` section; nothing here blocks Step 6.

- `.work/lane.yaml` exists, or no map feed is advertised → `design-map drift <path>/map.json --no-feed` prints `outcome=skip reason=no-map-feed`; write `map drift: not checked: fleet-lane-no-feed` in a lane, else `map drift: not checked: no-map-feed`.
- `outcome=current` → nothing.
- `outcome=drifted` with a live feed → owner check first (`work-docs-path --item <work_item> --owner-branch "$(git branch --show-current)"`; any verdict but `owner=none|self` is flagged and nothing written), then refresh the map as `/design` Step 4 writes it: `get_map` → `design-map write` → `design-map render` → `map-tree write --map <path>/map.json --ticket <work_item> --insert-after "## Resolved decision tree" --on-tamper displace <path>/design.md` → the three-path `docs(<id>): design` commit, naming a `displaced` result as `map-tree: displaced`. A refused render or `map-tree` error is flagged, nothing committed.
- Any other `skip` or `error` → `map drift: not checked: <reason>`.

## Step 5b — Measure the run

`build-summary.md` is in `<path>`; when absent, say so, skip the fill, and still run both commands:

```bash
run-metrics --emit --quiet > "${TMPDIR:-/tmp}/run-metrics-report.txt" 2>&1
run-metrics --usage-fragment --quiet > "${TMPDIR:-/tmp}/usage-fragment.yaml" 2> "${TMPDIR:-/tmp}/usage-fragment.err"
```

The first records the run and prints the headline Step 7 pastes; the second prints the `usage` fragments as YAML ending in `# RUN-METRICS-USAGE:v1 outcome=ok …` or `outcome=error reason=…`, read as a line, never as an exit code. Dispatches are attributed by the `slice <id>` in their description, else `unattributed`.

**Usage is generated by `run-metrics`, never hand-written.** Every number is copied verbatim from the fragment into these blocks, keyed as `/build` keys its slices:

```yaml
slices:
  - id: <id>
    usage:
      executor:   { model: <model>, effort: <effort>, tokens: <n>, activeMs: <ms> }
      verifier:   { model: <model>, effort: <effort>, tokens: <n>, activeMs: <ms> }
      testRunner: { model: <model>, effort: <effort>, tokens: <n>, activeMs: <ms> }
verifyBuild:
  usage: { model: <model>, effort: <effort>, tokens: <n>, activeMs: <ms> }
```

- `outcome=ok` → each slice entry in `build-summary.md` gets the `usage:` of the fragment entry with the same `id`; a role printed as `null` stays `null`; a slice with no fragment entry gets `usage: null`, named in `## What shipped`. `verifyBuild.usage` is the fragment's, or `null`. A non-`null` `unattributed` block is quoted per role in `## What shipped`.
- `verifyBuild.gate`, `verifyBuild.coherence`, `verifyBuild.fixSlicesAdded` and `verifyBuild.adrs` are this run's own results, written on every outcome of the fragment: `gate: { mode, verdict, skipped, inconclusive }` from Step 2's report block; `coherence: { critical, medium, low, shippedUnresolved }` from Step 3; `fixSlicesAdded:` the number of fix slices Step 3 added; `adrs:` the ADRs Step 5 wrote or amended. `verifyBuild.concerns` is copied from Step 5a's verdict line: on `pass` or `fail`, `concerns: { hard, soft, unmet }` with `unmet` a list of ids (`none` is `[]`); on `error`, `concerns: null` and one line in `## What shipped`, `Concerns not checked: <the reason= value>.` Every value is copied from those steps' own reports, never estimated; a step that produced no report writes `null`.
- `droppedDetached=<n>` on the verdict line counts dispatches whose transcript is stamped `gitBranch: HEAD` (a detached checkout, such as a pool worktree): above 0, one sentence in `## What shipped` says `<n>` dispatches ran in a detached pool worktree and were not attributed; a `/start-multi` unit reports 0 because it is never branch-filtered — 0 means not measured.
- `outcome=error`, no verdict line, or a command that did not run → write `usage: null` on every slice and `verifyBuild.usage: null`, and one line in `## What shipped`: `Usage not measured: <the reason= value, or the error's first line>.` Never invent numbers.

Commit `build-summary.md` on its own: `docs(record): measure the run`. A failure to measure must never block landing the work: it is one line in your report plus the nulls above, and Step 6 runs regardless. Done when the commit exists and every `usage:` cell is copied from the fragment or `null`.

## Step 6 — Open the PR

Push the branch, then open the PR ready for review in a Bash call:

```bash
gh pr create --base <resolved-base> --title "<TICKET-ID> — <title>" --body-file "${TMPDIR:-/tmp}/pr-body.md"
```

No `--draft`. Then compare the PR's `changed_files` and `commits` with `git log <resolved-base>..HEAD` and retarget with `gh pr edit --base <true-base>` on a mismatch. Step 5a's `fail` or `error` fills the *Unmet hard concerns* section and Step 6b's status. Among verdicts, only Step 2's `FAIL` holds this step back.

**Report mergeability, not "opened".** Re-fetch `origin/<default>`: a moved base voids every gate that read the diff, so re-run those locally and report that; a red CI job hides every step after it, so run those locally by name and report each as `RAN LOCALLY: <step> exit N`. Read `gh pr view --json mergeable,mergeStateStatus` after a short settle. Fix a conflict by rebasing this branch in its own worktree, touching no other branch or stacked-on history.

**A stacked child is retargeted before its parent's branch is deleted**: deleting the base branch (`gh pr merge --delete-branch`, `git push --delete`) closes the child unmerged (`base_ref_deleted`, whatever `delete_branch_on_merge` says). `gh pr edit <n> --base <default>` first, delete the parent's branch once nothing targets it, and verify every merge with `git merge-base --is-ancestor origin/<head> origin/<default>`.

**A closing keyword binds to exactly one issue.** Repeat it per issue in the body and every commit message: `Closes #12, closes #13`; a bare list, `Closes #12 #13`, closes `#12` and leaves the rest as mentions. After the merge, assert the issues reached `CLOSED`:

```sh
for n in <every issue the PR references>; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

One line per reference, every one `CLOSED`; check the line count first, since a `gh` failure prints a blank state. Close stragglers with `gh issue close <n> -c "landed in #<pr>"`.

The body is a short summary plus links to the committed record; `<path>` is Step 1's `path=` and `<branch>` is this branch:

```
## <TICKET-ID> — <title>

<two to four sentences: what shipped and why; a summary, not the design>

### Record
- [design.md](https://github.com/<owner>/<repo>/blob/<branch>/<path>/design.md) — the design as resolved
- [decisions.md](https://github.com/<owner>/<repo>/blob/<branch>/<path>/decisions.md) — every decision made after it
- [concerns.md](https://github.com/<owner>/<repo>/blob/<branch>/<path>/concerns.md) — the owners' bars, ruled
- [build-summary.md](https://github.com/<owner>/<repo>/blob/<branch>/<path>/build-summary.md) — the run's telemetry
- <`design-map count <path>/map.json [--lane .work/lane.yaml] --line` output, verbatim: `N of M forks answered by the owner (…)`, `map: none` when the folder carries no map, or `map: owner answers not carried: run dir absent` when the brief carries `mapProvenance: lost`>
- <Step 5a2's drift line, if any>
- <`map-tree: displaced` when Step 5a2 reported it>

### Slices
- slice 1 — <name> (<commit>)
- slice 2 — <name> (<commit>)
- ...

### Oracle candidates
<report-only, read from .work/slices.yaml and .work/lane.yaml; it never refuses or delays opening the PR.
whenever slices.yaml carries `review: unattended`, first: Breakdown not human-reviewed (unattended /plan).
then the first form that applies:
lane.yaml carries `mapProvenance: lost` → Oracle candidates: none (owner answers not carried: run dir absent)
slices.yaml has no `candidateOracles` key → Oracle candidates: none (no map.json)
`review: unattended` → one bullet per unconfirmed candidate — `<fork>` / `<option>`: <scenario> — e.g. <example>
`review: human` → Oracle candidates: <confirmed> confirmed, <rejected> rejected>

### Unmet hard concerns
<only when Step 5a's outcome is fail or error; omit the section on pass.
fail: one bullet per bar: hard entry ruled partial, unmet or cannot-determine (or still at verdict: —) — `C<n>` — <its label> — the bar as raised: <quote:> — evidence: <evidence:>
error: the reason= and the C-entry and D-id the verdict line names>

### Verification
<the Step 2 gate report block verbatim, `GATE-MODE:` line included, or "Gate deferred to the fleet gate, run `<runId>`." plus the `--fast` result; then every SKIP, INCONCLUSIVE or excluded tier by name>

<the dev checklist from Step 4>

### Decisions
- ADR-NNN — <title> (+ Principle, if the ADR states one)

### Coherence review
<Critical/Medium findings and how resolved; or "clean">
```

Done when the PR is open against `<resolved-base>` with every section above and its mergeability is reported.

## Step 6b — Post the `flow/concerns` commit status

Post Step 5a's result on the head sha (`git rev-parse HEAD` after the push, equal to `gh pr view --json headRefOid -q .headRefOid`):

```bash
gh api repos/{owner}/{repo}/statuses/<head-sha> -f context=flow/concerns -f state=<failure|success> -f description="<description>" -f target_url=<blob URL of concerns.md on the branch> > "${TMPDIR:-/tmp}/flow-concerns-status.txt" 2>&1
```

One bullet per outcome, each mapped exactly once:

- `outcome=pass` → `state=success` — `concerns met: <hard> hard, <soft> soft`, or `no concerns recorded` when both are 0.
- `outcome=fail` → `state=failure` — `<k> hard concerns unmet: C1, C3`, naming the `unmet=` ids whose `bar:` is `hard`; with `reason=missing-verdict`, `<k> concerns unruled: <the missing= ids>`.
- `outcome=error` → `state=failure` — `concerns not checked: <the reason= value>`. No verdict line, or a `work-docs-path` error, lands here too.

The description is limited to 140 characters: drop C-ids from the end and close with `, +<n> more`.

A status belongs to one sha: on every later push this flow makes, re-run Step 5a's check on the new head and post again; nothing re-posts on a human's push. Advisory: a status cannot be required, so the red mark is advisory in a single flow, and nothing in this flow reads it back; `/merge-multi` is the hard block. A failed status post never blocks landing: a non-zero exit or an error body becomes one line in your report, `flow/concerns not posted: <its first error line>`. Done when the post is made or that line is written.

## Step 7 — Put what the run cost in the PR body

Paste the headline of Step 5b's report under the template (`gh pr edit --body-file`), or `Run cost: not measured — <its first error line>` if it errored:

```
### Run cost
elapsed <X>h · alive <Y>h (<duty>%) · <N> agents · <W> weighted tokens · +<A>/-<D> lines
first-pass green: <G>  ·  plugin <version>@<sha>  ·  <model>, effort <effort>
```

Two lines, no tables.

## Step 8 — Report

Report the PR URL; `.work/` is disposable now. Suggest `/capture-learnings` for flow learnings.

Verdict values: `success` when the gate is green and the PR is open; `gate-red` when Step 2 returned `FAIL`; `blocked-on` when a human must resolve something first. A `SKIP` or `INCONCLUSIVE` step, like a concerns `fail` or `error`, is named in the PR and still `success`. `lane-step-record` may commit the verdict, moving the head off the sha Step 6b posted on: when it printed `recorded=empty`, say so and post Step 6b's status again, unchanged, on the new head. Then the verdict line, as the protocol says.
