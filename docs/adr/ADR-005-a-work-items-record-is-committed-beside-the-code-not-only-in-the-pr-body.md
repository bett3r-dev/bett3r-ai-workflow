# A work item's record is committed beside the code, not only in the PR body

The plugin's third commit set a rule that no ADR ever recorded. `62b4f85` (2026-06-19) wrote into the
README's Core principles: *"Git is the system of record. One commit per slice. The PR description
carries the design narrative + per-slice summary. ADRs capture decisions. Nothing else is kept."* The
commands followed it. `build.md` said *"No `build-progress.md`, no `build-summary.md`. The commits and
`passes` flags are the truth."* `verify-build.md` said the design *"become[s] the **PR description** —
they are *not* committed as a standalone doc"*, and that `.work/` *"may be discarded"*.

```sh
git log --oneline -S"Nothing else is kept" -- plugins        # → 62b4f85, the only commit adding it
git show f2fa61e:plugins/bett3r-ai-workflow/commands/build.md | sed -n 187p
git show f2fa61e:plugins/bett3r-ai-workflow/commands/verify-build.md | sed -n '107p;181p'
```

**We reversed it.** Every work item now leaves a committed folder beside the code, holding its design,
its post-design decisions, its owners' concerns and its build telemetry. The PR body is a short summary
that links that folder. ADRs still own the decisions that outlive a work item. This ADR changes where a
work item's record lives. It does not change what an ADR is for.

## Why the rule failed: the knowledge left and nothing caught it

**The folders stopped.** teselly used to commit a `docs/prs/<ticket>/` folder per PR. Its own rules then
retired that convention, and the flow's rule forbade replacing it. Re-measured for this ADR against the
local teselly checkout (`master` at `a56bbf629`, not fetched — offline), counting each folder in the
month its first file was added:

```sh
cd ../teselly
git log --reverse --diff-filter=A --name-only --format='@%as' master -- docs/prs \
  | awk '/^@/{d=substr($0,2,7);next} /^docs\/prs\/[^\/]+\//{split($0,a,"/"); if(!(a[3] in s)){s[a[3]]=d; c[d]++}} END{for(m in c) print m, c[m]}' | sort
```

| 2026 | Mar | Apr | May | Jun | Jul | Aug | Sep (to the 12th) |
|---|---|---|---|---|---|---|---|
| new folders | 55 | 37 | 51 | 41 | 15 | 13 | 0 |

These match the design's figures. The design did not record the command it used. The table above uses
author dates (`%as`). With committer dates (`%cs`), one March folder moves to May, giving 54 and 52. The
collapse is the same either way.

The corpus those months left behind, also re-measured and unchanged from the design:

```sh
ls ../teselly/docs/prs | wc -l                                            # → 212
for n in build-summary.md concerns.md context.md sdd.md decisions.md; do
  ls -d ../teselly/docs/prs/*/$n | wc -l; done                            # → 167 28 192 162 30
ls ../esas/docs/prs | wc -l; ls ../pv3/docs/prs | wc -l                   # → 3, 16
```

**The PR bodies did not absorb it.** The design measured the last three teselly PR bodies at 728–2,990
bytes, with no forks and no rejected options. That figure came from `gh` during the design on
2026-09-12. The design did not record the exact command, and it was **not re-measured** here, because
this ADR was written offline.

**The store was supposed to catch it, and captures nothing.** The rule seemed safe because the
experience layer "already captures `.work/`". Its capture rules do keep design prose (`glob/design`, in
`bett3r-xp-layer/packages/xp-capture/src/rules.ts`). But the hooks do nothing without an executable
`.xp-layer/capture` in the host repo, and neither consuming repo has one. Re-measured:

```sh
ls ../teselly/.xp-layer ../esas/.xp-layer    # → No such file or directory (both)
```

A rule that throws knowledge away because something else captures it is only as good as a
measurement that the capture happens. Nobody took that measurement until this design.

## What we did instead

### Four files, one copy each, at the work-docs root

| File | What it is | Its reader |
|---|---|---|
| `design.md` | the design as resolved: forks, chosen answers, rejected options | humans, `/plan`, `/build`, `/verify-build` (knowledge) |
| `decisions.md` | an append-only log of every decision made after the design | nobody in this plugin yet (knowledge, process measurement) |
| `concerns.md` | the owners' stated bars, with attribution, ruled at landing | `/verify-build`, `concerns-check`, `/merge-multi` |
| `build-summary.md` | telemetry: YAML frontmatter measurements plus short prose | nobody in this plugin yet (metrics, not knowledge) |

Every file has one committed copy and no mirror in `.work/`. `/design` writes `design.md` straight to
the committed path, and every reader moved there. Before this work item, 26 references in 10 plugin
files pointed at the old gitignored design path. None do now:

```sh
git grep -o '\.work/design\.md' f2fa61e -- plugins/bett3r-ai-workflow | wc -l   # → 26 (git grep -l … | wc -l → 10 files)
grep -rho '\.work/design\.md' plugins/bett3r-ai-workflow | wc -l                  # → 0
```

`.work/` keeps working state only: `slices.yaml`, `mode.yaml`, `lane.yaml`, `learnings.md`, `handoff/`
and `known-baseline-failures.md`.

**Knowledge and telemetry are kept apart on purpose.** `build-summary.md` holds numbers. If a store
extracts knowledge from it, those numbers become false facts. The backfill rules still rule
`build-summary*` as `extract` (`shape/build-summary`, `bett3r-xp-layer/packages/xp-backfill/src/rules.ts`).
Routing that file to metrics is a follow-up (below). The file is markdown rather than YAML for a
measured reason: the store's `junk/yaml` rule drops `*.{yaml,yml}`, so a `.yaml` file never reaches it.

### Where the folder is: `work-docs-path`

The folder comes from one script, `bin/work-docs-path` (`scripts/work-docs-path.py`), never from prose.
The design fixed the rule but named no mechanism. A tested script replaced ten prose copies of one rule
(decisions.md D3). The root is `docs/prs` unless `.claude/bett3r-ai-workflow.json` sets `workDocsRoot`.
A root inside `.work/` is refused (D17). The rule was not put in `.esas.config.json`, because ADR-003
keeps the flow store-agnostic. The folder name comes from the work item's id:

| work item | folder |
|---|---|
| Jira key `TV1-2400` | `TV1-2400/` |
| GitHub issue `#268` | `gh-268/` |
| no id | `<yyyy-mm-dd>-<slug>/`, dated **once, at `/start`** |
| fleet run id | `multi-<words>/`, mixed case kept as written |

Three rows differ from the design:

- **A no-id work item is dated when `/start` runs, and the whole flow carries that exact id**
  (D36). The design derived the date when the folder was written. A branch name reused on a later day
  then found the old folder and overwrote an unrelated design.
- **A design folder's owner is recorded in the design itself** (D29, which supersedes D18). `design.md`
  opens with a `work_item` + `branch` header. The script decides `owner=none|self|other|unowned` from
  that header, and `/design` writes only on `none` or `self`. The first build inferred ownership from git
  history. That falsely claimed other work items' folders in stacked, merged-feature and stale-origin
  branches. The accepted cost: renaming a branch causes a false stop.
- **Run ids are a fourth shape** (D90). Fleets needed one. It is described below.

### `decisions.md` measures the design

`design.md` holds the tree as resolved. Every later departure appends an entry to `decisions.md`: a
deviation, a silent seam someone filled, a false premise, a knowingly shipped finding, an overrule or a
waiver. The header is fixed so entries can be counted:

```markdown
## D<n> — <one-line decision>
kind: false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: <step> · slice: <id or —> · decidedBy: executor | verifier | orchestrator | lane | human
sources: [...]
rejected: <option — why not, or —>
supersedes: <ids or —>
```

This file is what keeps the record from being scratch. Its entry count per work item, grouped by plugin
version, is a design-to-build drift rate, and `run-metrics` cannot see that rate. The header records what
was consulted (`sources`), never a confidence score. How good a decision was shows in whether a later
entry supersedes it. Zero decisions is stated as `postDesignDecisions: []` in `build-summary.md`, so an
empty or missing log is never read as zero (D43).

**There is one writer.** `/build`'s orchestrator allocates every `D` id. Executors, verifiers and pool
workers report their decisions in their results and never touch the file (design critique C1: parallel
appends would conflict on every cherry-pick). Each slice's entries land in their own `docs(record)`
commit right after the slice lands (D44). So a branch holds **one slice commit per slice**, not one
commit per slice, and the README says that now (D49). For a fleet, the run-level file's single writer is
`/merge-multi`.

### `build-summary.md`: `/build` writes it, `/verify-build` completes it

`/build` writes and commits the `slices` block in Step 6 whenever any slice ran, whether the run was
green, gate-red or blocked (D45). `/verify-build` Step 5b then fills `verifyBuild` from its own
reports, and fills `usage` from `run-metrics --usage-fragment`, before the PR opens (D72, D74, D77).
Usage is **generated, never hand-written**: an agent cannot observe its own tokens. A measurement that
failed is written as `null` with a reason, never as numbers (D75). The frontmatter spells `work_item:`,
not the design's `workItem:`, so the key matches the marker and the ownership header (D42).

**R7 shipped only in part** (D71). `run-metrics` drops a subagent whose dominant `gitBranch` differs from
the task branch. A pool worker on a detached checkout would be stamped `HEAD`, so its usage is **counted
(`droppedDetached=<n>`), not attributed** to a slice, and `/verify-build` names the undercount. No agent
was ever dispatched into a pool worktree during this work item, so the case has never been observed
either way. Check it against a real pool run when one exists.

### Concerns: captured with attribution, checked closed, blocked at the fleet merge

- **Capture.** The `concern` skill (`skills/concern/SKILL.md`) records an owner's bar the moment it is
  stated, from any step: `bar: hard | soft`, who raised it and at which step, and a verbatim quote.
  `/design` also seeds concerns from explicit bars in the ticket (D67).
- **Check.** `bin/concerns-check` takes a file path and prints a `CONCERNS-CHECK:v1` verdict line
  (ADR-004). It **fails closed**. A hard concern ruled `partial`, `unmet` or `cannot-determine`, or not
  ruled at all, is `fail`. A malformed, missing or unreadable file is `error`, and `error` counts as
  failure exactly like `fail` (D61, D62, D64). A file with no entries passes only when it is empty, and
  `/verify-build` commits an empty `concerns.md` for a unit with none, as "no concerns recorded" (D80).
- **Waivers belong to the owner alone.** This differs from the design in two ways. The entry's `quote:`
  stays the quote that raised the concern and is never overwritten (D63). A waiver is its own
  `decisions.md` entry, with `kind: waiver` and `decidedBy: human`, the owner's verbatim words, and a
  title that names each concern it waives (`## D<n> — The owner waives C<n>: …`) (D82). The waived
  concern's `evidence:` cites that entry, and `concerns-check --decisions` checks the citation against
  **the unit's own** `decisions.md` (D81). The check proves the waiver's structure, not who wrote it
  (D85).
- **The status is advisory.** `/verify-build` rules every concern, opens the PR either way, and posts a
  `flow/concerns` commit status on the head. teselly is a private repo on GitHub's free plan, where
  branch protection and rulesets are unavailable (the design measured `403 Upgrade to GitHub Pro`; not
  re-measured here). So the status cannot be required, and a human can merge over a red one.
- **`/merge-multi` is the hard block.** It never trusts the status. It reads each unit's `concerns.md`
  and `decisions.md` from the unit's head commit and runs `concerns-check --decisions` itself. Only
  `outcome=pass` merges. `fail`, `error`, a missing verdict line and a missing `concerns.md` all refuse
  (D88). A refused unit also removes the units stacked on it, and only the exact head sha that was
  checked is merged (D89). The unit's work item comes from its lane's state file, never from its unit id
  (D91). `commands/merge-multi.md` is pinned whole by `scripts/test-merge-multi-concerns.sh` (D94),
  because narrower guards each let through a rewording that made it merge an unchecked unit or trust
  the status.

This work item carries its own `docs/prs/XL-27/concerns.md`: three bars the owner approved, quoted from
the ticket (D87). Its `/verify-build` is the first live run of the check.

### Parallel slices run in a worktree pool

Slices that are ready together run concurrently, each in its own worktree. A shared tree is not safe for
this: whole-repo build output, half-written files, generators, the lockfile and the git index all
collide. The mechanics are a tested script, `bin/worktree-pool` (`scripts/test-worktree-pool.sh`), with
the subcommands `size`, `provision`, `reset`, `land` and `teardown`, each printing a verdict line.

- **Pool size** is `min(DAG width, --max-parallel, worktreePoolMax)`. A width of 1 means no pool.
- **`worktreePoolMax` is a venue key** in `.work/lane.yaml`, the same mechanism as `gateDeferred`: one
  command set, with the venue expressed as a key. A dispatch to Anthropic cloud runners is meant to write
  `4` (30 GB VM). Local and internal runs write nothing, so there is no cap. `/build` only reads the key.
  Which component writes it belongs to the scheduler, and is deliberately unspecified.
- **Reset before every take, unconditionally.** Before each slice: switch to the task-branch tip,
  `git clean -fd`, install, build, even when nothing changed. A reused tree otherwise inherits stale
  build output (`remote-ai-agents` D6), and staleness should cost time, never correctness. `provision`
  only cuts the worktrees; install and build live only in `reset`, so there is one path for warm and cold
  trees (D5).
- **Landing is a cherry-pick in dependency order**, refused unless the sha is after that worktree's reset
  (D6). A worktree whose slice did not land takes no further slice (D8). Teardown refuses while any work
  is unlanded.

### Fleets: each lane its own folder, the run its own `decisions.md`

A lane's `/design`, `/build` and `/verify-build` write that unit's own folder on its unit branch, exactly
as a single flow does. A lane cannot cite a sibling lane's design until they merge. `/start-multi`
documents that limitation, and no machinery works around it. `/merge-multi` writes its conflict
resolutions to `<root>/<run-id>/decisions.md` for every fleet run. The design put that file under an
epic id, but `run.yaml` has no epic field (D90). The design also had this file restate `/design-multi`'s
Phase B cross-cutting policies. **That was dropped** (D92): each unit's committed `design.md` already
carries them, and the only source was a gitignored file in the main checkout. If `work-docs-path` refuses
a run id, no run-level entry is written, the refusal is noted in the integration PR body, and merging
continues (D93).

## Other differences from the design

- The release bump is `0.67.0 → 0.68.0`, not `0.65.0 → 0.66.0`, because master had already shipped
  `0.67.0` (D1).
- The PR body keeps Slices, Verification, the dev checklist, Decisions, Coherence review and Run cost. It
  adds a Record section linking the four files, and an Unmet hard concerns section when the check fails
  or errors (D84).

## Not done here: follow-ups in other repos

- **`decisions.md` and `build-summary.md` have no reader in this plugin yet.** They are written for a
  consumer that does not exist. In `bett3r-xp-layer`: route `build-summary.md` to a metrics ingest
  instead of the `shape/build-summary` extract rule, and add a consumer that counts `decisions.md`
  entries by `kind` per plugin version. Until then the drift rate is recorded but nobody reads it.
- **teselly's own docs are stale.** `.claude/rules/README.md:41` says `docs/prs/` remains *"as history
  only"*, and `.claude/commands/diagnose.md:171` tells readers to look for `context.md` and `sdd.md`
  there. Both need updating.
- Later, if wanted: a GitHub App for Check Runs instead of a commit status.

## Considered options

- **Commit the design only when `/verify-build` lands it.** Citations in between would be dead, and an
  abandoned unit's design, rejected options included, would be lost.
- **Keep a `.work/` copy and a committed copy.** Two copies, and nothing checks that they agree.
- **Rely on the store to capture `.work/`.** Measured above: nothing captures it anywhere today.
- **Put everything in the PR body.** That is what the old rule asked for, and the measured bodies did not
  hold it.
- **Make the concerns status a required check.** Unavailable on the consuming repo's plan. That is why
  `/merge-multi` checks for itself.

## Principle

A rule that discards knowledge because something downstream will capture it rests on a premise, so
measure the premise before relying on it. A rule that keeps knowledge must name the reader it keeps
it for, and must say plainly when that reader does not exist yet.

## Status

Accepted. Reverses an unrecorded founding principle (`62b4f85`), and supersedes no ADR. Leaves ADR-001
(the version bump) and ADR-004 (verdict lines, which `concerns-check` and `worktree-pool` follow)
unchanged, and keeps ADR-003's store-agnostic invariant: the work-docs root is the plugin's own
configuration, not the store's.
