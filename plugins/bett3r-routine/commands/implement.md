---
description: Routine entry point. Implement one Blueprint ticket unattended from its fire (Specification v1 JSON) — cut its agentBranch, plan from blueprint.md, build, verify — and end with the trailer Blueprint reads (done or needs-human). No /start, no /design, no PR.
---

# /implement — the routine's implementation lane

The whole run of one Blueprint implementation dispatch. Blueprint already holds the agreed design (`blueprint.md`, written by the board session and grounded against the code there), so this lane does not design: it plans, builds and verifies, then signals the outcome with one git trailer. No human watches this session: ask no one anything.

**Argument** `$ARGUMENTS`: the fire Steward sent the routine, whole: one JSON object, Specification v1 §1 (`steward-pv4-sdlc/docs/specification.md`; the tenant writes it in `FireText`):

```json
{"specification":1,"key":"PROJ-1","title":"Reserve stock on checkout","branch":"PROJ-1-reserve-stock-on-checkout",
 "agentBranch":"claude/PROJ-1-reserve-stock-on-checkout","pullRequest":null,"design":"docs/prs/PROJ-1/blueprint.md",
 "signal":"Blueprint-Status","answer":null,"options":{}}
```

## Step 1 — Read the fire

Write `$ARGUMENTS` verbatim to `${TMPDIR:-/tmp}/fire.json` with the Write tool (no shell quoting of it), then:

```bash
node -e '
const f = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
if (f === null || typeof f !== "object" || f.specification !== 1) throw new Error("specification is " + JSON.stringify(f && f.specification) + ", not 1")
for (const k of ["key", "branch", "agentBranch", "design", "signal"]) if (typeof f[k] !== "string" || !f[k]) throw new Error(k + " is missing")
if (f.agentBranch !== "claude/" + f.branch) throw new Error("agentBranch " + f.agentBranch + " is not claude/" + f.branch)
console.log(JSON.stringify(f, null, 1))' "${TMPDIR:-/tmp}/fire.json"
```

It fails (not JSON, `specification` not `1`, a field missing, or `agentBranch` not `claude/` + `branch`): **stop**. Say why, citing its error, and create no branch, write no other file, run no other command. There is no needs-human without a branch to signal on, and there is no prose fallback. Otherwise take:

- `KEY` ← `key`; `TICKET_BRANCH` ← `branch`; `DESIGN` ← `design`; `TRAILER` ← `signal`, e.g. `Blueprint-Status`.
- `WORK_BRANCH` ← `agentBranch`: Steward merges that branch, and only that one, into the ticket branch.
- `ANSWER` ← `answer`: the person's reply to the last needs-human, or `null` on a first fire. Not null, it is what the human decided: it goes into the brief (Step 4) and the plan reads it.
- `OPTIONS` ← `options`, passed through untouched in the brief.
- `title` and `pullRequest` are for information only.

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

Do not run `/design` and do not write `design.md`. The folder belongs to Blueprint: `blueprint.md`, `decisions.md` (the board's decisions; `/build` appends its `D<n>` entries after them), `scaffold.json`, and the bundle under `blueprint/`. Never edit `blueprint.md` or anything under `blueprint/`; Steward's flush rewrites them.

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
   answer: <ANSWER as a JSON string, or null>
   options: <OPTIONS as compact JSON>
   ```

   It marks every step as an unattended lane; `design:` is what `/routine-plan` and `/routine-verify` read, and `answer:` is the context `/routine-plan` plans the re-fire with. JSON is YAML, so write both values as `JSON.stringify` prints them.
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

Steward reads one trailer off the commits on `<WORK_BRANCH>`. Write the signal as its own commit, so it always carries the run's record even when every earlier commit is already pushed. It also carries the run's metrics, `<dirname DESIGN>/run-metrics.json`, which Steward reads at the signal's sha:

```bash
M="$(dirname "<DESIGN>")/run-metrics.json"
if run-metrics "<WORK_BRANCH>" --routine-metrics > "${TMPDIR:-/tmp}/run-metrics.json" 2> "${TMPDIR:-/tmp}/run-metrics.err"; then
  mkdir -p "$(dirname "$M")" && cp "${TMPDIR:-/tmp}/run-metrics.json" "$M" && git add -- "$M"
fi
git commit --allow-empty --cleanup=verbatim -F "${TMPDIR:-/tmp}/signal.txt"
git push -u origin "<WORK_BRANCH>"
```

`run-metrics --routine-metrics` prints one compact object, `schema: 1`, of the run's scalars read from this session's transcripts (a run with none prints `{"schema":1}`). **A metrics failure never blocks the signal and never changes the trailer:** when the command fails, commit without the file and add one line to the body, `run-metrics: not recorded (<first line of run-metrics.err>)`.

The message file:

```
<subject>

<body: one short paragraph — what shipped, or exactly what a human must do and where>

<every LANE-STEP:v1 line Step 5 collected, one per line, in order>

<only when the metrics failed: run-metrics: not recorded (<reason>)>

<TRAILER>: <done|needs-human>
```

- **Done** (Step 5 ended with `/routine-verify` `success`): subject `<KEY>: implementation done`, trailer `<TRAILER>: done`. Steward then merges `<WORK_BRANCH>` into the ticket branch and readies the PR.
- **Needs a human** (any stop above): the subject says why in one line, e.g. `<KEY>: build gate-red on slice 3`, trailer `<TRAILER>: needs-human`. Everything already committed stays pushed; the body names the step, the blocking line and what the human does next (fix on `<TICKET_BRANCH>` and re-fire, which resumes on this branch).

A refused push: say so with git's output, and stop. Then report the trailer you wrote, the branch, and every `LANE-STEP` line.

## Boundaries

- No `/start`, no `/design`, no `design.md`: the design is `blueprint.md`, agreed on the board.
- One branch, `<WORK_BRANCH>`; no pull request, no commit status, no tracker writes. Blueprint moves the ticket from the trailer.
- One file outside the lane's own record: `run-metrics.json` beside the design, in the signal commit only.
- A step's verdict is its `LANE-STEP` line, never your reading of its prose.
