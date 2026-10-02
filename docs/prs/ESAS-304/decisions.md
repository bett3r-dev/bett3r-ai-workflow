## D1 — scaffold-commit prepare skips (no-design-layer) when no design layer exists, instead of erroring
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [code:inputs_of (scaffold-commit.py), design:Step 4b]
rejected: error design-missing — fleet step 0 and lane worktrees hold no .blueprint/, so every declaring repo would end blocked-on
supersedes: —
A named --design that is absent stays an error.

## D2 — fleet step 0 scaffolds in a clean worktree on int/<run-id> with the design layer copied into .blueprint/ and defaults used
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [code:finish extract rewrite, design:ESAS-304-F3]
rejected: --graph .work/design-snapshot — finish's re-extract writes .blueprint/graph.json, so a named snapshot goes stale and deferred units end gate-red placement-incomplete
supersedes: —
A fleet lane never scaffolds (owner F3); the claim that lane snapshots follow the scaffold commit was false and was dropped.

## D3 — repeatable --map on scaffold-commit (inputs.maps[])
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [design:Fleet (owner answer B), ESAS-297 CLI contract]
rejected: single --map — a fleet passes one projection per unit
supersedes: —
Outside slice 3's six listed files; accepted by the verifier. No scaffold.json had been committed, so no upcaster.

## D4 — check 4 refuses any TODO(scaffold) marker; only node-naming markers are scoped to designs:
kind: false-premise
step: build · slice: 4 · decidedBy: verifier
sources: [code:scaffold-core test-plan.js caseComment, code:PV3 emitters]
rejected: scoping to the TODO(scaffold) [<nodeId>] form — no scaffolder emits it
supersedes: —
The block's "(ESAS-298 R1)" bracket form never shipped. Scoping goes by the subject node; bare and "no subject" markers and scaffoldTodo( stay file-scoped.

## D5 — a census error or missing verdict line is not a pass; lone unit blocks, fleet lane warns, /merge-multi blocks
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [design:Agreed scenario with no test (owner answer C)]
rejected: treating no line as skipped
supersedes: —
The human strike is the Step 5a waiver form in /verify-build and the owner's quoted words in the integration PR body in /merge-multi.

## D6 — BP designTooling.tests uses placement plus an array header
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [code:parseTestsConfig (pv3 emit/tests.ts)]
rejected: the brief's string header — the parser refuses it
supersedes: —

## D7 — the red-base error-set rule is built: a red typecheck is compared against HEAD's error set
kind: silent-seam
step: build · backfill fix · decidedBy: block (Bar P10)
sources: [design:Bar (P10), ESAS-300 block (error sets not exit codes; owner ESAS-304 fog), code:judge_red (scaffold-commit.py)]
rejected: recording it as deferred (decidedBy verifier) — only an owner can set aside a block decision, so that deferral was invalid; capturing the base set in prepare — doubles the typecheck on every green base, where the lazy re-run costs only when red
supersedes: the earlier D7 ("NOT built", shipped-finding)
On a red finish typecheck, the launcher sets the edits aside as a git tree object, restores HEAD, runs the declared typecheck there, and puts the edits back. Green only when HEAD is red too and every `error TS<n>` line now (ANSI colour and the location before the code removed) is in HEAD's set; each other is printed `new-error:`. Fail-safe: a red run with no such line, on either side, stays red. A green on a red base ends ok with `typecheck=base-red`; the report records typecheck{exit, baseExit, baseErrors, errors}. Pinned by the red-base cases in scripts/test-scaffold-commit.sh and by ADR-015.

## D8 — environment gap: the installed global pv3 `g scaffold` lacks --map
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:pv3-cli build]
rejected: —
supersedes: —
A real BP prepare fails until the ESAS-313 scaffolder release; out of scope here.
