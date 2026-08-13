# Board mode — registering, seeding, and the launch

The downstream half of `/design` **Step 0**. Open it only when both of that step's gates say yes: **relevance** — the drafted decision tree names a command, an event, an aggregate, a policy, a read model, or a coupling — and **capability**, the preflight's verdicts. The command keeps both gates, the preflight and the verdict table; each row of that table names the section here that answers the verdict it printed. On either no this file is never opened, and boards are never mentioned.

The *gestures* are the third thing and they are not here: the sync point, the summon, the withdrawal and correction gestures, the two restarts and the main-checkout-only fleet rule are the [`esas-design` skill](SKILL.md) beside this file, scoped differently on purpose — its standing rules fire wherever the `mcp__esas__*` tools exist, board mode armed or not. This file is only what `/design` does between a double yes and a working board.

## Registering `esas-mcp` — and the restart that makes it real

When the preflight says `mcp: registered`, call the `status` tool. It answers in exactly three ways:

- **It returns `{repoPath, gitSha, lastSeq, cursorSeq, pendingByAuthor, lockState, warnings}`** — board mode is live. Note `lastSeq` for the board comparison, and read `warnings` out loud if there are any: they mean another session is designing in this checkout, or that a writer is on a different build than yours.
- **There is no such tool in this session** — two causes, and they look identical from here. Either the entry was added by an earlier run and the session was never restarted: do the restart step below, and do **not** write the entry again. Or the server failed to spawn, in which case restarting changes nothing and the second attempt is the diagnosis: **still missing after a restart ⇒ the server failed to spawn** — check the entry's path resolves, and that the esas checkout has its dependencies installed (`bin/esas-mcp.mjs` runs the sources through `tsx`, so a fresh clone with no install dies at boot). Claude Code logs the spawn failure; read it rather than restarting a third time.
- **It returns `ESAS_DIR_MISSING`** — the server is running and answering about *this* checkout, which simply has no `.esas/`. In a fleet worktree that is **the correct answer, not a fault to fix** (see the skill's main-checkout rule). In the main checkout it means the extractor has not run here yet: `yarn esas`, then re-check. Do not add `ESAS_REPO_PATH` to point it elsewhere — that is how a worktree ends up writing into another checkout's design layer.

When the preflight says `mcp: unregistered` or `mcp: absent` — and the `mcp__esas__*` tools are not already in this session from a user-scoped registration — add the entry. **Add the one key to `mcpServers`** with an edit, not a read-modify-write of the whole file: rewriting it reformats every other server and turns a one-key diff into a whole-file one.

```jsonc
"esas": {
  "type": "stdio",
  "command": "node",
  "args": [ "<abs path to the esas checkout>/packages/esas-mcp/bin/esas-mcp.mjs" ]
}
```

Resolve the esas checkout from a link the host repo already has (teselly's `package.json` carries `"sticky-notes-board": "link:../esas/packages/sticky-notes-board"`, so it is `../esas`), and make it absolute. If nothing links esas, **ask** — do not guess a path.

**Do not set `ESAS_REPO_PATH`.** The server designs against its working directory, and Claude Code spawns a project server with the working directory set to the project root — including inside a worktree, where that is the worktree itself. `.mcp.json` is git-tracked, so the entry is byte-identical in every worktree of a fleet: pinning an absolute path there would make all of them design against the one checkout it names, which is exactly the split layer the main-checkout rule exists to prevent. Unpinned, a worktree answers `ESAS_DIR_MISSING`, which is the right answer there.

`.mcp.json` is git-tracked, so this dirties the working tree — say so, and let the user decide whether it ships with the PR.

Then **stop the command** with this, verbatim:

> **RESTART REQUIRED — `esas-mcp` is registered but not running.**
> Registration takes effect only at session start: Claude Code spawns stdio MCP servers when a session boots, so the tools do not exist in *this* one no matter what the file now says.
> Exit this session, start a new one in this repo, approve the `esas` server when Claude Code asks (repos with `enableAllProjectMcpServers` are not asked), and run `/design` again.
> No design write is lost — nothing has been written to `.esas/`, and `.work/design.md` is written at the end of the interview, not now. What the restart does cost is this session's reading: the grounding pass, and any forks already answered. The new session re-does them.

Three rules while this session lasts:

- **Do not call any `mcp__esas__*` tool for the rest of this session.** They are not there. A "no such tool" is not a transient failure to retry around.
- **Never substitute for the missing server.** Do not create or edit `.esas/design.json`, `.esas/ops.jsonl` or `.esas/.claude-cursor` by hand.
- **If the user does not restart** ("just keep going"): run Steps 1–4 with board mode off. That is a complete, correct `/design` — it produces `.work/design.md` and nothing else. Say once that the board layer will be there next session, then drop it.

## Seeding the design layer

`.esas/design.json` is the store's file and the store is the only writer: atomically, under a lock, with one attributed op appended to `.esas/ops.jsonl` per batch. **Never create or edit `.esas/design.json` by hand.** A hand-written verb has no op behind it, so it has no author, no rationale, no validation — the board renders a design nobody asserted, and the next `rebuild` (which replays the feed) drops it without a word.

So seeding is not a file write. `design: absent` already *is* the empty design everywhere that reads it — the board loader and `get_design` both answer with an empty document rather than an error. (The hook never opens `design.json` at all; it reads `ops.jsonl` against the cursor, so it is indifferent either way.) **The first `propose` seeds it**, through the same path every later write takes. Say that to the user instead of manufacturing an empty file.

What does need a decision is a layer that is already there. The design layer is gitignored and lives one unit of work, deleted after the merge — so `design: present` before you have written anything means you are resuming, or you are looking at residue. **Ask whose session it is.** Resuming keeps the verbs, the feed and the sync cursor and needs nothing done. Starting clean means the *user* deletes `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor`. Never delete them unasked: they are the only copy of a session's intent, and they are not in git.

(A sync cursor left behind by a previous feed reads as "nothing has been synced" and inflates the hook's pending count — see the `esas-pending` skill. That one is cosmetic and clears on the next sync. Another unit of work's *verbs* are not.)

## The board — offer the launch when there is something to see, verify the endpoint, never spawn it unasked

**Offer the board at the moment the first batch of questions is ready to post, and start it only on a yes.** That is the first moment it is worth looking at: before it the canvas holds the graph and nothing to answer, so the offer costs the user a second screen and gives them nothing to do on it. (The summon channel, below, is *not* gated on this moment — a held socket costs nothing while nobody presses.) Offer the line their repo uses — `yarn esas:board` in teselly, otherwise `node <esas checkout>/packages/sticky-notes-board/bin/esas-board.mjs` — together with the link the questions are behind, `?openComments=1&author=ai`, which opens on the open threads instead of on the whole canvas. On a yes, start it as a `Bash` call with `run_in_background`, which outlives the turn that started it; in the foreground it would hold that turn open for as long as the board serves. On a no, leave them the line and carry on — the board is a projection, and it opens current whenever they launch it.

**Never spawn it unasked, and never at the preflight.** The port is the reason, and it is strict (below): a board nobody asked for squats :3727 for as long as it runs, and the repo that pays is the *next* one — its board will not bind, in a session that did nothing wrong and has no reason to suspect a board it never started. An orphan is also the hardest kind to find, which is what the `board: other-repo` row of the command's verdict table is for. Offering at the preflight makes that the ordinary outcome rather than the unlucky one: the preflight answers *capability*, and a checkout that can hold a board is not yet a design that needs one.

The board claims **:3727 strictly**. It never drifts to the next free port, so `GET /api/esas/status` on that port either answers for this repo or does not answer at all. It returns `{repoPath, gitSha, lastSeq, sessions}`; `lastSeq` is the same number the `status` tool reports, which is what makes a dead link visible by comparing two screens instead of debugging, and `sessions` is how many sessions are holding the summon channel (`/api/esas/ws`) open right now. Read `sessions: 0` on a board serving this checkout as *nobody would hear the button* — open the channel. Do **not** build on it in the other direction: there is no heartbeat, so a half-open socket still counts, and `sessions >= 1` is not a guarantee that anyone is actually listening.

**Never block the design on the board.** It is the projection, not the source of truth: writes land in files through `esas-mcp`, and a board launched an hour later renders everything that already happened. What genuinely stops board mode is a missing `.esas/` (no substrate) or a missing server (no hands). A dark second screen is not one of them.

## What board mode changes about the rest of `/design`

- **Step 2 gains a surface.** Propose as decisions resolve, not in one dump at the end — the point is that the user watches the model take shape while you talk. Batch each turn's proposals into **one** call (arrays in, one write, one op).
- **Read reality with `get_flow`**, one command flow at a time, never by re-reading the whole graph. `scope.boundary` defaults to `'end-to-end'`; `'subdomain'` keeps a flow's cross-subdomain hand-offs visible as leaves rather than pretending the ripple stops at the boundary.
- **Open the summon channel once the board is up, and keep it open for the rest of the session.** It is one `Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })` call, and it needs no timing rule: a persistent socket is held for the life of the session, so there is no moment it must be armed at and no re-arming after a wake. That replaces a watcher that had to be armed on exactly the right turn and re-armed after every one — the arming, not the transport, was what kept failing. Open it early rather than late; the only cost of an early open is a wake on a press with nothing new behind it, which the skill's first invariant already tolerates. What the channel *is*, how the wake behaves, the two surviving invariants and the rule that reopens a channel reported closed are the `esas-design` skill's half; Step 0 decides only that it goes up.
- **The gestures live in the `esas-design` skill** — the sync point, the summon, corrections, restarts, and the fleet rule. Follow it; it is the behavioural half of Step 0.
- **Step 3 still writes `.work/design.md`.** The two surfaces are complementary, not redundant: `.work/design.md` carries the decisions — the forks, the why, the rejected options — and `design.json` (structure) carries the verbs. Both feed `/plan`, so do not thin one because the other exists.
