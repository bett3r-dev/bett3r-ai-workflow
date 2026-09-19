# /build — the committed record

*Companion to `/build`, read when writing `decisions.md` and `build-summary.md`; not a step to run on its own.*

Both files live in the folder Step 1 resolved with `work-docs-path --item <work_item>`, `.work/slices.yaml` stays working state.

## One writer

The orchestrator is the single writer of `decisions.md` and `build-summary.md`. Executors, verifiers and pool workers never write `decisions.md` or `build-summary.md`: they report each decision and fact in their result, and you write it in the main tree.

## `decisions.md`: every decision made after the design

One entry per post-design decision; the `kind` enum below names the six. Sources: the executor's flagged deviations, the verifier's per-item verdicts, your fix-round classifications (`design-silent` names a filled seam), every human decision on an `ESCALATE`. The header is fixed:

```markdown
## D1 — <one-line decision>
kind: silent-seam        # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: build · slice: 2 · decidedBy: executor    # executor | verifier | orchestrator | lane | human
sources: [code:<symbol> (<file>), adr:ADR-NNN, design:<section>, xp:<atom-id>, human]
rejected: <option> — <why not>
supersedes: —            # set when this overturns an earlier entry
<prose: why>
```

- `sources` records what was consulted; there is no confidence field.
- `slice:` is the slice id, or `—` for the plan as a whole; `rejected:` the options not taken, or `—`; `supersedes:` `—` or the earlier id(s) overturned (`D3` or `D3, D5`). Append-only: an overturned entry stays as written.
- Ids: the highest in the file plus one, read at the moment you append.
- When: right after the slice's commit (in a pool, its land), committed on its own as `docs(record): …`, in the same turn and before the next land. An `ESCALATE`'s human decision is appended when the human decides.

## `build-summary.md`: the run's telemetry

Written when `/build` ends, green **or partial**: on `success`, `gate-red`, and a `blocked-on` after any slice ran; before the verdict line; committed. Skipped only when the run stopped before any slice ran (a Step 1 `work-docs-path` error, a Step 2 `size` error). Keys are spelled `work_item:`, not `workItem:`, as `.work/mode.yaml` spells it.

```markdown
---
work_item: <work_item, as .work/mode.yaml records it>
plugin: bett3r-ai-workflow@<version>+<sha>
base: <sha the task branch was cut from>
slices:
  - id: 1
    name: <slice name>
    origin: plan                     # plan | verify-build (fix slice)
    mode: sequential                 # sequential | worktree | null
    modeReason: pool=0               # sequential only — the Step 2 branch: pool=0 | provision-refused | provision-failed | no-verdict-line | ready-alone | worktrees-retired; null otherwise
    commit: <landed sha>             # null when it did not land, or when its landed sha cannot be proven
    passed: true
    attempts: 1                      # executor passes; 0 = never started; 1 = first-pass green; null = passed in an earlier session with no record of it
    fixRounds: []                    # one per fix round: { cause: <Step 3 class>, executor: continued | fresh }; null = passed in an earlier session with no record of it
    verifier: pass                   # the final verdict: pass | retry | escalate; null = no verifier ran
    redBeforeGreen: true             # true | mutation | null
    postDesignDecisions: [D1]        # ids into decisions.md; [] = explicitly none
---
## What shipped
<short prose: outcome, root causes, what a future agent should know>
```

- Every slice in `.work/slices.yaml` gets an entry, in plan order. `id` and `name` come from `.work/slices.yaml` and are never `null`; `origin` is the slice's own `origin:` field in `.work/slices.yaml`, else `plan`.
- A slice no run has started: `mode: null`, `modeReason: null`, `commit: null`, `passed: false`, `attempts: 0`, `fixRounds: []`, `verifier: null`, `redBeforeGreen: null`, `postDesignDecisions:` the ids `decisions.md` records for it.
- Zero decisions is written `postDesignDecisions: []`, never an absent key.
- Read the existing file first. A slice this run did not run keeps its existing entry from `build-summary.md` verbatim only when that entry's `passed` matches the slice's `passes:` flag in `.work/slices.yaml`; a disagreeing entry is stale and is rewritten from the flag: a `passes: true` slice as the next bullet, a `passes: false` one keeps its entry with `passed: false` and `commit: null`. An entry with the pre-rename `retries:` key: read it as `fixRounds:` and write it back as `fixRounds:`.
- A slice an earlier session passed, with no entry or a stale one: `commit:`, `passed: true` and `postDesignDecisions:` from `decisions.md`, plus `id`, `name`, `origin`; `mode`, `modeReason`, `attempts`, `fixRounds`, `verifier` and `redBeforeGreen` are `null`, never a guessed value.
- `commit:` is the landed sha `.work/slices.yaml` records (a pool slice); else the one commit `git log --format=%H -E --grep '^Slice <id> of <work_item> ' <base>..HEAD` finds, `<base>` being the frontmatter's `base:` (anchored and space-terminated so `KEY-2` never matches `KEY-27`, ranged to this work item's history). When neither yields exactly one commit, write `commit: null` and name the slice and reason in `## What shipped`; never pick one. `passed: true` with `commit: null` is legal: the flag says it landed, the record says its commit could not be proven.
- A slice this run ran that did not land: `passed: false`, `commit: null`, its last verifier verdict.
- `mode:` is `worktree` for a pool slice, `sequential` for a main-tree one; `modeReason:` names which Step 2 branch sent a `sequential` slice there.
- The `usage` blocks and the `verifyBuild` block are not written here: they are generated later by `/verify-build` from `run-metrics`; when the file already carries them, rewrite only the keys above.
