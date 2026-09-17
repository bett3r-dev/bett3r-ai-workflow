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

## D5 — `links[]` is spelled `{esId, deliverableId}`, esas's `MapLink`
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [code:MapLink (esas@de920db packages/esas-schema/src/map-structure.ts), design:block D2]
rejected: `{from, to}` — a lane-brief paraphrase; D2 requires esas's spelling untranslated
supersedes: —
`deliverableId` must name a node; `esId` is any non-empty string (esas node ids carry `_`).

## D6 — The plugin writes `structureVersion: 2`; esas de920db writes and accepts only 1
kind: shipped-finding
step: build · slice: 2 · decidedBy: lane
sources: [code:MAP_STRUCTURE_VERSION (esas@de920db packages/esas-schema/src/map-structure.ts:22; unknown versions refused :244-269), design:block D2]
rejected: write 1 to match esas — contradicts the owner-accepted D2; silently diverging the block is the worse failure
supersedes: —
Escalated to the orchestrator: an esas reader refuses every map this plugin writes until one side moves. Recommendation: esas bumps `MAP_STRUCTURE_VERSION` to 2 (ESAS-167 D7 says it is "spelled as ESAS-178's map.json"). Also esas types `links` required where D2 has `links?`.

## D7 — v1 "no goal" level cases and the `schemaVersion`-required case are retired
kind: deviation
step: build · slice: 2 · decidedBy: orchestrator
sources: [design:block D2, code:scripts/test-design-map.sh at 51df694]
rejected: keep a level-completeness rule — D2 states none for v2 nodes
supersedes: —
v2 has no per-layout required levels and no top-level `schemaVersion` (it is `structureVersion`, pinned by a new case). The `impact-map-no-goal.json` fixture is deleted with them.

## D8 — Carried notes: epic stage 1's distinct-styles check is met by the page legend; README verb list is stale
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/oracles/epic-esas-156.sh stage 1, code:plugins/bett3r-ai-workflow/README.md]
rejected: —
supersedes: —
The real guard for D7 styling is test-design-map.sh's fork-class case. The README update lands with the last verb slice.

## D9 — An answer naming a map, folded into a map with no `mapId`, is skipped as `otherMap`
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:block D5, code:fold (plugins/bett3r-ai-workflow/scripts/design-map.py)]
rejected: apply it — its origin cannot be confirmed against a map that names none
supersedes: —
Also: `write` adds reason `map-dir-missing` (checked before stdin), and reuses `map-unparseable` for empty or non-JSON stdin.
