---
work_item: XL-62
plugin: bett3r-ai-workflow@0.99.2+7f1770a
base: 7f1770aaaa64696fcb855d5f943120d7ecd6988c
slices:
  - id: 1
    name: "TRACER BULLET — a decided fork's resolved_by: line, in the grammar the xp-layer census parses"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: eb07ef41335bc4bbc9e35bfdb77fb65f8c99b1e1
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D1, D2, D3, D4, D5]
  - id: 2
    name: "An open fork's typed reason is visible to the person reading the design"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 39beeafa5f43c146c47f9cedf513b58cbb7910f2
    passed: true
    attempts: 2
    fixRounds: [{ cause: invariant, executor: fresh }]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D6, D7, D8]
  - id: 3
    name: "The accepted ADR-003 exception is written down where the next renderer change will read it"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 6feadef8dc7bb514993c5f0f0ae6175685e10ae9
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D9, D10, D11, D12]
---
## What shipped

All three slices green and committed, one commit each, in plan order, sequentially in the lane
worktree (`worktree-pool size` returned `pool=0`: the slices are a 1 -> 2 -> 3 chain, width 1).

`map-tree`'s md projection now emits one column-0 `resolved_by: <value>` line per decided fork
and for no other fork kind, in the five-value grammar `atom:<id> | neotoma:<entity_id> | human |
code | recommendation`, valued from `status.resolvedBy` verbatim where the map carries it and
minted from `status.source` otherwise. `GEN` advanced 1 -> 2 in the same commit as the shape
change, so every region written by the previous renderer reads `stale` and re-renders rather than
being refused as a hand edit. An open fork's typed `reason` renders inline on the OPEN line,
mirroring the moot branch — presentation only, no column-0 line, no parser, no verdict-line
counter, with that negative half asserted rather than implied. ADR-014 records the four clauses
the first two slices relied on, and `flow-seams` checks its central factual claim against the tree
instead of trusting it.

Root causes worth knowing:

- **One fix round, cause `invariant` (slice 2, executor `fresh`).** The first draft wrote a comment
  claiming `design-map validate` judges the open-reason vocabulary. It does not: `open.reason` is
  `$defs/text` and validate returns `outcome=ok` on a value outside the three documented codes. The
  verifier ran it and refused the slice. The comment now says no layer enforces the vocabulary
  today and cites the ticket block's Risks section, where the gap is recorded as open. This is the
  run's one recurring shape — a normative placement written as a present-tense fact — and D7 is
  its disposition.
- **Both fixture extensions were new tickets, not mutations of existing ones** (`ESAS-905` in slice
  1, `ESAS-906` in slice 2). That was not tidiness: it preserved slice 1's checked-in conformance
  body as an independent drift signal, which is now a live assertion that slice 2's feature moved
  zero bytes of the no-reason render. Confirmed by rendering ESAS-901/902/905 before and after,
  `src=` and `out=` hashes included.
- **The `resolved_by:` grammar's reader lives in another repo that is not on this machine**
  (`environment-gap: consumer repository not present locally`). `packages/xp-mcp/src/resolved-by.ts`,
  XL-24 and that repo's ADR-053 §10 could not be opened. The checked-in conformance fixture exists
  precisely to narrow that gap, and it is the only drift signal this repo can carry for the
  grammar. See D12.

Gate results, named in the mode they ran:

- `sh scripts/test-map-tree.sh` and the same file under `MT_SH=dash dash` and `MT_SH=bash bash`:
  `✓ 231 passed` under each (188 at base, +29 in slice 1, +14 in slice 2). Three shells, every
  slice — not merely the developer's.
- `sh scripts/test-flow-seams.sh`: `✗ 2 failed, 556 passed` (544 at base, +12 in slice 3).
  **The two failures are a pre-existing baseline red**, not this lane's: `the brief keeps every
  field the absorbed lane marker carried` and `the brief carries what a step invoked on its own
  cannot ask anyone for`. The verifier reproduced the identical count and the identical two names
  on a clean `git archive` of the base at every slice. Neither names any file in this PR's diff.
  Gate step `flow-seams` is therefore **not met**, and is reported red rather than waived (D5).
- `check-artifact-links.py` `✓ 118 links across 80 artifacts` and `check-needles.py` `✓ 145 needles
  across 80 corpus files`, both identical before and after.
- **The version-bump gate is deliberately deferred**: `.work/lane.yaml` carries `gateDeferred: true`,
  so `check-plugin-version-bump.sh` prints `SKIP reason=deferred-to-merge-multi`. `/merge-multi`
  does the single real bump on the integration branch. **A SKIP is not a pass.** `plugin.json` is
  untouched at `0.99.2` on purpose (D3); the ticket block's `0.88.0 -> next` is stale.
- **No whole-repo gate was run**, and none was asked for. `yarn gate --full` does not apply here at
  all — this repo is Python and shell, with no install and no build step.

For `/verify-build`'s ripple sweep: the wire surface this PR changes is `render_md`'s output shape
in `plugins/bett3r-ai-workflow/scripts/map-tree.py` and the `GEN` constant. `GEN` is the ripple to
watch — every committed `map-tree` region in the tree now classifies `stale`, by design, including
`docs/prs/XL-62/ticket-block.md`'s own. `render_jira` and `COUNT_KEYS` are unchanged and both are
now pinned by assertions. **No suite was left un-run**: the only runners that collect these files
are `test-map-tree.sh` and `test-flow-seams.sh`, and both ran on every slice. What the local runs
cannot see is the consumer-side half of the grammar, in the repo that is absent.
