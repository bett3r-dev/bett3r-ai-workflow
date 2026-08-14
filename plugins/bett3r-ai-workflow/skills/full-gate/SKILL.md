---
name: full-gate
description: Discover and run the host repo's full validation gate (`.claude/gate.sh`) and read its verdict correctly. Use when a flow step needs to certify a branch — /verify-build's per-unit gate, /merge-multi's integration gate — or when deciding which commands constitute "the tests" in an unfamiliar repo.
---

# Full gate — the host repo declares what "green" means

**The plugin does not know this repo's test commands.** `yarn test` is a guess, and it has been the wrong one: a repo has `test`, `test:integration`, `generate-all`, `lint`, `gate`, `build` and `typecheck`, of which only some belong in a routine gate — and the split differs per repo. Hardcoding it into a flow command produces a gate that is either too slow to run or too narrow to mean anything.

So the host repo declares its own gate, and the flow discovers it.

## The convention

`.claude/gate.sh` at the host repo root, executable, accepting exactly one argument:

| Invocation | Contains | Who runs it |
|---|---|---|
| `.claude/gate.sh --fast` | The cheap structural checks — typically `build` + `typecheck`. Seconds-to-a-minute. | Every `/verify-build`, per unit. |
| `.claude/gate.sh --full` | Everything the repo wants run before code lands: tests, integration tests, codegen drift, lint, plus everything `--fast` covers. | Once per landing — `/verify-build` outside a fleet, `/merge-multi` on the integration branch. |

`--full` is a superset of `--fast`. A repo with nothing worth splitting may ignore the argument and run the same thing either way; say so in a comment at the top of the script.

### The output contract

The script prints one line per step, and the flow reads *those lines*, never the exit code alone:

```
GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE  <detail>
```

- `<name>` is stable across runs (`build`, `typecheck`, `test`, `test:integration`, `generate-drift`, `lint`) so two runs can be diffed by step.
- `<detail>` carries the numbers that make the verdict readable — for a test step, the runner's own summary (`Test Suites: 57 passed, 57 total · Tests: 812 passed, 812 total`). A `PASS` with no counts is not usable as a baseline.
- The script exits **non-zero if any step is `FAIL`**, and prints a final `GATE: PASS` or `GATE: FAIL <n> step(s)` line.
- **The script must not pipe its own steps.** `yarn test | tail -30` reports `tail`'s status; a 33-suite-red run surfaces as exit 0. Use `set -o pipefail`, or capture into a log and read `${PIPESTATUS[0]}`.

`SKIP` is for a step the repo deliberately does not run in this mode. `INCONCLUSIVE` is for a step that ran but proved nothing — zero tests collected, an all-skipped env-gated tier, a suite that died at collection. **Neither is a pass**, and the flow must surface both by name rather than folding them into a summary count.

### Example — a `.claude/gate.sh`

```sh
#!/usr/bin/env bash
# --fast: build + typecheck.  --full: everything below.
set -uo pipefail
MODE="${1:---full}"; FAILED=0

step() {  # step <name> <cmd...>
  local name="$1"; shift
  local log; log="$(mktemp)"
  "$@" >"$log" 2>&1; local rc=$?
  local detail; detail="$(grep -E '^(Tests|Test Suites):' "$log" | tr '\n' ' ')"
  [ -z "$detail" ] && detail="exit $rc"
  if [ $rc -eq 0 ]; then echo "GATE-STEP: $name PASS  $detail"
  else echo "GATE-STEP: $name FAIL  $detail  (log: $log)"; FAILED=$((FAILED+1)); fi
}

step build     yarn build
step typecheck yarn typecheck
if [ "$MODE" = "--full" ]; then
  step test             yarn test
  step test:integration yarn test:integration
  step generate-drift   yarn generate-all
  step lint             yarn lint
fi
[ $FAILED -eq 0 ] && echo "GATE: PASS" || echo "GATE: FAIL $FAILED step(s)"
exit $FAILED
```

A repo that already has an aggregate script keeps it — the convention file is then a three-line wrapper that adds the `GATE-STEP:` lines around it, not a reimplementation.

## Discovery, in order

1. `.claude/gate.sh` in the host repo root → run it. This is the only case where the verdict is fully structured.
2. No such file: fall back to the repo's own aggregate script if one is obvious from `package.json` (`gate`, `check`, `ci`, `validate`), then to `test`. **Say in the report that you fell back and to what** — an inferred gate is a weaker claim than a declared one.
3. Nothing found → **INCONCLUSIVE**, reported as such. Never silently skip, and never let "no gate found" read as "gate passed."

When you fall back, also **offer to write `.claude/gate.sh`** — one round-trip with the user now removes the guess from every future run of every flow command in this repo.

## Reading the verdict

Everything below is [EVIDENCE.md](../../EVIDENCE.md) §1 — *a verdict is evidence only about what it actually executed* — applied to this one instrument.

- **Never read a pass from a piped exit code**, yours or the script's. Parse the `GATE-STEP:` lines; if there are none, you are looking at output from something that is not a conforming gate, and the run is inconclusive.
- **A run that executed nothing reports green.** `Tests: 0 total` and an all-skipped tier both exit 0, and jest prints `PASS` for the latter. The counts in `<detail>` are the only thing that distinguishes them from a real pass — which is why the contract requires them.
- **A green *partial* inventory reads as full coverage**, and is harder to spot than zero because the run looks substantial. `find` the repo's test files by its naming convention and compare against the count the runner reported; a material gap means the `include` globs are wrong or a tier is opt-in.
- **"All green" is the wrong bar when the base is already red.** The sound verdict is a **baseline diff**: capture the failing-suite *set* on the base and on `HEAD`, and diff the **names**. `PASS→FAIL` is a regression; already-red-on-base is pre-existing — name it and move on. Compare **by file, not by total**; totals hide an equal-and-opposite swap. `.work/known-baseline-failures.md` (written by `/start` step 4 and the `provisioner`) is that base-side set where it exists.
- **When HEAD is fully green with parsed counts, skip the base-side run entirely** — zero flips are possible, so the worktree + install is pure cost. Only a red HEAD needs the base set.
- **A gate's verdict names its blind spot in the same breath.** Any step reported `SKIP` or `INCONCLUSIVE`, and any tier the repo excludes from `--full` on purpose, goes into the PR body by name. Silence there reads as coverage.

## Reporting

Whatever consumes this skill records, verbatim:

```
.claude/gate.sh --full on <branch> @ <sha>
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
