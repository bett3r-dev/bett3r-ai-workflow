---
name: full-gate
description: Discover and run the host repo's gate (.claude/gate.mjs, else .claude/gate.sh) scoped to the branch's diff, and read its GATE-STEP verdict. Use to certify a branch in /verify-build or /merge-multi.
---

# Full gate — the host repo declares what "green" means

The plugin does not know this repo's test commands, and which of `test`, `test:integration`, `lint`, `build`, `typecheck` and the drift checks belong in a routine gate differs per repo. So the host repo declares its gate, and the flow discovers and runs it.

## The contract

`.claude/gate.mjs` at the repo root, run as `node .claude/gate.mjs <mode>` with exactly one argument:

| Invocation | Runs | Who runs it |
|---|---|---|
| `node .claude/gate.mjs --fast` | the cheap structural checks, typically build + typecheck | every `/verify-build` inside a fleet lane (`gateDeferred: true`) |
| `node .claude/gate.mjs` (no argument: scoped) | the whole-repo structural checks, then only the suites, drift checks and guards whose surface this branch's own diff touches | every landing the flow performs: `/verify-build` outside a fleet, `/merge-multi` on the integration branch, `/start-multi`'s base check |
| `node .claude/gate.mjs --full` | everything, unconditionally | CI, or the human when they ask for it by name; never a flow step, and `--all` likewise |

`--full` ⊃ scoped ⊃ `--fast`. A repo with nothing worth splitting may run the same thing in every mode and say so in a comment. A repo with no scoped mode (it exits 2 on `--scoped`, or accepts only `--fast` and `--full`) is run with `--fast`, and the report says so; the gap is closed in the repo's gate script, not in the flow.

**Output.** One line per step, which the flow reads instead of the exit code:

```
GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE  <detail>
```

- `<name>` is stable across runs (`build`, `typecheck`, `test`, `test:integration`, `generate-drift`, `lint`) so two runs diff by step; `<detail>` carries the runner's own counts (`Test Suites: 57 passed, 57 total · Tests: 812 passed, 812 total`), and a `PASS` with no counts is unusable as a baseline.
- An optional `GATE-MODE: <mode>` line names the mode that ran. Quote it as an opaque token: hosts spell it `fast`, `--fast` or `--scoped`.
- The final line is `GATE: PASS` or `GATE: FAIL <n> step(s)`; the exit is non-zero iff any step is `FAIL`. The script does not pipe its own steps (`yarn test | tail` reports `tail`).
- `SKIP` is a step the repo deliberately does not run in this mode. `INCONCLUSIVE` is a step that ran and proved nothing: zero tests collected, an all-skipped env-gated tier, a suite dead at collection, or a step the venue could not run for want of a credential. Neither is a pass, and the report names each one.

A new gate is `.mjs`: Node is present wherever this flow runs, `spawnSync(..., { shell: true })` resolves `yarn` → `yarn.cmd` on Windows, and with no pipeline there is no exit code to lose. A repo with an aggregate script wraps it in the few lines that add the `GATE-STEP:` lines.

## Discovery, in order

1. `.claude/gate.mjs` → `node .claude/gate.mjs <mode>`.
2. `.claude/gate.sh` → `sh .claude/gate.sh <mode>` (through `sh`; the executable bit does not survive every checkout).
3. Neither: fall back to the repo's aggregate script from `package.json` (`gate`, `check`, `ci`, `validate`, then `test`), say in the report that you fell back and to what, and offer to write `.claude/gate.mjs`.
4. Nothing found: `INCONCLUSIVE`, reported as such; "no gate found" is not "gate passed".

## Reading the verdict

[EVIDENCE.md](../../EVIDENCE.md) §1, *a verdict is evidence only about what it actually executed*, applied to this instrument:

- Parse the `GATE-STEP:` lines; none means the output is not a conforming gate's and the run is inconclusive. An exit code (a pipe's, a wrapper's `cmd > log; echo EXIT=$?`, a sharded runner's) is not the verdict.
- A run that can outlive the Bash ceiling runs detached and writes its own sentinel as the last command: `nohup sh -c "<gate> > <log> 2>&1; echo GATE_EXIT=$? >> <log>" &`, then wait for `GATE_EXIT`. An interrupted generator leaves a tree to restore, not a diff to read.
- `Tests: 0 total`, an all-skipped tier and a suite dead at collection exit 0; the counts in `<detail>` distinguish them from a pass. A green partial inventory is harder to spot: `find` the repo's test files by its naming convention and compare with the count the runner reported; a material gap is a config defect, not coverage.
- A silent, fast, exit-0 typecheck is decided by a positive control planted inside a workspace the runner visits: a deliberate type error, exit 1, removed.
- With a red `HEAD`, the sound verdict is a baseline diff by suite name, not "all green": `git diff --name-only <base>..HEAD -- <the suite's subject paths>` empty disowns the failure by construction; else `git show <base>:<artifact>` may already violate the assertion; else run the red suites by name on a freshly built base tree and append the red set to `.work/known-baseline-failures.md`, which arrives holding only the base sha and `not captured — capture on demand`. Clear an incremental typechecker's state before capturing (a second run under-reports, and the count stops being comparable), and compare by file, not by total (a total hides an equal-and-opposite swap). `PASS→FAIL` is a regression; red on the base too is pre-existing, named and left. With a fully green `HEAD` and parsed counts, skip the base run.
- Tests that count the tree (census and ratchet guards) glob the filesystem and import nothing, so no diff-scoped selection reaches them; a change that adds or removes a file of a kind something counts runs those guards by name.
- A venue without the repo's secrets certifies partially by construction: name each `INCONCLUSIVE` step and why, and where making one step runnable disables another, name the pair, since the two verdicts are not additive.
- The verdict names its blind spot in the same breath: every `SKIP` and `INCONCLUSIVE` by name, every tier the repo excludes on purpose, and on a scoped run the suites and tree-counting guards it did not select. A scoped `PASS` certifies this branch's diff and its importers, not the tree.

**Waiting.** Wait in one blocking call: `Monitor` on the file or transcript the work writes, or a bounded `until <condition>; do sleep 10; done` inside a single foreground Bash call. A background `sleep` or a re-issued timer is a whole extra turn at full context. Printing your verdict line ends the run: take no turn after it.

## Reporting

Whatever consumes this skill records, verbatim:

```
node .claude/gate.mjs (--scoped) on <branch> @ <sha>
  build            PASS
  typecheck        PASS
  test             PASS  Test Suites: 57 passed, 57 total · Tests: 812 passed, 812 total
  test:integration PASS  Test Suites: 9 passed, 9 total · Tests: 104 passed, 104 total
  generate-drift   PASS
  lint             PASS
Baseline diff vs <base>: no PASS→FAIL flips.
Scope: scoped to this branch's diff — certifies the diff and its importers, not the tree.
Not covered: <suites/guards not selected by the scoping, plus tiers this repo
             excludes on purpose, by name — the whole-repo run is CI's, or the user's on request>
```

The step names let the next run diff against this one, and the counts are the only defence against a green that ran nothing.

## Boundaries

- No flow step runs `--full` or `--all`, and none may be made to: the whole-repo run is CI's, or the user's when they ask for it by name. A step that believes it needs one stops and asks.
- A scoped verdict is reported as scoped, with the `GATE-MODE:` line quoted and the unselected suites named; a sentence that reads as whole-repo certification is a false claim.
- A `SKIP` or `INCONCLUSIVE` is surfaced by name, never folded into a summary count.
