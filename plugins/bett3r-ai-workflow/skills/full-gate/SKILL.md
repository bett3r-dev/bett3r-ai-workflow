---
name: full-gate
description: Discover and run the host repo's full validation gate (`.claude/gate.sh`) and read its verdict correctly. Use when a flow step needs to certify a branch — /verify-build's per-unit gate, /merge-multi's integration gate — or when deciding which commands constitute "the tests" in an unfamiliar repo.
---

# Full gate — the host repo declares what "green" means

**The plugin does not know this repo's test commands.** `yarn test` is a guess, and it has been the wrong one: a repo has `test`, `test:integration`, `generate-all`, `lint`, `gate`, `build` and `typecheck`, of which only some belong in a routine gate — and the split differs per repo. Hardcoding it into a flow command produces a gate that is either too slow to run or too narrow to mean anything.

So the host repo declares its own gate, and the flow discovers it.

## The convention

**`.claude/gate.mjs`** at the host repo root, run as `node .claude/gate.mjs <mode>`, accepting exactly one argument:

| Invocation | Contains | Who runs it |
|---|---|---|
| `node .claude/gate.mjs --fast` | The cheap structural checks — typically `build` + `typecheck`. Seconds-to-a-minute. | Every `/verify-build`, per unit. |
| `node .claude/gate.mjs --full` | Everything the repo wants run before code lands: tests, integration tests, codegen drift, lint, plus everything `--fast` covers. | Once per landing — `/verify-build` outside a fleet, `/merge-multi` on the integration branch. |

`--full` is a superset of `--fast`. A repo with nothing worth splitting may ignore the argument and run the same thing either way; say so in a comment at the top of the file.

**A repo may declare a third, middle mode** — conventionally the *no-argument* default, `--scoped` — that runs the whole-repo structural checks and then only the suites, drift checks and guards whose surface the branch's diff actually touches. It exists for the human inner loop, where `--full` is too slow to run as often as it is needed and `--fast` proves too little. **The flow never selects it**: a flow step certifies a branch, and a scoped verdict is a claim about a diff and its importers, not about the tree. `/verify-build` still runs `--fast`, `/merge-multi` still runs `--full`. If you invoke a gate with no argument and its output carries a `GATE-MODE:` line naming a scoped run, say so wherever you report it — that verdict does not certify a landing.

**Node, not bash, and the reason is a contributor, not a preference.** This is the one flow artifact each host repo authors itself and each contributor runs directly, and a `.sh` makes a working Git Bash or WSL a precondition for running the repo's own gate on Windows. Node is already present in any repo this flow runs in, and `spawnSync(..., { shell: true })` resolves `yarn` → `yarn.cmd` for free. A `.claude/gate.sh` is still accepted (see discovery) — a repo that already has one need not rewrite it — but a **new** one is `.mjs`.

Two things this does not buy, worth saying so nobody over-claims it downstream: the gate script being cross-platform says nothing about the commands it *invokes* (a `gate.mjs` wrapping a bash `local-gate.sh` is portable in form only), and the flow's own commands assume a POSIX shell throughout. Portability here is about not *adding* to that, not about having removed it.

### The output contract

The script prints one line per step, and the flow reads *those lines*, never the exit code alone:

```
GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE  <detail>
```

- The script may also print a final `GATE-MODE: <mode>` line naming which mode actually ran. Where it does, quote it in the report: it is the difference between "the repo is green" and "my diff is green."
- `<name>` is stable across runs (`build`, `typecheck`, `test`, `test:integration`, `generate-drift`, `lint`) so two runs can be diffed by step.
- `<detail>` carries the numbers that make the verdict readable — for a test step, the runner's own summary (`Test Suites: 57 passed, 57 total · Tests: 812 passed, 812 total`). A `PASS` with no counts is not usable as a baseline.
- The script exits **non-zero if any step is `FAIL`**, and prints a final `GATE: PASS` or `GATE: FAIL <n> step(s)` line.
- **The script must not pipe its own steps.** `yarn test | tail -30` reports `tail`'s status; a 33-suite-red run surfaces as exit 0. Use `set -o pipefail`, or capture into a log and read `${PIPESTATUS[0]}`.

`SKIP` is for a step the repo deliberately does not run in this mode. `INCONCLUSIVE` is for a step that ran but proved nothing — zero tests collected, an all-skipped env-gated tier, a suite that died at collection. **Neither is a pass**, and the flow must surface both by name rather than folding them into a summary count.

### Example — a `.claude/gate.mjs`

```js
#!/usr/bin/env node
// --fast: build + typecheck.  --full: everything below.
import { spawnSync } from 'node:child_process'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const mode = process.argv[2] ?? '--full'
const tmp = mkdtempSync(join(tmpdir(), 'gate-'))
let failed = 0

const step = (name, cmd) => {
  // shell:true so `yarn` resolves to yarn.cmd on Windows.
  const r = spawnSync(cmd, { shell: true, encoding: 'utf8' })
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`
  const log = join(tmp, `${name.replace(/\W+/g, '-')}.log`)
  writeFileSync(log, out)
  const summary = out.split('\n').filter(l => /^(Tests|Test Suites):/.test(l)).join(' · ')
  const detail = summary || `exit ${r.status}`
  if (r.status === 0) console.log(`GATE-STEP: ${name} PASS  ${detail}`)
  else { console.log(`GATE-STEP: ${name} FAIL  ${detail}  (log: ${log})`); failed++ }
}

step('build', 'yarn build')
step('typecheck', 'yarn typecheck')
if (mode === '--full') {
  step('test', 'yarn test')
  step('test:integration', 'yarn test:integration')
  step('generate-drift', 'yarn generate-all')
  step('lint', 'yarn lint')
}

console.log(failed === 0 ? 'GATE: PASS' : `GATE: FAIL ${failed} step(s)`)
process.exit(failed)
```

Note what `spawnSync` buys beyond portability: there is **no pipeline**, so there is no exit code to lose. The piped-exit-code lie below is a property of shell pipelines, and this shape cannot express it.

A repo that already has an aggregate script keeps it — the convention file is then a three-line wrapper that adds the `GATE-STEP:` lines around it, not a reimplementation.

## Discovery, in order

1. **`.claude/gate.mjs`** → `node .claude/gate.mjs <mode>`.
2. **`.claude/gate.sh`** → `sh .claude/gate.sh <mode>`. Accepted for repos that already have one. Invoke it through `sh`/`bash` rather than relying on the executable bit, which does not survive some Windows checkouts.

Either of the two is a fully structured verdict. Failing both:

3. Fall back to the repo's own aggregate script if one is obvious from `package.json` (`gate`, `check`, `ci`, `validate`), then to `test`. **Say in the report that you fell back and to what** — an inferred gate is a weaker claim than a declared one.
4. Nothing found → **INCONCLUSIVE**, reported as such. Never silently skip, and never let "no gate found" read as "gate passed."

When you fall back, also **offer to write `.claude/gate.mjs`** — one round-trip with the user now removes the guess from every future run of every flow command in this repo.

## Reading the verdict

Everything below is [EVIDENCE.md](../../EVIDENCE.md) §1 — *a verdict is evidence only about what it actually executed* — applied to this one instrument.

- **Never read a pass from a piped exit code**, yours or the script's. Parse the `GATE-STEP:` lines; if there are none, you are looking at output from something that is not a conforming gate, and the run is inconclusive.
- **A run that executed nothing reports green.** `Tests: 0 total` and an all-skipped tier both exit 0, and jest prints `PASS` for the latter. The counts in `<detail>` are the only thing that distinguishes them from a real pass — which is why the contract requires them.
- **A green *partial* inventory reads as full coverage**, and is harder to spot than zero because the run looks substantial. `find` the repo's test files by its naming convention and compare against the count the runner reported; a material gap means the `include` globs are wrong or a tier is opt-in. (A root glob that predated a monorepo move silently excluded **33 of 57 suites**; every prior "green" on that branch was vacuous for them.)
- **"All green" is the wrong bar when the base is already red.** The sound verdict is a **baseline diff**: capture the failing-suite *set* on the base and on `HEAD`, and diff the **names**. `PASS→FAIL` is a regression; already-red-on-base is pre-existing — name it and move on. Compare **by file, not by total**; totals hide an equal-and-opposite swap. `.work/known-baseline-failures.md` is where that base-side set is written. It normally arrives holding only the base sha and *"not captured — capture on demand"*: `/start` and the `provisioner` deliberately do **not** run a suite to fill it, because the base side is only needed on a red `HEAD`. When you need it, capture it yourself — for the **red suites by name**, on a freshly-built tree — and append it there for whoever comes next. An empty baseline file is the absence of a claim about the base, never a claim that the base is green.
- **When HEAD is fully green with parsed counts, skip the base-side run entirely** — zero flips are possible, so the worktree + install is pure cost. Only a red HEAD needs the base set.
- **A gate's verdict names its blind spot in the same breath.** Any step reported `SKIP` or `INCONCLUSIVE`, and any tier the repo excludes from `--full` on purpose, goes into the PR body by name. Silence there reads as coverage.

## Reporting

Whatever consumes this skill records, verbatim:

```
node .claude/gate.mjs --full on <branch> @ <sha>
  build            PASS
  typecheck        PASS
  test             PASS  Test Suites: 57 passed, 57 total · Tests: 812 passed, 812 total
  test:integration PASS  Test Suites: 9 passed, 9 total · Tests: 104 passed, 104 total
  generate-drift   PASS
  lint             PASS
Baseline diff vs <base>: no PASS→FAIL flips.
Not covered: <tiers this repo excludes, by name — or "none declared">
```

Two facts make that block worth its length: the step names let the next run diff against it, and the counts are the only defence against a green that ran nothing.
