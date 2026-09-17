# ESAS-174 — post-design decisions

## D1 — Plugin version is not bumped in this unit
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [design:block §1 D8, human (orchestrator directive CAMPAIGN-PLAN §5)]
rejected: bump plugin.json per D8 — the campaign takes one bump at /merge-multi
supersedes: —
The block's D8 says bump; the fleet directive says do not. `scripts/check-plugin-version-bump.sh` fails deliberately on this branch.

## D2 — select's unreadable inputs degrade to the silent artifact row, never an error
kind: silent-seam
step: build · slice: S1 · decidedBy: executor
sources: [design:block §1 D2 rows 6/10, code:BoardStatus type guard (esas@de920db packages/sticky-notes-board/src/vite-plugin-esas-fs/board-identity.ts:321)]
rejected: outcome=error on a non-JSON board.json / start.json — would stop a design over a flaky probe
supersedes: —
Empty/non-JSON/non-object board.json reads as board-off; unparseable start.json as start-failed; a board without repoPath as board-other-repo; status ok neither true nor false as mcp-error. missing start.json at --phase start is checked after rows 0-1 and is outcome=error (P1). Tool names match bare or mcp__<server>__-prefixed.

## D3 — Row order 6 vs 7 cannot be pinned by an input
kind: shipped-finding
step: build · slice: S1 · decidedBy: verifier
sources: [code:select (plugins/bett3r-ai-workflow/scripts/design-map.py)]
rejected: —
supersedes: —
Row 6 (no board) and row 7 (board repoPath) cannot both fail on one input; every other adjacent pair is pinned by a two-row precedence case. The no-pwd.txt fallback tests do not separately bite on the logical ($PWD) vs physical (realpath) element — both mutations stayed green; production code is correct, left as follow-up.

## D4 — D5 readback merges statuses onto the local map, then `write`; no helper verb
kind: silent-seam
step: build · slice: S2 · decidedBy: executor
sources: [code:postedMapEntry (esas@de920db packages/esas-store/src/replay.ts:703-722), code:MapFile (esas@de920db packages/esas-schema/src/map-structure.ts:19,120-129), design:block §1 D5]
rejected: pipe get_map's map straight into `write` — refused schema-invalid (esas map is structureVersion 1, forks carry no `tickets`); a new merge verb — `write` already expresses it
supersedes: —
Readback statuses are copied onto the local map.json by fork id, feedSeq=mapSeq, and the result goes through `design-map write` on stdin. Local-only forks keep their status; readback-only forks are ignored. SKILL.md (S4) documents the recipe. `post` reports `statuses=` of the readback; count is checked before the multiset.

## D5 — Epic oracle stage 4 corrected to the shipped map-tree contract
kind: deviation
step: build · slice: S3 · decidedBy: executor
sources: [code:START_COMMENT/END_COMMENT (plugins/bett3r-ai-workflow/scripts/map-tree.py:51-54,227), code:/design Step 4 recipe (plugins/bett3r-ai-workflow/commands/design.md:171), human (lane brief: oracle owned by no unit, correct but never weaken)]
rejected: leave stage 4 red — its expectation was written before ESAS-163 shipped; weaken it to region-optional — forbidden
supersedes: —
Stage 4's no-verdict had three causes, not one: map-tree prints `MAP-TREE:v1` (not `DESIGN-MAP:v1`), requires `--ticket`/`--map`, and never commits. The oracle now reads map-tree's own verdict/outcomes (written, stale/fresh), runs /design Step 4's recipe (write → render → map-tree write --insert-after into a seeded design.md → the 3-path commit, done by the oracle as the flow does), and uses the comment markers (the inline form sits inside them). Added stricter checks `region-not-regenerated` and `not-fresh-after-rewrite`. Consequence: `commit-not-three-files` can no longer fire, since the oracle makes the commit with a 3-path pathspec.

## D6 — Epic oracle stage 7 produces real esas captures; owner answers go through the store as the board does
kind: silent-seam
step: build · slice: S3 · decidedBy: executor
sources: [code:mapChoose author 'human' (esas@de920db packages/sticky-notes-board/src/.../map-routes.ts:146), code:bin/esas-mcp.mjs tsx loader (esas@de920db), design:design.md P4]
rejected: committed static captures — drift silently from esas; owner via MCP map_choose — impossible by design (ESAS-168: ai never writes owner); built entry — esas packages export src/*.ts, unresolvable by plain node
supersedes: —
With ESAS_ORACLE_CAPTURES unset, `scripts/oracles/capture-esas-156.mjs` drives the real esas MCP server in-memory in a fresh git-init repo (tools, status, start_map_session, map_ground/map_post/map_choose/map_strike, get_map). Owner decisions call the store's mapChoose with author 'human', the exact call the board route makes (skipping only its HTTP body validation). board.json is synthesized (BOARD_KINDS imported, lastSeq=mapSeq, gitSha unknown) and disclosed. Stage 7 now checks prereq-failed before captures, requires probe=board-candidate, and passes `--map $S3FINAL --readback getmap.json` to post; statuses= comes from the store readback, so the multiset comparison is not self-referential. E1 (structureVersion 1 vs 2) did not fire: esas accepted the plugin's forks.

## D7 — BOARD-SETUP's graphless branch: start_map_session launches nothing; the owner launches `--non-anchor`
kind: false-premise
step: build · slice: S4 · decidedBy: verifier
sources: [code:startMapSession mkdir only (esas@de920db packages/esas-store/src/start-map-session.ts:104), code:launcher --non-anchor (esas@de920db packages/esas-session-server/src/launcher.ts:261-262,303), design:block §2 In "start_map_session, launch with esas-session-server --non-anchor"]
rejected: read block §2 as start_map_session launching the board — false at de920db and would contradict D3 (never launch)
supersedes: —
The block's §2 sentence compresses two steps; the doc states them separately. First draft of S4 (sonnet) carried this and five other prose errors caught by the verifier (fix round cause: mis-routed).
