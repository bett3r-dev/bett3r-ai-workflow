## D1 — Probe sits inside the .blueprint branch, so no-blueprint prints no board_script line
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [design:Testing Decisions item 2, design:slice 1 behavior, code:PREFLIGHT.md]
rejected: probe outside the .blueprint branch — the board refuses to start without .blueprint/graph.json, and the fixtures README pins "nothing probed below blueprint_dir: absent"
supersedes: —
Testing item 2 said no-blueprint prints board_script: absent. board_script: absent is asserted on no-graph, unregistered and no-mcp-json (same package.json shape) instead. Verifier ACCEPTED; PR body should note the correction.

## D2 — Line-based BLUEPRINT_CHECKOUT match can misfire on a minified package.json
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:PREFLIGHT.md board_script probe]
rejected: —
supersedes: —
A one-line package.json naming BLUEPRINT_CHECKOUT in another field gets an unneeded env prefix; the launch still works. Same limit as the .mcp.json probe.

## D3 — Slice 2 fix round 1 (oracle-wrong): D5 clauses were unpinned
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [design:D5, design:D6]
rejected: —
supersedes: —
Five mutations of the checkout-resolution sentence stayed green at 190/190. A fresh executor added three spanning needles plus one for the second launcher refusal ("has no index.html", bundle-config.ts:31); re-check PASS at 194. Executor: fresh.

## D4 — Refute needles built from OLD_ROOT=packages so the stale-path census can reach 0
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [design:D8, code:scripts/test-blueprint-design.sh]
rejected: a pathspec exclusion in the census — it would hide the whole file from the guard
supersedes: —
scripts/test-blueprint-design.sh is outside D8's list. Verifier mutated both refutes and each stayed discriminating. ACCEPTED.

## D5 — select/README.md keeps de920db attribution with a sentence
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [design:D8]
rejected: swapping paths only — it would misattribute line numbers to the src/ layout
supersedes: —
Verifier ACCEPTED.

## D6 — Slice 3 doc round: epic-esas-156.sh:382 misquoted the ESAS-156 block
kind: false-premise
step: build · slice: 3 · decidedBy: verifier
sources: [design:D8]
rejected: —
supersedes: —
Reworded to a non-quote. Classified doc-wording; scope-check confirmed comment-only; recheck: skipped (doc round).

## D7 — Slices ran sequentially although the pool sized to 2
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [code:worktree-pool size]
rejected: concurrent pool worktrees for slices 1 and 3 — provisioning cost outweighed two small slices
supersedes: —
Pool sizing: `worktree-pool size` returned outcome=ok pool=2, so this is a choice, not a pool=0 fallback.

## D8 — Manual criterion 6 run against the main blueprint checkout
kind: shipped-finding
step: build · slice: 3 · decidedBy: executor
sources: [design:Testing Decisions item 6]
rejected: running in the base tree — it has no node_modules
supersedes: —
capture-esas-156.mjs exits 0 with six captures against blueprint 03aaa3d5 (742c07b9 is an ancestor; no change under the imported paths). Stage 7 of epic-esas-156.sh itself was not run. Plugin version bump (past 0.110.0) is owed in the PR body, not made in the lane (F19).
