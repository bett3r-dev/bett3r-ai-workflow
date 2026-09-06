---
name: esas-design
description: "For a live ESAS design-board session (.esas/ plus the esas-mcp tools). STANDING RULES wherever those tools exist: 'look at the board' — any phrasing — means read_changes, then reconcile, then mark_synced, in that order, never half of it, never unasked; with unread board edits, do not assert what the design says — sync first if they asked you to look, else say your picture may be behind and let them decide; a write refused with CONFLICT_PENDING_SYNC is cleared by ONE read_changes + mark_synced at the seq it named and the SAME batch retried whole; a summon frame on the ESAS session channel (/api/esas/ws, held open with Monitor) is the user pressing 'look now' — the answers are in the feed, not the wake — run that gesture whole; and an esas-mcp result carrying an esasSessionChannel notice with code SESSION_CHANNEL_CLOSED means reopen it unasked on the ws URL it names. Here: the summon's two invariants, the withdrawal/correction gestures, the restarts, the main-checkout-only rule."
---

# Designing on the board

`/design` sets this up (PREFLIGHT.md for capability, `esas-design`'s
BOARD-SETUP.md for registration, seeding and launch). This is what to *do* once
it is running: the user edits a board on one screen, you write through
`esas-mcp` from the terminal, and both land in one attributed design layer.

**You are turn-based and cannot see the board move.** Everything below follows
from that one fact.

## The sync point — "look at the board"

Any phrasing counts: *look at the board*, *I moved some things*, *check what I
did*. The gesture is three steps and is never run in halves:

1. `read_changes` — defaults to the cursor and to semantic ops; sticky drags
   are excluded and should stay that way.
2. **Reconcile, and say what you make of it in the terminal.** Ops carry full
   payloads, so a burst is readable without re-reading the design.
3. `mark_synced(lastSeq)` — the seq `read_changes` just reported, and only
   *after* you have responded.

Reading without `mark_synced` leaves the count stuck and the next write refused;
`mark_synced` without reading is a lie about what you know.

**Never start this yourself.** The `esas: N pending` line is telemetry, not a
trigger (see `esas-pending`). The one thing it changes is that you stop
asserting the design as fact until the user asks you to look — with edits
pending and no invitation, say your picture may be behind and let them decide.

Two things are asks, and neither is the count: a **refused write**, which names
the seq to read from; and a **summon**, which is the user pressing a button.

### A refused write

`CONFLICT_PENDING_SYNC` means the batch touched an element the user edited since
your cursor. The store refuses **the whole batch** and names the conflicting ids
and the `sinceSeq`; nothing was written.

One `read_changes({ sinceSeq })`, reconcile, `mark_synced`, then **retry the
same batch unchanged**. Never item by item — the rejection already named the
entry, and probing turns one refusal into a dozen writes racing the user's next
edit. Do not reword the proposal to dodge the conflict either; the user's edit
may be the answer to it.

## The map and the questions

**The terminal carries the map, the board carries the questions.** The terminal
*names* each fork in one line of `grill`'s decision tree; the board *holds* the
fork — options, recommendation, thread — as a `comment` anchored to the element
it concerns. **Neither surface is a copy of the other**, so there is nothing to
keep in sync. Ask a fork in both places and the user answers where you are not
looking, or answers twice, or reads the canvas as a stale echo and stops looking
at it.

**Batch the independent forks to the board; serialize the dependent ones in the
terminal.** A fork is independent when you could write it out in full right now.
Those go up in **one** `comment` call and get answered in any order — that is
the entire payoff of a canvas, since a serial question posted to a board is just
a slower terminal. A dependent fork cannot go up at all: its *wording* does not
exist yet, so posting it posts your guess at what the user is about to say,
under your name, and an answered guess resolves a fork nobody asked. It is
the summon's second invariant — *never propose from partial answers* —
pointed at asking instead of proposing: the same dependency edge, one step
earlier.

`resolve` each comment as its fork is answered. `resolved: false` is the shared
to-decide list, and it is the only state the two surfaces share.

## The summon — the board asking you to look *now*

The user presses **Ask Claude**; the board POSTs `/api/esas/board/summon` and
broadcasts one frame `{"type":"summon","at":<epoch ms>}` to every session
holding the channel open. It says *look now*, never *look at this* — what
changed is already in the feed.

Hold the channel open with `Monitor`, from anywhere, and let the turn end:

```
Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })
```

`persistent: true` makes it **session-scoped rather than turn-scoped**, which is
the whole mechanism: a command-scoped channel dies at every session boundary and
only the user remembering to ask brings it back.

**No hook can do this.** `FileChanged` has no decision control (side effects
only, cannot inject context); `Stop` fires the instant you finish posting, before
anything is answered. Ruled out at the mechanism level. This plugin's
`SessionStart` hook may *tell* you to open the channel — that is a nudge to run
the `Monitor` call, not a second wake mechanism.

Hand the user `?openComments=1&author=ai` — it opens the board on the open
threads instead of the whole canvas.

**Two invariants:**

1. **Tolerate an empty wake.** A press means the user pressed, not that
   `read_changes` has something. "Nothing new since the cursor" is a normal
   outcome — say so in one line and go back to waiting. A press with nobody
   connected reaches nobody and leaves nothing behind, so no state on disk can
   be misread as a wake later.
2. **Never propose from partial answers** — only for forks whose dependencies
   are all resolved. A press means *I answered something*, never *I answered
   everything*.

**Expect the wake to arrive wrapped in a platform banner declaring itself not
user input, and sync anyway.** Every word of the banner is accurate and none of
it is about what the read returns: **the notification is the doorbell, not the
sentence.** What the user said is in the feed. Taken for a refusal, it ends the
board session silently while the user watches a canvas that answered nothing.

### Reopen a closed channel the moment you are told it is closed

`Monitor`'s watch ends when the socket closes and there is no auto-reconnect, so
a board restart leaves you **deaf** with nothing on either side saying so. While
the channel is shut, **every `esas-mcp` result carries an extra text block**:

```json
{ "esasSessionChannel": {
    "code": "SESSION_CHANNEL_CLOSED",
    "message": "…",
    "ws": "ws://127.0.0.1:3727/api/esas/ws" } }
```

Reopen it **then and there, unasked** — `Monitor` on that `ws`, `persistent:
true`. Say it in one line; do not make it a question. Three consumer rules:

- **Branch on `code`, never on `message`** — the message is prose that will be
  reworded. Standing convention for every ESAS result.
- **Dial the `ws` field; do not reconstruct it.** The board can move
  (`--port`, `ESAS_BOARD_PORT`), and a rebuilt URL reopens a channel to nothing
  while reporting success.
- **A missing notice means nothing to do.** It is emitted *only* while the
  channel is provably shut. An unreachable board, a board on another checkout,
  and a channel someone else holds are **all silent** — absence is never "fine".

### Cross-repo literals — copy, never reword

Each is pinned in esas@master and **nothing links the two repos at build time**,
so a paraphrase breaks the gesture with both suites green on both sides:
`/api/esas/ws` (session channel) · `POST /api/esas/board/summon` (the press) ·
`?openComments=1&author=ai` (handoff link) · `code` + `ws` +
`SESSION_CHANNEL_CLOSED` (the notice's keys and its one code) · `3727` (the
port, claimed strictly). On that side the port and both routes have one
definition, `esas-store/src/board-endpoints.ts`.

## remove — "scrap that, I was wrong"

Changing your mind about your **own** proposal is `remove`, and nothing extra.
The tool decides what the deletion means from what the target is: an element in
**reality** stays on the board desaturated (no propose-edge may touch it); an
element **only proposed by this design** is withdrawn, taking its proposed
edges, the `modify`s standing on it, and the comments anchored to those.

Do not rename it `"(RETRACTED)"`, annotate it, or park it out of the way — each
leaves a sticky asserting an element that does not exist, and the board cannot
show that a label is a disclaimer. If a removal comes back refused, **say so and
stop**; never route around it.

Two consequences, weighed before you withdraw:

- **The thread goes with it** — a comment on nothing is never drawn again. If
  the conversation reached a conclusion worth keeping, say it in the terminal or
  re-anchor it first.
- **It is not undo-able from the board.** A rebuild re-applies the op; recovery
  means proposing it again.

`remove` is not `reclassify`, and both end with an entry leaving `design.json`.
**Withdrawing says *this was never right*; reclassifying says *this is already
true*.** Guess wrong toward reclassify and you write a phantom element into a
git-tracked file that ships with the PR.

## reclassify — "that rename is a correction"

When a board edit is not design intent — the extractor mislabelled something, or
a coupling already exists in code ESAS cannot see — and **the user says so**,
`reclassify` moves the payload from `design.json` to `.esas.overrides.json`,
author and note intact. Reclassify only what the user called a correction; a
proposal you merely believe is implemented is a question for them.

Say three things out loud:

- **It dirties the working tree.** `.esas.overrides.json` is git-tracked, so the
  correction ships with the PR. That is the point — a fact about reality belongs
  in the repo, not a file that dies at merge.
- **The diff may look bigger than the change** — the store rewrites through a
  JSON round-trip, normalising whitespace and key order.
- **A refusal is information.** `RECLASSIFY_WOULD_BE_STALE` means an id the
  extracted graph lacks, or an edge whose endpoint is still a proposal. The
  error names the alternative, and the correction still applies in the design
  layer.

## A label is a code-identity contract

A proposed node's id is derived from `(subdomain, type, label)`, and `/build`'s
scaffold step generates the artifact from that id — its export name, its file
name, and the module it lands in. So on the board a label is not a caption:

- **Renaming a proposal renames the code that has not been written yet.** Say
  so before you `modify` one. After the artifact exists, a board rename and a
  code rename are two halves of one change, and doing only the first makes the
  design stop converging: the proposal never flips to `satisfied`, and the
  board reports a phantom artifact forever while the code compiles and the
  tests pass. Nothing goes red — this is a failure you only find by looking.
- **The subdomain is part of the id too**, so re-homing a proposal is the same
  kind of edit, not a filing decision.
- **Draw the edges the scaffolder reads.** A proposed policy with no `issues`
  edge cannot be placed (its module is the one whose state it changes), and a
  proposed command with no `handled-by` edge has no file to live in. Both are
  refused rather than guessed — which is the board telling you a question is
  still open, and is worth answering there rather than in the code.

## The two restarts

- **Pulled esas mid-session?** Restart the session **and** the board. The MCP
  server spawns once at session start and the board reads its sources at boot,
  so both run old code after a pull — writer-version skew in the ops feed is
  this surfacing.
- **Registered `esas-mcp` this session?** The tools do not exist until the next
  one. Do not work around a missing server by hand-writing `.esas/design.json`.

## Main checkout only

Board collaboration happens in the **main checkout**, never a worktree. A fleet
worktree has no `.esas/` and every tool answers `ESAS_DIR_MISSING` — the correct
answer, not a setup problem. Creating one there enrols a throwaway tree in a
design session and splits the layer in two. In a worktree, design in
`.work/design.md` and leave the board alone.

One design session per checkout. If `status` warns another session is designing
here, say so — two sessions sharing one cursor lose each other's syncs quietly.

**A read-only snapshot is not a board.** A fleet lane may carry
`.work/design-snapshot/` — a copy of `design.json` + `graph.json` that
`/build`'s scaffold step reads. That changes nothing here: it is two documents,
not a session; no esas tool points at it, nothing written there reaches the
board, and `ESAS_DIR_MISSING` remains the right answer in that worktree. The
rule is about **writing** the layer and about session identity, and a copy has
neither. If a lane finds the design wrong, that is an escalation to the
orchestrator — never an edit made there and never a `.esas/` created to make
the tools work.


## Writing and reading

**Batch.** Arrays in, one write, one op out. Ten proposals in one `propose` is
one entry in the feed the user reads; ten calls is ten collisions waiting.

**Read ids before referencing them — never guess a derived id.** No verb lists
node ids (`get_flow` *requires* a root command id you already have), so the
entry point is grepping `.esas/graph.json`. Ids read
`<subdomain>_<abbrev>_<kebab-label>` (`cmd`, `evt`, `rm`, `agg`, `pol`, `sys`,
`ext`, `ui`). Two things break the obvious guess:

- **Extracted `ext` ids carry an extra `external-system-` segment a *proposed*
  node will not reproduce** — it comes from the extractor's artifact naming, not
  from `(subdomain, type, label)`, so an edge to
  `…_ext_external-system-foo-api` fails `UNRESOLVED_EDGE_ENDPOINT` against a
  node that landed as `…_ext_foo-api`.
- **Label casing is load-bearing.** `"MercadoLibre Messaging API"` does not kebab
  to `mercadolibre-messaging-api` (the caser splits internal capitals and
  acronyms); `"Mercalibre Messaging Api"` does. Same artifact, two ids, no
  warning — and it survives review because it is a correctly-spelled label.
  Prefer plain Title Case wherever the derived id will be referenced.

So where a batch introduces a node later edges must point at and the id is not
certain, **propose the nodes first, read the returned `nodeIds`, then send the
edges** — a deliberate exception to *batch everything*, because `propose`
rejects the whole batch and the no-take-it-apart rule makes each miss a full
round-trip.

**`reads-from` is only legal from a policy, read-model or aggregate.** An
external system that genuinely queries a readmodel expresses that on the
**policy that drives it**. A modelling constraint to know up front, not on
rejection.

**Read flow-sized.** `get_flow(rootCommand, scope?)` walks one command's ripple
over the merged graph (extracted + overrides + design), the same walk the board
draws. `scope.boundary` defaults to `'end-to-end'`; `'subdomain'` keeps
cross-subdomain hand-offs visible as leaves rather than pretending the ripple
stops at the boundary — it is **not** a token lever (foreign nodes still carry
full `queries` arrays). `get_design` returns the verb delta, not a copy of the
graph. Neither is "read the whole graph", which stays the thing not to do.

The verbs are `propose`, `modify`, `remove`, `reclassify`, `comment`, `resolve`,
`get_flow`, `get_design`, `read_changes`, `mark_synced`, `status`. If a gesture
needs something not on that list, say so rather than improvising a file edit.

**A refused verb is a fact to report, never a reason to reach for one that
lands.** Writing the intent into a label, note or comment because the right verb
would not go through records a contradiction on the user's canvas, in the field
they read as the truth. Say what you tried, quote what it said, let them decide.

### Writing a comment that asks a fork

`comment` and `resolve` are the grill on canvas. Prefer a **node anchor** — the
spine couplings (`handled-by`, `produces`, `issues`) usually draw no line, so a
comment anchored there has nowhere to show.

Write under `grill`'s literal headings — `**The Problem:**` (what is undecided),
`**Use Case:**` (one concrete case, named cast, showing why it bites),
`**Options:**` (laid out so the divergence is visible on sight), `**Recommendation:**`
(your answer, one line of why). The board is the surface with *room* for that
shape, which is why the questions moved here; a comment arriving as a paragraph
of prose spends the room and delivers the terminal's wall again.

Four rules for the body, in the order they matter:

- **Restate every reference at every mention** — `**TV1-1234** (*outbox
  redelivery drops the version watermark*)`, never a bare key. A comment is read
  cold, out of order, in a thread that may hold other tickets' questions, so an
  unresolvable address costs the reader the panel.
- **Diagram a problem of logic rather than describing it.** The panel renders
  fenced ` ```mermaid ` blocks inline: `flowchart TD` for a branch or a race,
  `sequenceDiagram` for a multi-party exchange. **One fence per comment** — a
  wall of diagrams is as unreadable as the prose it replaced. Prose is still
  right for a single fact or an answer with no shape.
- **Give each thing its own numbered section.** A comment naming a state, a
  recommendation and a constraint is three things; nest sub-points as bullets
  rather than splicing them into a sentence with em-dashes.
- **Bold the load-bearing claim inside a sentence, not a label at the start of
  one.** `**RECOMMEND:**` marks where to start reading and says nothing;
  bolding the claim means a bold-only skim still gets the idea.

The test: can a tired reader skim the headers and bolded phrases and get the
shape before reading a full sentence?
