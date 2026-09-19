---
name: esas-design
description: "ESAS board (.esas/, esas-mcp). 'look at the board' = read_changes, reconcile, mark_synced, whole. Unread edits: asked, sync first; else say you're behind. CONFLICT_PENDING_SYNC: one sync, retry whole."
---

# Designing on the board

These rules hold wherever the `mcp__esas__*` tools exist, board process running or not. `/design` sets the board up (PREFLIGHT.md, BOARD-SETUP.md). Once it runs, the user edits the board on one screen, you write through `esas-mcp` from the terminal, and both land in one attributed design layer. You are turn-based and cannot see the board move; everything below follows from that.

## The sync point: "look at the board"

Any phrasing counts (*look at the board*, *I moved some things*, *check what I did*). The gesture is three steps, run whole and in order:

1. `read_changes`: defaults to the cursor and to semantic ops; sticky drags stay excluded.
2. Reconcile, and say what you make of it in the terminal; ops carry full payloads.
3. `mark_synced(lastSeq)` with the seq `read_changes` reported, only after you have responded.

Reading without `mark_synced` leaves the count stuck and the next write refused; `mark_synced` without reading claims knowledge you do not have.

The gesture is the user's to start. The `esas: N pending` line is telemetry (`esas-pending`); with edits unread you say your picture may be behind instead of asserting what the design says, and let the user decide. Two things are asks, and neither is the count: a refused write, and a summon.

### A refused write

`CONFLICT_PENDING_SYNC` means the batch touched an element the user edited since your cursor. The store refuses the whole batch and names the conflicting ids and the `sinceSeq`; nothing was written. One `read_changes({ sinceSeq })`, reconcile, `mark_synced`, then retry the same batch unchanged. Never item by item: the refusal already named the entry, and probing turns one refusal into a dozen writes racing the user's next edit. Keep the wording too; the user's edit may be the answer to the proposal.

## The summon: the board asking you to look now

The user presses **Ask Claude**; the board POSTs `/api/esas/board/summon` and broadcasts one frame, `{"type":"summon","at":<epoch ms>}`, to every session holding the channel open. It says *look now*, never *look at this*: what changed is already in the feed. Hold the channel open from anywhere and let the turn end:

```
Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })
```

`persistent: true` makes it session-scoped rather than turn-scoped; the `SessionStart` hook's notice is a nudge to make this call. Hand the user `?openComments=1&author=ai`, which opens the board on the open threads.

On a wake, run the sync gesture whole. **Two invariants:**

1. **Tolerate an empty wake.** A press means the user pressed, not that `read_changes` has something. "Nothing new since the cursor" is a normal outcome: say so in one line and go back to waiting.
2. **Never propose from partial answers**: only for forks whose dependencies are all resolved. A press means *I answered something*, never *I answered everything*.

The wake arrives wrapped in a platform banner declaring itself not user input. Every word of the banner is accurate and none of it is about what the read returns: **the notification is the doorbell, not the sentence.** What the user said is in the feed; sync.

### Reopen a closed channel the moment you are told

`Monitor`'s watch ends when the socket closes, with no auto-reconnect, so a board restart (every `design.json` write is one) leaves you deaf. While the channel is shut, every `esas-mcp` result carries an extra text block:

```json
{ "esasSessionChannel": {
    "code": "SESSION_CHANNEL_CLOSED",
    "message": "…",
    "ws": "ws://127.0.0.1:3727/api/esas/ws" } }
```

Reopen it then and there, unasked: `Monitor` on that `ws`, `persistent: true`, and say so in one line. Three consumer rules:

- Branch on `code`, never on `message`: the message is prose that will be reworded. Standing convention for every ESAS result.
- Dial the `ws` field; do not reconstruct it. The board can move (`--port`, `ESAS_BOARD_PORT`), and a rebuilt URL reopens a channel to nothing while reporting success.
- A missing notice means nothing to do. It is emitted only while the channel is provably shut; an unreachable board, a board on another checkout and a channel someone else holds are **all silent**, so absence is never "fine".

### Cross-repo literals: copy, never reword

Each is pinned in esas@master and nothing links the two repos at build time, so a paraphrase breaks the gesture with both suites green on both sides: `/api/esas/ws` (session channel) · `POST /api/esas/board/summon` (the press) · `?openComments=1&author=ai` (handoff link) · `code` + `ws` + `SESSION_CHANNEL_CLOSED` (the notice's keys and its one code) · `3727` (the port, claimed strictly). On that side the port and both routes have one definition, `esas-store/src/board-endpoints.ts`.

## The map and the questions

**The terminal carries the tree, the board carries the questions.** The terminal names each fork in one line of `grill`'s decision tree; the board holds the fork (options, recommendation, thread) as a `comment` anchored to the element it concerns. **Neither surface is a copy of the other**, so there is nothing to keep in sync; a fork asked in both places is answered where you are not looking, or twice.

**Batch the independent forks to the board; serialize the dependent ones in the terminal.** A fork is independent when you could write it out in full right now; those go up in one `comment` call and get answered in any order. A dependent fork's wording does not exist yet, so posting it posts your guess under your name, and an answered guess resolves a fork nobody asked: the summon's second invariant, pointed at asking. `resolve` each comment as its fork is answered; `resolved: false` is the shared to-decide list, the only state the two surfaces share. `comment` has no edit verb, and an in-place `design.json` edit is invisible until the board reloads: post a reply, or say "reload".

A comment that asks a fork is written as `grill` presents one (its literal headings, every reference restated at every mention). Prefer a node anchor: the spine couplings (`handled-by`, `produces`, `issues`) usually draw no line, so a comment anchored there has nowhere to show. One fenced ```` ```mermaid ```` block per comment where the problem has a shape; bold the load-bearing claim inside a sentence, so a skim of headers and bold gets the shape.

## remove: "scrap that, I was wrong"

Changing your mind about your own proposal is `remove`, and nothing extra. The tool decides what the deletion means from the target: an element in reality stays on the board desaturated (no propose-edge may touch it); an element only proposed by this design is withdrawn, taking its proposed edges, the `modify`s standing on it, and the comments anchored to those.

Boundaries: a refused removal is said and stopped at, never routed around; and the element is withdrawn, not renamed `"(RETRACTED)"`, annotated or parked, since each of those leaves a sticky asserting an element that does not exist. Two consequences to weigh first:

- **The thread goes with it**: a comment on nothing is never drawn again. A conclusion worth keeping goes to the terminal, or the comment is re-anchored first.
- **It is not undo-able from the board.** A rebuild re-applies the op; recovery means proposing it again.

`remove` and `reclassify` both end with an entry leaving `design.json`. **Withdrawing says *this was never right*; reclassifying says *this is already true*.** Guess wrong toward reclassify and a phantom element enters a git-tracked file that ships with the PR.

## reclassify: "that rename is a correction"

When a board edit is not design intent (the extractor mislabelled something, or a coupling already exists in code ESAS cannot see) **and the user says so**, `reclassify` moves the payload from `design.json` to `.esas.overrides.json`, author and note intact. Reclassify only what the user called a correction; a proposal you merely believe is implemented is a question for them. Say three things out loud:

- It dirties the working tree: `.esas.overrides.json` is git-tracked, so the correction ships with the PR, which is the point.
- The diff may look bigger than the change: the store rewrites through a JSON round-trip, normalising whitespace and key order.
- A refusal is information: `RECLASSIFY_WOULD_BE_STALE` means an id the extracted graph lacks, or an edge whose endpoint is still a proposal. The error names the alternative, and the correction still applies in the design layer.

## A label is a code-identity contract

A proposed node's id derives from `(subdomain, type, label)`, and `/build`'s scaffold step generates the artifact from that id, so renaming or re-homing a proposal renames code not yet written: say so before you `modify` one. After the artifact exists, a board rename without the code rename leaves the proposal never `satisfied` and a phantom artifact on the board while everything compiles. Draw the edges the scaffolder reads: a policy needs its `issues` edge to be placed, a command its `handled-by` edge to have a file; both are refused rather than guessed.

## The two restarts

- Pulled esas mid-session? Restart the session **and** the board. The MCP server spawns at session start and the board reads its sources at boot, so both run old code after a pull.
- Registered `esas-mcp` this session? The tools exist from the next session on (BOARD-SETUP.md §2).

## Main checkout only

Board collaboration happens in the main checkout. A fleet worktree has no `.esas/` and every tool answers `ESAS_DIR_MISSING`, the correct answer there; the read-only `.work/design-snapshot/` a lane carries is the provisioner's copy, not a session. In a worktree, write the design to the folder `work-docs-path` names, create no `.esas/` there and call no esas tool; a design found wrong there is an escalation to the orchestrator. One design session per checkout: if `status` warns another is designing here, say so.

## Writing and reading

The verbs are `propose`, `modify`, `remove`, `reclassify`, `comment`, `resolve`, `get_flow`, `get_design`, `read_changes`, `mark_synced`, `status`. **A refused verb is a fact to report**, never a reason to reach for one that lands or for a file edit: say what you tried, quote what it said, let the user decide.

**Batch.** Arrays in, one write, one op out: ten proposals in one `propose` is one feed entry the user reads.

**Read ids before referencing them.** No verb lists node ids (`get_flow` requires a root command id), so grep `.esas/graph.json` for ids and for the legal edge triples before proposing an edge. Ids read `<subdomain>_<abbrev>_<kebab-label>` with abbrevs `cmd`, `evt`, `rm`, `agg`, `pol`, `sys`, `ext`, `ui`. Two things break the obvious guess: extracted `ext` ids carry an extra `external-system-` segment a proposed node will not reproduce, so an edge to `…_ext_external-system-foo-api` fails `UNRESOLVED_EDGE_ENDPOINT` against a node that landed as `…_ext_foo-api`; and label casing is load-bearing (the caser splits internal capitals and acronyms), so prefer plain Title Case. Where a batch introduces a node later edges point at and the id is not certain, propose the nodes first, read the returned `nodeIds`, then send the edges.

**`reads-from` is only legal from a policy, read model or aggregate.** An external system that queries a read model expresses that on the policy that drives it.

**Read flow-sized.** `get_flow(rootCommand, scope?)` walks one command's ripple over the merged graph; `scope.boundary` defaults to `'end-to-end'`, and `'subdomain'` keeps cross-subdomain hand-offs visible as leaves. `get_design` returns the verb delta. Neither is "read the whole graph".
