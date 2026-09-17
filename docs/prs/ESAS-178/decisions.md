# ESAS-178 — decisions after the design

## D1 — Oracle stage 6 runs vitest from the esas repo ROOT, not packages/esas-mcp
kind: false-premise
step: build · slice: 1 · decidedBy: verifier
sources: [code:vitest.oracle.config.ts (esas@de920db, repo root; include packages/esas-mcp/oracles/**/*.oracle.test.ts), design:block D8 stage 6]
rejected: run in packages/esas-mcp as the block says — no config there; from that dir the root-relative include collects zero files
supersedes: —
The block's D8 stage 6 path is wrong. The driver runs `npx --no vitest run -c vitest.oracle.config.ts` from `$ESAS_CHECKOUT`; `vitest-unavailable` when the checkout has no node_modules (true of the read-only int checkout).

## D2 — No esas captures exist; stage 7 reads an ESAS_ORACLE_CAPTURES dir and says no-captures without it
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [code:packages/esas-mcp/oracles/epic-esas-156.oracle.test.ts (esas@de920db, writes only into mkdtemp), design:block D8 stages 6-7]
rejected: imply stage 6 hands captures to stage 7 — nothing on either side writes or reads a persistent capture
supersedes: —
The stage 6 → 7 handoff D8 describes does not exist. `ESAS_ORACLE_CAPTURES` and `select --captures` are placeholders for ESAS-167/ESAS-174 to replace; the stage stays `error reason=no-captures`, never a skip.

## D3 — Stage 4 assumes map-tree region markers `map-tree:begin` / `map-tree:end`
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:block D8 stage 4]
rejected: omit the out-of-region check until ESAS-163 — D8 names it; missing markers print error region-markers-absent instead
supersedes: —
ESAS-163 owns the real marker format and `map-tree` CLI (`write`, `check`, `reason=stale`); re-derive stage 4 at its merge.

## D4 — Stage 3 asserts owner=2 recommendation=2 moot=1 open=0 from apply-answers' own verdict
kind: false-premise
step: build · slice: 1 · decidedBy: lane
sources: [design:docs/prs/ESAS-178/design.md "Verified at BASE", code:apply_answers (scripts/design-map.py)]
rejected: block's owner 2 / recommendation 1 / moot 1 via `count` — sums to 4 over 5 forks with none open after --final; `count` is ESAS-162's, absent
supersedes: —
Stage 5 reads the static final.map.json (candidates=6); stage 7's multiset reads stage 3's runtime map.
