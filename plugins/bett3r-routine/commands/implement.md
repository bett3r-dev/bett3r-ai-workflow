---
description: Routine entry point. Implement one Blueprint ticket unattended from its dispatch text — cut claude/<branch>, plan from blueprint.md, build, verify — and end with the trailer Blueprint reads (done or needs-human). No /start, no /design, no PR.
---

# /implement — the routine's implementation lane

The whole run of one Blueprint implementation dispatch. Blueprint already holds the agreed design (`blueprint.md`, written by the board session and grounded against the code there), so this lane does not design: it plans, builds and verifies, then signals the outcome with one git trailer. No human watches this session: ask no one anything.

**Argument** `$ARGUMENTS`: the dispatch text Blueprint fired the routine with, whole. Its lines, composed by Blueprint's `implementationDispatchText`:

```
Implement <KEY>[: <title>].
Branch: <ticket branch>. Work on claude/<ticket branch>, cut from <ticket branch>, and push only to claude/<ticket branch>; ...
Pull request: <url> | Pull request: none is recorded for this branch.
Design: <docsRoot>/<KEY>/blueprint.md on that branch (...)
When the implementation is complete, end your last commit's message with the git trailer "<TRAILER>: done". ...
```

## Step 1 — Read the dispatch

Take four values from `$ARGUMENTS`:

- `KEY`: the ticket key in `Implement <KEY>`, up to the first `:` or `.`.
- `TICKET_BRANCH`: the value after `Branch: `, up to the `.` that ends it.
- `DESIGN`: the path after `Design: `, up to ` on that branch`.
- `TRAILER`: the key before `: done` in the quoted trailer, e.g. `Blueprint-Status`.

If any is missing, **stop**: say which, and create no branch, write no file, run no command. Nothing can be signalled without a branch. Let `WORK_BRANCH` be `claude/<TICKET_BRANCH>`; Blueprint merges that branch, and only that one, into the ticket branch (its `agentBranchOf` must keep this prefix).

## Step 2 — The work branch

```bash
git fetch origin "<TICKET_BRANCH>:refs/remotes/origin/<TICKET_BRANCH>"
git ls-remote --exit-code --heads origin "<WORK_BRANCH>"
```

- **No `WORK_BRANCH` on origin** (exit 2): `git checkout --no-track -b <WORK_BRANCH> origin/<TICKET_BRANCH>`.
- **It exists** (a re-fire after a needs-human): fetch it the same way, `git checkout -B <WORK_BRANCH> origin/<WORK_BRANCH>`, then `git merge --no-edit origin/<TICKET_BRANCH>` so the run sees what a human fixed on the ticket branch since. Cutting fresh instead would make the final push non-fast-forward. A conflicting merge: `git merge --abort`, then signal needs-human (Step 7) with subject `<KEY>: claude/ branch conflicts with <TICKET_BRANCH>`.
- The fetch fails: **stop** and say so; never start from the default branch.

**You push only to `<WORK_BRANCH>`**, whatever any later step or command says. Never push to `<TICKET_BRANCH>` or the default branch, and never open a pull request: Blueprint owns the ticket's PR.

## Step 3 — The design and the record folder

1. `DESIGN` must exist on this branch. Absent: needs-human, `<KEY>: no design at <DESIGN>`.
2. Run `work-docs-path --item <KEY>` and read its last line. Its `path=` must equal `dirname <DESIGN>`: it is the folder `/build` writes `decisions.md` and `build-summary.md` into, and a record beside a different design is one nobody reads together. `outcome=error` or a different folder: needs-human, naming both paths.

Do not run `/design` and do not write `design.md`. The folder belongs to Blueprint: `blueprint.md`, `decisions.md` (the board's decisions; `/build` appends its `D<n>` entries after them), `scaffold.json`, and the bundle under `blueprint/`. Never edit `blueprint.md` or anything under `blueprint/`; the runner's flush rewrites them.

## Step 4 — Working state

This replaces `/start`, which would cut or rename branches and scrub the brief.

1. `.work/` is working state, never committed: if `git check-ignore -q .work/x` fails, append `.work/` to `.git/info/exclude` (not `.gitignore`, which would put a commit on the ticket's diff).
2. Write `.work/lane.yaml`:

   ```yaml
   verdictOnBranch: true
   branch: <WORK_BRANCH>
   work_item: <KEY>
   worktree: <output of pwd>
   design: <DESIGN>
   ```

   It marks every step as an unattended lane; `design:` is what `/routine-plan` and `/routine-verify` read.
3. Write `.work/mode.yaml` with `mode: start`, `work_item: <KEY>`, `branch: <WORK_BRANCH>`, `updated:` now (ISO-8601 UTC).
4. Write `.work/known-baseline-failures.md`: the base sha (`git rev-parse origin/<TICKET_BRANCH>`), the branch, and the line `not captured — capture on demand`.

## Step 5 — Plan, build, verify

Invoke each as its bare slash command, in order. Each ends by printing a `LANE-STEP:v1` line and saying to take no turn after it: that ends **the step**, not this command. Read the line, keep it for Step 7, and continue here.

1. `/routine-plan`. Anything but `outcome=success`: needs-human, citing its line.
2. `/build`. It yields after a slice budget with `outcome=success slices=<k>/<N>` and `k < N`: invoke `/build` again, which resumes from the slices marked `passes: true`, until `k = N`. Stop re-invoking after 6 invocations, or when one completes no new slice; either is needs-human. `outcome=gate-red` or `blocked-on`, or no `LANE-STEP` line at all: needs-human, citing what it reported.
3. `/routine-verify`. `outcome=success`: done. Anything else: needs-human, citing its line.

## Step 6 — Before signalling

`git status --short` shows nothing but ignored state, and `git log origin/<TICKET_BRANCH>..HEAD` lists the slice commits you expect. Any uncommitted change that a step left behind is reported in the signal commit's body, not committed blindly.

## Step 7 — Signal the outcome

Blueprint reads one trailer off the commits on `<WORK_BRANCH>`. Write the signal as its own commit, so it always carries the run's record even when every earlier commit is already pushed:

```bash
git commit --allow-empty --cleanup=verbatim -F "${TMPDIR:-/tmp}/signal.txt"
git push -u origin "<WORK_BRANCH>"
```

The message file:

```
<subject>

<body: one short paragraph — what shipped, or exactly what a human must do and where>

<every LANE-STEP:v1 line Step 5 collected, one per line, in order>

<TRAILER>: <done|needs-human>
```

- **Done** (Step 5 ended with `/routine-verify` `success`): subject `<KEY>: implementation done`, trailer `<TRAILER>: done`. Blueprint then merges `<WORK_BRANCH>` into the ticket branch and readies the PR.
- **Needs a human** (any stop above): the subject says why in one line, e.g. `<KEY>: build gate-red on slice 3`, trailer `<TRAILER>: needs-human`. Everything already committed stays pushed; the body names the step, the blocking line and what the human does next (fix on `<TICKET_BRANCH>` and re-fire, which resumes on this branch).

A refused push: say so with git's output, and stop. Then report the trailer you wrote, the branch, and every `LANE-STEP` line.

## Boundaries

- No `/start`, no `/design`, no `design.md`: the design is `blueprint.md`, agreed on the board.
- One branch, `<WORK_BRANCH>`; no pull request, no commit status, no tracker writes. Blueprint moves the ticket from the trailer.
- A step's verdict is its `LANE-STEP` line, never your reading of its prose.
