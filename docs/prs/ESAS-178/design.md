---
work_item: ESAS-178
branch: ESAS-178-design-map-prefactor
---
# ESAS-178 — design-map v2 prefactor (verification pass)

Brief: `.work/lane.yaml` (fleet run `multi-ESAS-178-162-164-163-165-166-174`). The ticket carries a
`design-multi:resolved:v2` block (owner-accepted 2026-09-16); this document is the **second pass**: it
re-verifies the block at BASE `int/multi-… @ 9c835c0` and records where the code disagrees. Grounding
degraded: no plugin `CONTEXT.md` covers design-map; the ground is `scripts/design-map.py`'s module header.

## Problem & intent
ESAS-161 shipped `bin/design-map` (`render`, `check-page`, `apply-answers [--final]`) over a
**plugin-authored** v1 schema (`layout: impactMap|decisionTree`, flat `status`/`by`/`pick`, option `key`).
The epic needs one map spelling across repos (esas ESAS-167 D12), the vocabulary taken byte-identical from
esas (ESAS-176), one structural writer (`write`), and the reader verbs the sibling units (165, 166) scoped
out to this one. The epic oracle driver lands first, RED.

## Verified at BASE (code wins)
| Block claim | At 9c835c0 | Consequence |
|---|---|---|
| `scripts/test-design-map.sh`, `scripts/fixtures/design-map/` under `plugins/bett3r-ai-workflow/` | They live at **repo-root** `scripts/` (`ls scripts/test-design-map.sh`); only `design-map.py` is under the plugin | Oracle driver goes at repo-root `scripts/oracles/epic-esas-156.sh`, fixtures at `scripts/fixtures/epic-esas-156/` |
| ESAS-176 emitted vocabulary exists | `esas@de920db:packages/esas-schema/schema/map.schema.json`, `schemaVersion: 2`, `decidedSource ∋ code`, `mapShape = impact\|decision` | D1 unblocked |
| "re-emit and diff" (D1 staleness) | The emitter `packages/esas-schema/scripts/emit-map-schema.mjs` **writes into the checkout** and needs `build/esm` — absent in the read-only checkout | Staleness case diffs against `$ESAS_CHECKOUT/packages/esas-schema/schema/map.schema.json` (the committed emit output, which esas's own build regenerates); when `build/esm/index.js` exists it additionally serialises `serialiseMapSchema()` to stdout (no write) and diffs that too |
| `VERBS` dispatch table, `verb=` key | `VERBS = {...}` (`design-map.py:653`), `verdict()` | Extended, not reshaped |
| D8 stage 3 "`count` = owner 2 / recommendation 1 / moot 1" over 5 forks | Arithmetically impossible: after `--final` no fork is open, so owner+recommendation+moot = 5. And `count` is ESAS-162's verb, absent | Stage 3 reads `apply-answers --final`'s own verdict counts and asserts **owner 2 / recommendation 2 / moot 1 / open 0** (chosen + unlocked-then-picked = owner; commented-only + untouched open = recommendation). Correction recorded in the PR body |
| AC7 "stages 1-3 and 5 ok at land time" | Stage 3 would need `count` | Satisfied via the verdict counts above; stage 4 (`map-tree`, 163) and 6-7 (`select`/`post`, 174; esas vitest) are `outcome=error reason=unknown-verb` / missing, driver exits non-zero |
| ESAS-165 writes `candidates --map <p>`; 178 D6 writes `candidates <map>` | — | Positional is the contract (D7 §7 "no `--map` flag" spirit); `--map` is refused as unknown flag. Recorded for 165 |

## Resolved decision tree (block D1–D8, confirmed; build-level resolutions added)
- **D1 vocabulary copy** — `skills/design-map/map.schema.json` := esas emitted bytes. Structure moves to
  `skills/design-map/map-structure.schema.json` (`structureVersion: 2`). The structure schema names enums by
  `$ref` into `map.schema.json#/$defs/<name>`; the stdlib validator resolves that cross-file ref, so the enum
  data is read from the copy, never restated. *Rejected:* plugin enum set + parity check; one merged file.
- **D2 structure** — exactly the block's shape. Additional top-level keys refused. Option `key`/`recommended`
  (v1) are gone: recommendation is `card.recommendation.option`.
- **D3 ids** — `^[A-Za-z0-9-]+$` everywhere; fork ids `^[A-Z][A-Z0-9]*-[0-9]+-F[0-9]+$`, unique; option ids
  unique per fork; node ids unique; `anchor`/`parents`/`restsOn` must resolve (refusal `dangling-ref`).
- **D4 grounding** — `render`/`check-page` refuse `reason=not-grounded` when forks ≥1 and `grounded` not true.
- **D5 apply-answers v2** — as the block; `otherMap=<n>` and `code=<n>` join the verdict. Validation of picks
  runs over non-moot forks only (moot untouched even with an invalid pick).
- **D6 verbs** — `validate`, `write` (stdin, atomic), `render --stack`, `project --ticket`, `decisions`,
  `candidates`, `check-plan`. Build-level resolutions of what the requesting blocks leave loose:
  - `render --stack <m1> <m2>… --expect <n1> <n2>…` — one `--expect` per map, in argument order; page order =
    most open forks first, ties by lowest ticket key; verdict `maps= forks= expected=`; a count miss is
    `outcome=error` (house refusal; 166's "fail" wording yields, as D4 did for 164).
  - `project --ticket K <map>…` — prints the projected map JSON on stdout (pipe it into `write`, the single
    writer) and a verdict `forks=`; nodes kept = those referenced by kept forks' `anchor` plus their ancestors.
  - `decisions <map>` — prints per-ticket Markdown (`owner` / `applied on recommendation` / `code` / `moot`),
    verdict `open= owner= recommendation= code= moot=`; `--closed` turns open>0 into `outcome=fail
    reason=open-forks` (166's "one-answer check exits non-zero without --close").
  - `candidates <map>` — one JSON line `{fork, option, scenario, source, example}` per walk of a decided
    fork's chosen option; counters per 165 D1.
  - `check-plan <slices.yaml>` — `outcome=fail` exit 1 for `review: unattended` with a `confirmed` candidate,
    or a slice `oracle` containing a candidate `example` verbatim; ok exit 0. Parsed with PyYAML if importable,
    else refuses `reason=yaml-unavailable` (never a silent pass).
- **D7 `source: code`** — third card style (`.fork.code`), distinct from owner/recommendation.
- **D8 oracle first, RED** — first commit = `scripts/oracles/epic-esas-156.sh` + fixture; `ORACLE:v1` lines.

## Seams / flow
```mermaid
flowchart LR
  draft -->|stdin| write --> M[map.json v2]
  M --> validate
  M -->|grounded| render --> page -->|answers/<forkId> + map| A[answers dir]
  A --> apply[apply-answers / --final] --> M
  M --> candidates --> plan[/plan (165)/] --> checkplan[check-plan]
  M --> project -->|stdout| write
  M --> decisions
  M -->|--stack| render
  vocab[esas emitted map.schema.json] -.byte copy.-> schema[skills/design-map/map.schema.json] -.$ref.-> struct[map-structure.schema.json]
```

## Test seams
1. `scripts/test-design-map.sh` (existing, extended; DM_SH sh/dash/bash matrix already in validate-plugins.yml)
   — every AC1–AC6 case, fixtures migrated to v2 under `scripts/fixtures/design-map/`.
2. `scripts/oracles/epic-esas-156.sh` — separate seam, deliberately in **no** default suite; `/merge-multi` runs it.

## Risks / gate-less seam
- **Staleness case is SKIP in every gate run** (the gate mirror does not set `ESAS_CHECKOUT`): the copy can
  go stale with a green gate. Mitigation: loud `SKIP reason=no-esas-checkout`; lane runs it once with the checkout.
- **Cross-file `$ref` in a hand-rolled validator** — if the resolver silently ignores an unresolved ref, enums
  are unchecked while tests of valid maps pass. Tracer bullet: a map with `status.kind:"closed"` must be refused.
- v2 breaks every v1 map; none exist outside fixtures (161's `docs/prs/ESAS-161/` holds no map.json).

## Unspecified seams (explicit non-guidance)
- The page's answer writer: block says answers carry `map: <mapId>`; the embedded page script adds it when
  `mapId` is set. Stacked page answers keyed by fork id stay unique because fork ids embed the ticket.
- `write` does not merge with the existing file; it replaces. Preserving answered statuses across a re-`write`
  is the caller's job (ESAS-164/166).
- `feedSeq` is validated as integer ≥ 0 only; nothing here advances it (ESAS-162).
- `target` is validated as `board|artifact` only; nothing here selects it (ESAS-174).

## Scope
In: block §2 minus the `plugin.json` bump (orchestrator directive: single bump at /merge-multi;
`check-plugin-version-bump.sh` fails deliberately). Out: block §2 Out. No ADR (none allocated; ADR-010 not claimed).

## Provenance
- `git -C …/esas-int156-de920db log -1 --format=%h` → `de920db`; `ls …/packages/esas-schema/schema/` → `map.schema.json`
- `ls …/packages/esas-schema/build/esm/index.js` → absent
- `grep -n VERBS plugins/bett3r-ai-workflow/scripts/design-map.py` → `:653`
- `ls scripts/test-design-map.sh scripts/fixtures/design-map` (repo root) → present; under plugin → absent
- `work-docs-path --item ESAS-178 --owner-branch ESAS-178-design-map-prefactor` → `path=docs/prs/ESAS-178 owner=none`
