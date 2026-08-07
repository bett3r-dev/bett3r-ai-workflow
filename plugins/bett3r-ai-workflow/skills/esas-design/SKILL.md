---
name: esas-design
description: "Gestures for a live ESAS design-board session (a repo with .esas/ plus the esas-mcp tools). STANDING RULES wherever those tools exist: 'look at the board' — any phrasing — means read_changes, then reconcile, then mark_synced, in that order and never half of it, and never unasked; while the user has unread board edits, do not assert what the design says — sync first if they asked you to look, otherwise say your picture may be behind and let them decide; a write refused with CONFLICT_PENDING_SYNC is cleared by ONE read_changes + mark_synced at the seq it named and the SAME batch retried whole. Read this file for the withdrawal and correction gestures, the two restarts, and why the board is main-checkout-only."
---

# Designing on the board

`/design` sets this up (Step 0). This is what to *do* once it is running: the
user edits a board on one screen, you write through `esas-mcp` from the
terminal, and both land in one attributed, durable design layer.

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
by seq.

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

**Read flow-sized.** `get_flow(rootCommand, scope?)` walks one command's ripple
over the merged graph — extracted plus overrides plus design — so proposed and
removed elements are in the answer and it stays the same walk the board draws.
`scope.boundary` defaults to `'end-to-end'`; `'subdomain'` keeps the flow's
cross-subdomain hand-offs visible as leaves instead of pretending the ripple
stops at the boundary. `get_design` returns the verb delta — intent, not a copy
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
