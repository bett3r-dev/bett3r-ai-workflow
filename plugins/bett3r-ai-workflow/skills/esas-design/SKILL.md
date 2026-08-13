---
name: esas-design
description: "For a live ESAS design-board session (.esas/ plus the esas-mcp tools). STANDING RULES wherever those tools exist: 'look at the board' — any phrasing — means read_changes, then reconcile, then mark_synced, in that order, never half of it, never unasked; with unread board edits, do not assert what the design says — sync first if they asked you to look, else say your picture may be behind and let them decide; a write refused with CONFLICT_PENDING_SYNC is cleared by ONE read_changes + mark_synced at the seq it named and the SAME batch retried whole; a summon frame on the ESAS session channel (/api/esas/ws, held open with Monitor) is the user pressing 'look now' — the answers are in the feed, not the wake — run that gesture whole; and an esas-mcp result carrying an esasSessionChannel notice with code SESSION_CHANNEL_CLOSED means reopen it unasked on the ws URL it names. Here: the summon's two invariants, the withdrawal/correction gestures, the restarts, the main-checkout-only rule."
---

# Designing on the board

`/design` sets this up — Step 0 for the gates, then
[BOARD-SETUP.md](BOARD-SETUP.md) beside this file for the registration, the
seeding and the launch. This is what to *do* once it is running: the user edits
a board on one screen, you write through `esas-mcp` from the terminal, and both
land in one attributed, durable design layer.

You are turn-based. You cannot see the board move. Everything below exists
because of that one fact.

## The sync point — "look at the board"

The user edits in bursts, then says so. Any phrasing counts: *look at the
board*, *I moved some things*, *check what I did*, *see the board*.

1. `read_changes` — defaults to the cursor and to semantic ops, which is what
   you want; sticky drags are excluded and should stay that way.
2. **Reconcile, and say what you make of it in the terminal.** Ops carry full
   payloads, so a burst is readable without re-reading the design.
3. `mark_synced(lastSeq)` — the `lastSeq` `read_changes` just reported, and
   only *after* you have responded. It is what clears the pending count.

Half a gesture is worse than none: reading without `mark_synced` leaves the
count stuck and the next write still refused; `mark_synced` without reading is
a lie about what you know.

**Never start this yourself.** The `esas: N pending` line is telemetry, not a
trigger — see the `esas-pending` skill for the standing rule. The count is
there so you know your picture is stale, and the one thing it changes is that
you stop asserting the design as fact until the user asks you to look.

So "sync first" never licenses syncing unasked: it means *do not assert* until
you have. With edits pending and no invitation to look, say your picture may be
behind and let the user decide. The one sync you make on your own initiative is
the one a refused write demands — and that one the store asked for, by name and
by seq. A summon is not a second exception: the button is the user asking,
through a channel that is not the prompt — see *The summon*, below.

### When a write comes back refused

`CONFLICT_PENDING_SYNC` means the batch touched an element the user has edited
since your cursor. The store refuses **the whole batch** and names the
conflicting ids and the `sinceSeq` to read from — nothing was written.

The answer is one `read_changes({ sinceSeq })`, reconcile, `mark_synced`, then
**retry the same batch unchanged** — one refusal, one sync, one retry, and
**never item by item**. Do not take the batch apart to find the bad entry: the
rejection already named it, and probing turns one refusal into a dozen writes
racing the user's next edit. Do not reword the proposal to dodge the conflict
either; the user's edit may be the answer to it.

## The map and the questions — what goes where

The board is not a second rendering of the interview. It is one half of a split:
**the terminal carries the map, the board carries the questions.** The terminal
*names* each fork in one line of the decision tree `grill` opens with; the board
*holds* the fork itself — its options, your recommendation, the thread it
collects — as a `comment` anchored to the element it concerns.

**Neither surface is a second copy of the other**, so there is nothing to keep in
sync between them and no policy to remember about where a question may be asked.
Get that wrong in the obvious direction — ask the fork in the terminal *and* post
it to the board — and the user answers in one place while you are watching the
other, or answers twice and reconciles the two themselves, or reads the canvas as
a stale echo of a conversation that has moved on and stops looking at it. A second
screen is only worth having while everything on it is still live.

**Batch the independent forks to the board; serialize the dependent ones in the
terminal.** A fork is independent when you could write it out in full right now,
because it turns on nothing you have yet to hear. Those go up in **one**
`comment` call — arrays in, one write, one op — each anchored to the node it is
about, and the user answers them in any order, all at once, or after lunch. That
is the entire payoff of a canvas: the grill is deliberately serial, and a serial
question posted to a board is just a slower terminal.

A dependent fork cannot go up at all, because its *wording* does not exist yet.
"Then where does the reservation number come from?" is not a question until the
previous answer says there is one. Posting it anyway means posting your guess at
what the user is about to say, on their canvas, under your name — and if they
answer the guess, you have resolved a fork nobody asked. Those stay in the
terminal, one at a time, exactly as `grill` runs them. It is the summon's second
invariant — *never propose from partial answers* — pointed at asking instead of
proposing: the same dependency edge, one step earlier.

The precedent is not hypothetical. `/design-multi`'s Phase B already gathers every
open fork across every ticket into one batched sitting, and it works; the board is
that sitting with anchors.

Anchoring is what makes a batched fork legible — see *Writing and reading* for
`comment`/`resolve` and why a node anchor beats a spine coupling that draws no
line. `resolved: false` is the shared to-decide list, so `resolve` each comment as
its fork is answered: the map in the terminal and the open threads on the canvas
are then two views of one state, which is the only sense in which they overlap.

## The summon — the board asking you to look *now*

You are turn-based, so a board answer normally costs a terminal turn to collect:
the user answers on the canvas, then types into the terminal to say they did.
That is the whole reason answering on the board is slower than typing. The
summon removes it. The user presses **Ask Claude**, the board POSTs to
`/api/esas/board/summon`, and the route broadcasts one frame —
`{"type":"summon","at":<epoch ms>}` — to every session holding the channel open.
It says *look now*, never *look at this*: what changed is already in the feed,
which is the one place both of you agree on, and the frame deliberately carries
nothing else.

What re-invokes you is a **frame arriving on a socket you are already holding
open**: the ESAS **session channel**, a WebSocket at `/api/esas/ws`. Open it
with `Monitor`, from anywhere, and let the turn end:

```
Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })
```

`persistent: true` is what makes this **session-scoped rather than turn- or
command-scoped**, and that is the whole point of the mechanism. The channel it
replaced was armed by `/design`, so it died at every session boundary — a
resume, a `/handon`, any other session doing something else in the repo — and
the only recovery was the user remembering to ask for it. One socket, held for
the life of the session, has no such boundary to fall through.

**No hook does this**, and reaching for one is the first wrong turn.
`FileChanged` fires but has *no decision control* — side effects only, it cannot
inject context. `Stop` can force a continuation, but it fires the instant you
finish posting the questions, which is before anything has been answered. Both
are ruled out at the mechanism level, not merely unused. (This plugin's
`SessionStart` hook may *tell* you to open the channel when a board is up and
nobody is holding it; that is a nudge to run the `Monitor` call above, not a
second wake mechanism, and the wake still only ever arrives on the socket.)

The user answers where the questions already are: `?openComments=1&author=ai`
opens the board on the open threads instead of the whole canvas.

**Two invariants.** There used to be six, and four of them were consequences of
a wake that was *edge-triggered once* — a file to delete, an exit to re-arm
after, a deadline to bound, an exit reason to echo. A held socket is
level-triggered and has none of those, so those four are gone rather than
reimplemented. What survives are the two rules that were never about the
transport at all — they are about the **design**:

1. **Tolerate an empty wake.** A press means the user pressed, not that
   `read_changes` will have something for you: they may have pressed twice, or
   pressed after an edit you already synced. "Nothing new since the cursor" is a
   normal outcome, not an error — say so in one line and go back to waiting,
   rather than hunting for the change that must surely be there. This is
   strictly weaker than it used to be, in the good direction: a press with
   nobody connected reaches nobody and **leaves nothing behind**, so there is no
   longer any state on disk for a later session to misread as a wake.
2. **Never propose from partial answers** — only for forks whose dependencies
   are all resolved. A press means *I answered something*, never *I answered
   everything*; three answers plus a guess at the fourth is a design the user
   never agreed to, on their canvas, under your name.

### Reopen a closed channel the moment you are told it is closed

`Monitor`'s watch **ends when the socket closes**, and it has no auto-reconnect.
So a board restart — a config edit, a crash, a closed laptop — leaves you
**deaf**, with nothing on either side saying so, and the next press reaches
nobody.

The recovery is automatic and it is yours to run. While the channel is shut,
**every `esas-mcp` tool result carries an extra text content block** holding:

```json
{ "esasSessionChannel": {
    "code": "SESSION_CHANNEL_CLOSED",
    "message": "…",
    "ws": "ws://127.0.0.1:3727/api/esas/ws" } }
```

When you see it, **reopen the channel then and there, without being asked** —
`Monitor` on that `ws` URL, `persistent: true`, and let the turn end. Say it in
one line; do not make it a question. Three consumer rules, each a real failure
if it drifts:

- **Branch on `code`, never on `message`.** That is the standing convention for
  every ESAS tool result, and the message is prose that will be reworded.
- **Dial the `ws` field, do not reconstruct it.** The board can be moved
  (`esas-board --port`, `ESAS_BOARD_PORT`), and a consumer that rebuilt the URL
  from a remembered `3727` would reopen a channel to nothing while reporting
  success.
- **A missing notice means *nothing to do*.** It is emitted *only* while the
  channel is provably shut. An unreachable board, a board serving a different
  checkout, and a channel somebody is already holding open are **all silent**,
  so its absence must never be read as "the channel is fine" and acted on.

**A summon is the user asking**, so the standing rule against syncing unasked
does not reach it — `esas-pending` carries the matching carve-out, and it is
exactly that narrow: the press is an ask, the `esas: N pending` count still is
not. What the wake then runs is the ordinary gesture, whole: `read_changes`,
reconcile, `mark_synced`.

Expect a second refusal, and a louder one. **The wake arrives wrapped in a
platform banner that declares itself not user input**, and not a response to any
pending question — and it was *measured* that a frame on this socket arrives
inside the identical banner the sentinel wake did, so nothing about this problem
was bought or lost by changing the transport. Every word of that banner is
accurate, and none of it is about what the read returns:
**the notification is not the answer.** It is the doorbell, not the sentence.
What the user actually said is in the feed — the authored comments
`read_changes` returns — and the banner makes no claim about those, because the
summon carries no payload by design: it says *look now*, never *look at this*.
So the banner is true and you sync anyway. Taken for a refusal, it ends the
board session silently while the user watches a canvas that answered nothing —
the same silent ending a deaf channel produces, arriving through a different
door.

### The cross-repo contracts

Every string below is spelled in esas@master and pinned on that side too, and
**nothing links the two repos at build time** — so a paraphrase here breaks the
gesture with both suites green on both sides. Copy them; never reword them.

- **`/api/esas/ws`** — the session channel, `SESSION_CHANNEL_ROUTE` in the
  board's `vite-plugin-esas-fs/session-channel.ts`.
- **`POST /api/esas/board/summon`** — the press route. The human gesture that
  broadcasts the frame; unchanged across the transport change.
- **`?openComments=1&author=ai`** — the handoff link that opens the board on the
  open threads instead of on the whole canvas.
- **`code` and `ws`** — the two keys of the `esasSessionChannel` notice, with
  `SESSION_CHANNEL_CLOSED` as the one code, from esas-mcp's
  `session-channel-notice.ts`.
- **`3727`** — the port, claimed strictly; `/design` carries it too.

The port, the status route (`/api/esas/status`) and the channel route now have
**one definition** on that side, in `esas-store/src/board-endpoints.ts`, which
both the board and `esas-mcp` import rather than re-typing.

## "Scrap that, I was wrong" — remove

Changing your mind about your **own** proposal is `remove`. Nothing else, and
nothing extra. The tool decides what the deletion means from what the target
*is*, so you never have to pick:

- the element is **in reality** — it is a design statement about code that
  exists. It stays on the board desaturated, and no propose-edge may touch it;
- the element is **only proposed by this design** — the proposal is
  **withdrawn**: its entry leaves `design.json`, taking every proposed edge on
  it, every `modify` standing on it, and the comments anchored to those.

So a proposal you re-anchored, split, or simply got wrong just goes. Do not
rename it `"(RETRACTED — use X)"`, do not leave a note on it explaining that it
is not real, and do not park it somewhere out of the way. Every one of those
leaves a sticky on the user's canvas asserting an element that does not exist,
and the board has no way to show that a label is a disclaimer. If a removal ever
comes back refused, **say so and stop** — never route around it (see *A refusal
is the same rule*, under **Writing and reading**).

Two consequences to weigh before you withdraw, not after:

- **The thread goes with it.** Comments anchored to a withdrawn proposal are
  deleted, because the element survives in no layer and a comment on nothing is
  never drawn again. If the conversation reached a conclusion worth keeping, say
  it in the terminal — or re-anchor it to the element that replaced it — before
  the withdrawal, not after.
- **It is not undo-able from the board.** A withdrawal is an op like any other
  and a rebuild re-applies it. Recovering a withdrawn proposal means proposing
  it again.

`remove` is also not `reclassify`, and the two are easy to confuse because both
end with an entry leaving `design.json`. The difference is one sentence:
withdrawing says *this was never right*, reclassifying says *this is already
true*. Guess wrong toward reclassify and you write a phantom element into a
git-tracked file that ships with the PR.

## "That rename is a correction" — reclassify

Sometimes a board edit is not design intent at all: the extractor got a label
wrong, or a coupling already exists in code that ESAS cannot see. The user says
so — *that rename is a correction*, *that's a fact, not a proposal*, *that's
already true*. Then `reclassify` the entry: it moves the same payload out of
`design.json` and into `.esas.overrides.json`, keeping its author and note.

Three things to say out loud when you do it:

- **It dirties the working tree.** `.esas.overrides.json` is git-tracked (the
  design layer is not), so the correction ships with the PR. That is the point:
  a fact about reality belongs in the repo, not in a file that dies at merge.
- **The diff may look bigger than the change.** The store rewrites the file
  through a JSON round-trip, so whitespace and key order are normalised. A
  large-looking diff on a hand-formatted overrides file is usually formatting;
  read it before assuming the tool did more than you asked.
- **A refusal is information.** `RECLASSIFY_WOULD_BE_STALE` means the move
  could not land — an entry keyed by an id the extracted graph does not have,
  or an edge whose endpoint is still a proposal. The error names the
  alternative. The correction is not lost; it is still in the design layer,
  where it at least applies.

Reclassify only what the user called a correction. A proposal you happen to
believe is already implemented is a question for them, not a move to make.

## The two restarts

- **Pulled esas mid-session?** Then restart the session **and** the board. The
  MCP server is spawned once at session start and the board reads its sources
  at boot, so after a `git pull` in the esas checkout both are running the old
  code — and the ops feed will start showing writer-version skew, which is the
  warning surfacing exactly this. Same for a rebuilt board with an unrestarted
  server: one screen is ahead of the other.
- **Registered `esas-mcp` this session?** The tools do not exist until the next
  one. `/design` makes that its own step; the rule here is the negative one —
  do not work around a missing server by hand-writing `.esas/design.json`.

## The fleet rule — main checkout only

Board collaboration happens in the **main checkout**, never in a worktree. A
fleet worktree has no `.esas/`, so every tool answers `ESAS_DIR_MISSING`, and
that is the correct answer, not a setup problem to fix: creating a `.esas/`
there would enrol a throwaway tree in a design session and split the layer in
two. In a worktree, design in `.work/design.md` and leave the board alone.

One design session per checkout, likewise. If `status` warns that another
session is designing here, say so — two sessions sharing one cursor lose each
other's syncs quietly.

## Writing and reading

**Batch.** Arrays in, one write, one op out. Ten proposals in one `propose` is
one entry in the feed the user reads; ten calls is ten, and ten chances to
collide with an edit they are making right now.

**Read the ids before you reference them — never guess a derived id.** No verb
lists node ids: `status` and `get_design` do not, and `get_flow` *requires* a
root command id you must already have. The entry point for "what is this called
on the board" is grepping `.esas/graph.json` directly. Ids read
`<subdomain>_<abbrev>_<kebab-label>` (`cmd`, `evt`, `rm`, `agg`, `pol`, `sys`,
`ext`, `ui`), and two things break the obvious guess:

- **Extracted `ext` ids carry an extra `external-system-` segment that a
  *proposed* node will not reproduce.** The segment comes from the extractor's
  artifact naming, not from `(subdomain, type, label)` — so reading the graph to
  learn the convention and then writing an edge to
  `…_ext_external-system-mercadolibre-messaging-api` fails
  `UNRESOLVED_EDGE_ENDPOINT`, because the node actually landed as
  `…_ext_mercadolibre-messaging-api`.
- **Label casing is load-bearing for the derived id.** `"MercadoLibre Messaging
  API"` does *not* kebab to `mercadolibre-messaging-api` (the caser splits
  internal capitals and all-caps acronyms); `"Mercalibre Messaging Api"` does.
  Same intended artifact, two ids, no warning — and because it is a
  correctly-spelled label rather than a typo, it survives review. Prefer plain
  Title Case wherever the derived id will be referenced.

So where a batch introduces a node that later edges must point at and the id is
not certain, **propose the nodes first, read the returned `nodeIds`, then send
the edges in a second call.** That is a deliberate, documented exception to
*batch everything*: `propose` validates before disk and rejects the **whole**
batch, so guessing turns one call into guess-the-whole-batch-correctly, and the
skill's own rule against taking a batch apart to find the bad entry makes each
miss a full round-trip. One extra op removes the guess.

**`reads-from` is only legal from a policy, read-model or aggregate.** A
`system -[reads-from]-> read-model` triple is rejected, so an external system
that genuinely queries a readmodel expresses that dependency on the **policy
that drives it**. That is a modelling constraint a designer needs up front, not
on rejection.

**Read flow-sized.** `get_flow(rootCommand, scope?)` walks one command's ripple
over the merged graph — extracted plus overrides plus design — so proposed and
removed elements are in the answer and it stays the same walk the board draws.
`scope.boundary` defaults to `'end-to-end'`; `'subdomain'` keeps the flow's
cross-subdomain hand-offs visible as leaves instead of pretending the ripple
stops at the boundary — and it is **not** a token-reduction lever: it still
lists foreign nodes with their full `queries` arrays, so it is "smaller graph,
similar payload." `get_design` returns the verb delta — intent, not a copy
of the graph. Neither of them is "read the whole graph", which is the thing to
keep not doing.

The tools that exist today are `propose`, `modify`, `remove`, `reclassify`,
`comment`, `resolve`, `get_flow`, `get_design`, `read_changes`, `mark_synced`
and `status`. If a gesture seems to need something not on that list, say so
instead of improvising a file edit around it.

**A refusal is the same rule.** A verb that comes back refused and stays refused
is a fact about the board worth one sentence in the terminal, and
never a reason to reach for a *different* verb that lands.
Writing the intent into a label, a note
or a comment because the verb for it would not go through does not record the
intent; it records a contradiction, on the user's canvas, in the one field they
read as the truth. Say what you tried, quote what it said, and let them decide.

`comment` and `resolve` are the grill on canvas: an open question lands on the
sticky it concerns, and `resolved: false` is the shared to-decide list. Prefer a
node anchor — the spine couplings (`handled-by`, `produces`, `issues`) usually
draw no line, so a comment anchored there has nowhere to show.

**When a comment explains a problem of logic — a sequence of steps, a branch, a
race, an ordering — favor a diagram over prose.** The comment panel renders
fenced ` ```mermaid ` blocks as flowcharts and sequence diagrams inline, not as
a code block. A branch or a race is what `flowchart TD` is for; a multi-party
exchange (who calls what, in what order, waiting on what) is what
`sequenceDiagram` is for. Reach for one whenever the shape of the problem is the
thing under discussion — a paragraph describing "A happens, then either B or C,
then D" is strictly harder to read than the same shape drawn — but prose is
still right for a single fact, a yes/no answer, or a recommendation with no
shape to it. One fence per comment: a wall of stacked diagrams is as unreadable
as the wall of prose it replaced.

**When prose is still right, break it up — a single dense paragraph is not the
default.** A comment that names a state, a recommendation, and a constraint is
three things, not one: give each its own numbered section (`1. The Problem`,
`2. The Recommendation`, `3. The Constraint` — name them for what's actually
in this comment, not literally these words) with its own short paragraphs or
bullets underneath, rather than running everything together with em-dashes
into one block. Nest sub-points as bullets under the sentence they belong to
instead of splicing them into it — three parenthetical states read easier as
three list items than as one sentence carrying all three.

**Bold the load-bearing words inside each sentence, not whole labels at the
start of one.** A bolded lead-in (`**RECOMMEND:**`) marks where to start
reading but says nothing on its own; bolding the actual claim inside the
sentence (*tolerate absence only where it cannot escalate the document
class*) means a reader skimming bold-only still gets the idea, and reading the
unbolded rest is opt-in elaboration, not the only place the point lives. Apply
this within a section's own prose, not as a substitute for the section break
above — the two techniques stack: numbered/bulleted structure for shape, bold
for the one sentence in each part that carries it.

The test is whether a tired reader can skim the section headers and bolded
phrases alone and get the shape of the comment before reading a full sentence;
if the whole thing has to be read start to finish to find the recommendation,
it is one paragraph pretending to be several.
