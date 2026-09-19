# Fleet readers and the board target

Companion to SKILL.md for `/design-multi`, a `design-lane`, and any design that may live on a board; every verdict is a `DESIGN-MAP:v1` line on stdout.

## Stacking several maps on one page

```
design-map render --stack <m1> <m2>... --expect <n1> <n2>... --out <page.html>
```

Every map is validated and must be grounded (refusals name `map=`). One `--expect` per map in argument order; `--out` is required; a fork id in two maps is `duplicate-fork-id`. A refusal leaves no page and removes an earlier one at `--out`. Sections are ordered: most `open` forks first, then the lowest ticket key over the map's forks' `tickets` (project, then number; a map with no forks last), then argument order. Answers carry `map: <mapId>`. Verdict: `outcome=ok verb=render maps=<n> forks=<sum> expected=<sum> page=<path>`; `check-page` takes no `--stack`.

## Projecting a ticket's forks

```
design-map project --ticket <K> <map>... | design-map write <units/K.map.json>
```

`project` prints the v2 map of K: the forks whose `tickets` contain K, their anchors and ancestors as nodes, `restsOn` and links pruned to what is kept, `mapId` K, `grounded` and `shape` from the inputs (refused when they disagree); `feedSeq` and `target` are not carried over. The verdict follows the JSON as the last stdout line; `write` drops `project`'s ok line and refuses `reason=upstream-refused` on any other, so a refused projection is never written as a map.

## Listing decisions per ticket

```
design-map decisions <map.json> [--closed]
```

Prints a `## <ticket>` heading per ticket and one line per fork carrying it: `- <forkId> <title>: owner — <option> (<label>)`, `applied on recommendation — …`, `code — …`, `moot — <reason>`, or `open`. With `--closed`, any open fork is `outcome=fail reason=open-forks` (exit 1), the Markdown still printed first.

## Folding answers in the sitting

`apply-answers` over a stacked page's readback skips unchecked, and counts in `otherMap=`, an answer whose `map` is not this map's `mapId`; an answer with no `map` applies. `esas-design`'s two invariants hold as for a summon: an empty fold is normal, and a mid-sitting readback is a snapshot to act on only once every fork a fork rests on is resolved; `--final` waits for the owner's terminal word (SKILL.md).

## Recording an answered fork

```
design-map record <map.json>
```

`record` is pure over files: no network call, no subprocess, no tool of its own. Before the verdict it prints one payload per fork with a `decided` status, in map order: `forkKey` (the join key), `question`, `options` (every label), `chosen` (the `status.option` id), `chosenLabel`, `rationale` (`recommendation.why`), `source`, `tickets`. An `open` or `moot` fork counts in `unresolved=`, a decided fork with no card in `nocard=`; neither gets a payload.

The caller makes the recording call the host declares (CONTEXT-PROVIDERS.md), one per payload, exactly as the fields read, and reads its answer. Never probe whether the provider is up before calling: the call's own result says; a refusal or timeout is the tolerated failure, one notice per fork, not reported as recorded. Where the call hands back an id, that id has one home: the sidecar the verdict names as `sidecar=`, `<map stem>.resolved-by.json` beside the map, keyed by fork id and committed with it; beside because the fork's shape is a closed set shared with esas, named after its map because a run dir holds one map per subject, distinct from a status's `resolvedBy`. `record` reads the sidecar and never writes it: a fork whose id it holds counts in `already=` and is not offered again; an unparseable sidecar is `reason=sidecar-unparseable`, never an empty start.

## Choosing the target: board or artifact

```
design-map select --phase probe|start --captures <dir> [--map <map.json>] [--lane <lane.yaml>]
```

`select` is pure over a **captures directory** you assemble from what the session already showed, always these names: `tools.txt` (the session's tool names, one per line, bare or `mcp__<server>__<name>`), `status.json` (the whole body the `status` tool returned), `board.json` (the body of `curl -s --max-time 2 http://127.0.0.1:${ESAS_BOARD_PORT:-3727}/api/esas/status`, a ceiling, not a retry budget), `start.json` (the `start_map_session` body, `--phase start` only; absent there it is `outcome=error reason=missing-start`) and optionally `pwd.txt` (logical and physical cwd, one per line). First match wins:

| row | condition | verdict |
|---|---|---|
| 0 | `--map` given and its `target` is `artifact` | `target=artifact reason=pinned probe=skipped` |
| 1 | `--lane` (default `.work/lane.yaml`) exists | `target=artifact reason=fleet-lane probe=skipped` |
| 2 | `tools.txt` lacks `status` | `artifact reason=no-mcp` |
| 3 | `status.json` lacks `capabilities.verbFamilies` containing `map` | `artifact reason=mcp-no-map` |
| 4 | `tools.txt` lacks any of `map_post`, `get_map`, `start_map_session` | `artifact reason=tools-missing` |
| 5 | `status.json` is not `ok: true` and its error code is not `ESAS_DIR_MISSING` | `artifact reason=mcp-error` |
| 6 | `board.json` is empty or not JSON | `artifact reason=board-off` |
| 7 | its `repoPath` is not this cwd | `artifact reason=board-other-repo` |
| 8 | its `boardKinds` lacks `map` | `artifact reason=board-no-map` |
| probe | every row passed | `target=board-candidate reason=ok probe=done` |
| 9-11 (`start` only) | `start.json` is not `ok: true` | `artifact reason=linked-worktree` on `LINKED_WORKTREE`, else `start-failed` |
| | `start.json` is `ok: true` | `target=board reason=ok probe=done` |

**`probe` first, and only a `board-candidate` calls anything.** On `board-candidate`, call `start_map_session` yourself (the one side effect: it creates `.esas/`), capture its body as `start.json`, then run `--phase start`, which re-evaluates rows 0-8 before 9-11. The first `start` is followed by a `design-map write` carrying the resolved `target`, so later calls short-circuit at row 0; a `board` pin re-probes at the next sync point.

**Silence.** Nothing in an artifact-target design names a board, a port or `.esas/`, with two exceptions: on row 7 tell the owner which repo holds the port (`board.json`'s `repoPath`); on row 6, attended only, print the launch line one time, as information, never as a question (`esas-session-server --non-anchor` with no graph, `ESAS_DIR_MISSING`; otherwise BOARD-SETUP.md's launch line).

Boundaries: neither this skill nor `select` launches a process; no row retries, polls or waits past the curl's `--max-time 2`, so a wedged board reads as `board-off` and the design proceeds on the artifact.

**The board dies mid-sitting.** When `board.json` comes back empty on a design already `target=board`: call `get_map` one time; if it answers, merge its readback statuses onto the local `map.json` by fork id (unknown forks ignored, unmentioned forks unchanged), set `feedSeq` to its `mapSeq`, pipe the result into `design-map write <map.json>`, and tell the owner in the row-6 wording. Still down at the next sync point: render the artifact from `map.json` as it stands. A failed MCP call anywhere here ends MCP calls for the session.

## Proving board parity

```
design-map post --expect <n> --map <map.json> --readback <getmap.json>
```

After any upsert (`map_post` or `map_choose`), call `get_map` and check the store, never pixels: `post` fails on a fork count other than `--expect` or a different multiset of `(kind, source, reason, option)`, and prints `statuses=<sorted kind:source,...>` for the epic oracle. `map_ground` replays before any `map_post`; `map_choose` passes the map's own `mapSeq` as `seenSeq` and never `source`. A grill takes `verb=render` or `verb=post` with `outcome=ok` as the design being live. `/design-multi` calls `select` once per subject, never stacked.
