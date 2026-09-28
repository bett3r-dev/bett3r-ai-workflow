# Board mode: registering, seeding, the launch

Opened from `/design` Step 0 only when both gates said yes: **relevance** (the drafted tree names a command, event, aggregate, policy, read model or coupling) and **capability**, the preflight's verdicts. Once the board runs, the [`blueprint-design` skill](SKILL.md) takes over.

## 1. Registered: call `status`

On `mcp: registered`, call the `status` tool. It answers in one of three ways:

- **`{repoPath, gitSha, lastSeq, cursorSeq, pendingByAuthor, lockState, warnings}`**: board mode is live. Keep `lastSeq` for the board comparison; read `warnings` out loud.
- **No such tool in this session**: do §2's restart once, writing nothing again. Still missing after it means the server failed to spawn, which no restart fixes: check the entry's path and the checkout's dependencies, and read Claude Code's spawn log.
- **`BLUEPRINT_DIR_MISSING`**: this checkout has no `.blueprint/`. Correct in a fleet worktree (the skill's main-checkout rule); in the main checkout run the repo's `designTooling.extract` from `.blueprint.config.json` and re-check. A repo with no graph can still get a map: `design-map select` judges MCP capability and board reachability, `start_map_session` creates a bare `.blueprint/`, and the owner launches with `blueprint-session-server --non-anchor`.

Done when `status` has answered and its row is acted on.

## 2. Unregistered: add the entry, then stop

On `mcp: unregistered` or `mcp: absent`, unless the `mcp__blueprint__*` tools are already in the session: **Add the one key to `mcpServers`** with an edit, not a rewrite of the whole file:

```jsonc
"blueprint": {
  "type": "stdio",
  "command": "node",
  "args": [ "<abs path to the blueprint checkout>/packages/blueprint-mcp/bin/blueprint-mcp.mjs" ]
}
```

Resolve the checkout from a `link:../blueprint/...` dependency the host repo has, absolute; if nothing links blueprint, ask. **Do not set `BLUEPRINT_REPO_PATH`.** The server designs against its working directory, and `.mcp.json` is byte-identical across a fleet's worktrees, so a pinned path would point every worktree at one checkout's layer. The edit dirties the tree: say so.

Then stop the command with this, verbatim:

> **RESTART REQUIRED — `blueprint-mcp` is registered but not running.**
> Registration takes effect only at session start: Claude Code spawns stdio MCP servers when a session boots, so the tools do not exist in *this* one no matter what the file now says.
> Exit this session, start a new one in this repo, approve the `blueprint` server when Claude Code asks (repos with `enableAllProjectMcpServers` are not asked), and run `/design` again.
> No design write is lost — nothing has been written to `.blueprint/`, and the design file (`design.md`, in the folder `work-docs-path` names) is written at the end of the interview, not now. What the restart does cost is this session's reading: the grounding pass, and any forks already answered. The new session re-does them.

Until then:

- **Do not call any `mcp__blueprint__*` tool for the rest of this session.** A "no such tool" is not transient.
- **Never substitute for the missing server.** `.blueprint/design.json`, `.blueprint/ops.jsonl` and `.blueprint/.claude-cursor` are the store's files.
- **If the user does not restart**: run Steps 1–4 with board mode off, a complete `/design` producing the committed `design.md`; say the board layer arrives next session, then drop it.

Done when the RESTART block is printed and no `mcp__blueprint__*` call follows.

## 3. Seeding

The store is the only writer of `.blueprint/design.json`, one attributed op in `.blueprint/ops.jsonl` per batch. **Never create or edit `.blueprint/design.json` by hand**: a hand-written verb has no op, so no author and no validation, and the next `rebuild` drops it. `design: absent` already reads as the empty design; **The first `propose` seeds it**.

`design: present` or `ops: present` before you have written anything is a resume or residue: **ask whose session it is**. Starting clean means the *user* deletes `.blueprint/design.json`, `.blueprint/design.json.bak`, `.blueprint/ops.jsonl` and `.blueprint/.claude-cursor`, which are not in git.

## 4. The board: offer it, verify it, never spawn it unasked

Offer the board when **the first batch of questions is ready to post**. Offer the repo's line, `yarn blueprint:board` or `node <blueprint checkout>/packages/sticky-notes-board/bin/blueprint-board.mjs`, with the link the questions are behind, `?openComments=1&author=ai`. On a yes, start it as a `Bash` call with `run_in_background`; on a no, leave the line: the board is a projection and opens current whenever launched.

The board claims **:3727 strictly**, so `GET /api/blueprint/status` there either answers for this repo or not at all, with `{repoPath, gitSha, lastSeq, sessions}`: `lastSeq` matches the `status` tool's when the link is live; `sessions` is how many sessions hold the summon channel (`/api/blueprint/ws`) open. `sessions: 0` on a board serving this checkout means nobody would hear the button: open the channel.

Done when the board answers `/api/blueprint/status` for this repo and the channel is open.

Boundaries:

- **Spawn it only on the user's yes**, never at the preflight: an unwanted board squats :3727 for as long as it runs and the next repo's board fails to bind.
- **Never block the design on the board.** Writes land in files through `blueprint-mcp` and a board launched later renders all of it; only a missing `.blueprint/` or server stops board mode.

## 5. Board mode in the rest of `/design`

- Step 3 gains a surface: propose as decisions resolve, each turn's proposals in **one** call.
- Open the summon channel as soon as the board is up (`Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/blueprint/ws' }, persistent: true })`); the skill owns the wake.
- Step 4 still commits `design.md` in the folder `work-docs-path` names: `design.md` carries the decisions, `design.json` (structure) the verbs, and both feed `/plan`.
