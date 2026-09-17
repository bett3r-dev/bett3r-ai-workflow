# ESAS-165 — decisions after the design

## D1 — plugin.json is not bumped
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [human, design:C5]
rejected: bump per the block's scope — the orchestrator directive reserves the single bump for /merge-multi
The block lists a `plugin.json` bump in scope; the fleet directive overrides it. `check-plugin-version-bump.sh` fails on this branch deliberately.

## D2 — AC3 uses a new seven-fork fixture, not ESAS-178's candidates.map.json
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:candidates (plugins/bett3r-ai-workflow/scripts/design-map.py), design:C3]
rejected: reuse candidates.map.json — its zero-walk fork also carries testable:false, giving skipped-untestable=2, not the block's 1
`plan-candidates.map.json` is candidates.map.json minus F8, ids renamed ESAS-165-F1..F7.

## D3 — check-plan fail handling split by reason
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [code:check_plan (plugins/bett3r-ai-workflow/scripts/design-map.py:1248,1266), design:U2]
rejected: one "remove the offending copy" instruction — has nothing to do on unattended-confirmed and can loop
`candidate-in-oracle` removes the copy from that slice's oracle; `unattended-confirmed` resets the candidate to unconfirmed, and the re-run then catches any pasted copy as candidate-in-oracle.

## D4 — flow-seams needles anchored to unique phrases
kind: overruled
step: build · slice: 2 · decidedBy: verifier
sources: [code:test-flow-seams.sh]
rejected: one-word needles ('unconfirmed') — matched twice; deleting the unattended rule stayed green

## D5 — Oracle candidates wording the design left open
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:D5, design:U3, code:plan.md Step 5]
rejected: prose in Step 6 — the template is the single place the PR body is specified
Bullet layout `<fork>` / `<option>`: <scenario> — e.g. <example>; human form "Oracle candidates: <confirmed> confirmed, <rejected> rejected". A plan with no `review:` key (predating this unit) falls to "none (no map.json)" — harmless, report-only.
