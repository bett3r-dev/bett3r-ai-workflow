# XL-62 — decisions made after the design

## D1 — the `resolved_by:` line is placed after the `Why:` block, not directly under `decided(src)`
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:render_md (plugins/bett3r-ai-workflow/scripts/map-tree.py), design:ticket-block.md "Unspecified seams"]
rejected: placing it immediately under `decided(<source>)` — reads marginally better to a human, but the block explicitly delegates the insertion index to the build lane, and the census greps column 0 either way
supersedes: —
The ticket block leaves the precise insertion index relative to the `Why:` line undesigned. The renderer now emits `### heading / decided(src) / Why: … / resolved_by: … / rejected bullets`, which keeps the citation beside the reasoning it justifies and ahead of the rejected alternatives. The checked-in conformance fixture freezes the order, so any later move is a reviewable diff rather than a silent drift.

## D2 — the four-fork-kinds fixture is a new ticket inside design.map.json, not a new map file
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:ESAS-905 (scripts/fixtures/map-tree/design.map.json), design:slice 1 scenario 5]
rejected: extending ESAS-901 in place — it would have rewritten T1's `forks=2` assertions; a separate map file — the slice's intended-files list names design.map.json as the map to extend
supersedes: —
Scenario 5 needs decided, open, moot and card-less LOCKED forks present at once. `ESAS-905` carries all four. The verifier confirmed ESAS-901's rendered body and both its `src=` and `out=` hashes are byte-identical before and after, so the existing cases are untouched.

## D3 — the plugin version is NOT bumped in this lane
kind: waiver
step: build · slice: 1 · decidedBy: orchestrator
sources: [code:check-plugin-version-bump.sh:250-259, human]
rejected: bumping plugins/bett3r-ai-workflow/.claude-plugin/plugin.json in the slice commit — the verifier's F2 asked for it, reading the gate as if this were an ordinary branch
supersedes: —
The verifier flagged that `map-tree.py` is a plugin payload, so the version-bump gate will demand a bump at commit time. It will not: `.work/lane.yaml` declares `gateDeferred: true`, and the gate reads that file and prints `SKIP reason=deferred-to-merge-multi`. `/merge-multi` does the single real bump on the integration branch, where no lane.yaml exists. A per-lane bump here would collide with every sibling lane's. The ticket block's own `0.88.0 -> next` is stale besides; the tree is at `0.99.2`.

## D4 — cross-repo citations in the new source comments are left unqualified for slice 3 to resolve
kind: shipped-finding
step: build · slice: 1 · decidedBy: orchestrator
sources: [code:resolved_by (plugins/bett3r-ai-workflow/scripts/map-tree.py:134-140), code:scripts/test-map-tree.sh:465, adr:ADR-010]
rejected: qualifying them inside slice 1 — the natural home is slice 3, which mints ADR-014 in this repo and can be cited instead
supersedes: —
The new comments cite `ADR-053 §10`, `XL-24` and `packages/xp-mcp/src/resolved-by.ts`, none of which resolve in this repo (`docs/adr/` tops out at ADR-013; there is no `packages/`). ADR-010 already establishes the `cross-repo <repo>@<sha>:<path>` spelling for exactly this. Carried into slice 3.

## D5 — flow-seams' two red assertions are a pre-existing baseline failure, not slice 1's
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh, human]
rejected: treating gate step `flow-seams` as met — it is not; it is red, and reported red
supersedes: —
`sh scripts/test-flow-seams.sh` reports `✗ 2 failed, 544 passed`: `the brief keeps every field the absorbed lane marker carried` and `the brief carries what a step invoked on its own cannot ask anyone for`. The verifier reproduced the identical count and the identical two names on a clean base checkout, so the red predates the slice and names no file in its diff. Slice 1's gate 2 is therefore not met, and the failure is out of the slice's scope rather than waived.
