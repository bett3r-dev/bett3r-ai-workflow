# `design-map select` captures

One file per input the agent captures before calling `design-map select`
(ESAS-174 D1/D2, design.md P1). The tests assemble a captures directory per
case under `$TMP`, copying these under the names `select` reads (`tools.txt`,
`status.json`, `board.json`, `start.json`) and writing a `pwd.txt` whose paths
are `/work/design-repo`, the `repoPath` of `board-map.json`.

The JSON shapes are copied from esas at the ESAS-156 integration base
(`esas-int156` @ de920db):

- `status-*.json`: the `status` tool's body. Success is `EsasStatusResult`
  (`packages/esas-store/src/design-store.ts:554`) plus `capabilities`
  (`packages/esas-mcp/src/handlers.ts:714-732`, `capabilities.ts`); a failure is
  `ToolFailure` `{ok:false, error:{code,message,details?}, capabilities?}`
  (`packages/esas-mcp/src/tool-result.ts:24-39`). The `ESAS_DIR_MISSING` message
  and details are `missingEsasDir` (`packages/esas-store/src/local-fs-substrate.ts:133-139`).
  `-old` variants carry no `capabilities`: an esas-mcp that predates ADR-061.
- `tools-*.txt`: the tool names `packages/esas-mcp/src/server.ts` registers, one
  per line; `tools-no-post.txt` lacks `map_post`.
- `board-*.json`: `BoardStatus`
  (`packages/sticky-notes-board/src/vite-plugin-esas-fs/board-identity.ts:79-165`),
  `boardKinds` from `BOARD_KINDS` (`packages/esas-store/src/board-endpoints.ts:196`).
  `board-nokinds.json` is a board that predates the map view.
- `start-*.json`: `start_map_session`'s body, `MapSessionResult`
  (`packages/esas-store/src/start-map-session.ts:38-43`) on success; the
  `LINKED_WORKTREE` refusal is `start-map-session.ts:87-91`.
- `map-pinned-artifact.json`: `../decision-3-forks.json` with top-level
  `target: "artifact"` (D9).

`design-map post` readbacks (ESAS-174 D7/D5, design.md P3):

- `post-map-4.json`: a v2 map.json with one fork per status: decided(owner),
  decided(recommendation), moot, open. `post-map-4-open.json` is the same map
  with every fork open, the local map before a D5 readback.
- `getmap-*.json`: the `get_map` tool body, `ToolSuccess<MapReadResult>`
  (`packages/esas-mcp/src/tool-result.ts:19-21`, `handlers.ts:801`,
  `packages/esas-store/src/map-write.ts:161-165`). Its map is esas's `MapFile`
  (`packages/esas-schema/src/map-structure.ts:120-129`): `structureVersion: 1`,
  `links` required, and forks as `postedMapEntry` folds them
  (`packages/esas-store/src/replay.ts:703-722`), with no `tickets`.
  `getmap-4.json` matches `post-map-4.json`. `-3` drops the open fork,
  `-flipped` turns recommendation into owner, `-option` changes a decided
  option, `-reason` changes the moot reason, and `-kind` turns the open fork
  into a moot with no reason, a shape esas never emits.
