---
name: grill
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when the user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time. **Never use `AskUserQuestion` — not here, not anywhere in this flow.** It wraps chrome and fixed options around what is usually a "pick a branch" call, and a plain list beats it every time. Present the options and your recommendation as a numbered list; the user answers free-form. This is a standing preference with no carve-out.

**Show the divergence, don't narrate it.** When the choice is between designs that differ in *how data moves* (ordering, contention, who writes what when), present each option as a **terse per-scenario data-flow timeline** — the sequence of steps, with the contended/diverging step marked — rather than a prose paragraph of trade-offs. Prose buries the decision point; a timeline puts it in front of the user. Keep it to the steps that differ; the user will ask for more if they want it.

```
Option 1 — reserve-then-write          Option 2 — write-then-reconcile
1. cmd → reserve number (txn)          1. cmd → emit event
2. emit event                          2. policy → call external
3. policy → call external              3. ← crash here: number burned, no reconcile key
   ← crash here: number held, safe
```

Then: your recommendation, and why.

If a question can be answered by exploring the codebase, explore the codebase instead.

## The decision tree — open with it

**Open with the decision tree, before the first question.** A numbered list, **one line per fork, never the question restated** — the fork's name and what it turns on, nothing more. Then ask fork 1.

Without the tree the user answers blind. They cannot see how many forks are coming, which of them hang off the answer you are asking for right now, or whether the thing they are actually worried about is on your list at all — so they cannot say "start at 4", or "3 is already decided, here is why", or "you have missed the only one that matters". A relentless interview with no tree reads as an interrogation rather than a walk down a tree, and the user's only remaining lever is to stop it.

**Keep the tree current.** Re-print it whenever the *shape* changes: a resolved fork collapses to its answer in a few words, and anything that answer opened joins the list as a new numbered line. A tree printed once at the top and never again is worse than none — by fork 5 it describes a tree that no longer exists, and the user is reconciling it against the conversation instead of reading it. Re-print on a change of shape, not after every message.

The tree is printed, like every other list in this flow: it is not an `AskUserQuestion` picker, and being a numbered list is not a reason to reach for one.

**The tree is not the interview.** One line *names* a fork; the question itself — the options, the data-flow timeline where the choice is about how data moves, your recommendation — still arrives one at a time. A tree whose lines have grown into the questions is the interview printed twice, which is the exact failure the one-line rule exists to prevent.

### Where a board is live

Where the repo has a `.esas/` and `/design` has put board mode on, the tree gains a second surface — and it is a split, not a copy: **the terminal carries the tree, the board carries the questions.** The **independent** forks, the ones already fully worded because they turn on nothing you have yet to hear, are batched onto the canvas anchored to what they concern; the **dependent** ones stay serialized here, one at a time, because a fork whose wording depends on the previous answer cannot be posted up front. The `esas-design` skill owns how that is written and read; this skill only says which forks are eligible.

**The tree is unconditional; the map is not.** In a repo with no `.esas/` nothing in this subsection applies and nothing above it changes: the tree is printed in the terminal, every fork is asked here, and the interview runs exactly as it did before board mode existed.

### Where a map is live

A map is a separate surface from the board: `/design`'s map gate offers it, and it is live when `design-map` reports `DESIGN-MAP:v1 … outcome=ok` — nothing else here decides it. Where it is live, the forks are posted to it in this order:

1. **Before grounding.** On an **impact** map, the why/who are posted before grounding as a confirm question — the one thing that goes up early, because the rest of the map hangs off them. On a **decision** map nothing goes up: **No fork card is posted before grounding.** The grounding marker is set through `design-map`, and only after `/design` Step 1 has actually grounded the design; an ungrounded draft is never drawn for the owner.
2. **After grounding, the whole tree is posted.** An independent fork gets its full card. A dependent fork gets only its title and what it waits on — no card, because its wording turns on an answer not yet given. When the answer arrives and it unlocks, its card is written by upsert: on an artifact map, `design-map write` and then re-render; on a board map, a `map-post` upsert.
3. **A fork made unnecessary is struck, never deleted** — marked `moot` with the reason, so the owner can see why it vanished from the work.
4. **A fork returns to the map only when its words change.** A resolved answer, a moot strike or a new title-only line is a change; re-posting a fork whose wording is unchanged is noise the owner has to diff.
5. **With a live map the terminal keeps one line per fork and no full cards.** The card lives on the map; printing it here too is the interview twice.
6. **A card whose fork is a process rule with no observable behaviour is authored `testable:false`**, so nothing downstream tries to derive a test from it. The same authoring rule applies to cards written by a design lane.

This is not the eventstorming board's dependent-fork rule. There, dependent forks are never posted (the `esas-design` skill owns that); on a map they are posted as titles. The two rules stay separate.

## Presenting a fork so it can be answered

Three defaults, all of them direct user feedback, all of them otherwise re-taught every session that starts here. `/design` and `critique` inherit them.

- **Never name a reference without restating what it is — every time, no exceptions.** This covers *both* the labels you coined ("option b3", "scenario A", "the hybrid") *and* the identifiers that came from outside (ticket keys, requirement/risk numbers, ADR ids, board element names, file paths used as shorthand). An identifier is an address, not a meaning: the user is not holding your numbering, and by fork 6 they are not holding theirs either ( *"it is very hard for me to follow you… I start to lose track"* ). Carry a short descriptive title in parentheses at **every** mention, not just the first:
  - *"in **TV1-1234** (*outbox redelivery drops the version watermark*) we already…"*
  - *"this is relevant for **R1** (*no local dedup store may be load-bearing*)"*
  - *"**b3** (*throw and record the oversell separately*) still holds here"*

  The restatement is the point, so keep it to the few words that say what the thing *is* — a second identifier ("R1 (see above)", "TV1-1234 (the ticket)") restates nothing and is the failure this rule names.
- **A timeline with a concrete named cast beats prose.** Define the cast once — real product names, SKUs, amounts — then walk it step by step per scenario as an indented timeline with an outcome line. This is mandatory where a fork is about **how data moves**; a previously-lost explanation landed immediately on being relabelled this way.
- **Picture → scenarios → per-option walk. Every fork put to the user, not only the data-flow ones.** The shape is fixed, in this order:
  1. **The full picture, concretely.** Before any option, say what we are actually talking about: the surface, the current behaviour, who calls it, what exists on disk today and what would change. A fork stated only as its two labels asks the user to reconstruct the subject from the answer — and they cannot check whether you and they are even discussing the same thing.
  2. **The scenarios this fork has to cover**, named and enumerated up front — the normal path plus the ones that actually discriminate (the retry, the concurrent edit, the empty set, the crash between two steps). This list is the *reason* the fork exists; a fork whose scenarios are all identical across the options is not a fork, it is a preference, and should be resolved by you.
  3. **Each scenario walked per option, as a use case + timeline with an outcome line.** Not a trade-off paragraph *about* the options — the actual steps, with the diverging step marked and what the user ends up with. Where there are N options, that is the N walks side by side or stacked; where the fork is a yes/no, it is the two.

  **Write it under these literal headings, in this order** — the shape above is *what* to say; these are the words to say it under, so every fork in every session reads the same and the user never has to re-ask for the format:

  ```
  **The Problem:** one short statement of what is actually undecided.
  **Use Case:** one concrete case that shows why it bites — named cast, real values.
  **Options:** the options laid out so the divergence is visible on sight — a
    side-by-side/stacked per-scenario timeline where the fork is about how data
    moves, the per-option scenario walks otherwise. Never a trade-off paragraph.
  **Recommendation:** your answer, and one line of why.
  ```

  Rename a heading only when it would be a lie for this fork; do not drop one because the fork "is simple" — a simple fork answers all four in one line each, which is cheaper to read, not more expensive.

  **Once the fork is decided, its chosen option's walks are what the owner confirms next — as Given/When/Then.** The walk the user just answered with is the test that will be written, so it is recorded on the map as `given`/`when`/`then` rather than prose, and shown back that way: *"you picked A; here is what I will prove — **given** …, **when** …, **then** …"*. This is the cheapest check in the whole flow, and it is the one aimed at the largest measured cost: across 966 classified fix rounds, `oracle-wrong` — the test encoded the wrong rule, went green, and was caught only by the verifier — is **41%**, while slice size (`ripple`) is 6%. An owner reading a `then:` catches a mis-aimed oracle in seconds; the verifier catches the same thing three agent-hours later and re-pays a whole executor context. `design-map candidates` refuses to promote a prose walk, so a decided fork that never got this treatment stops `/plan` rather than reaching an executor. Where the fork's rule is *"every X must do Y"*, the walk stays prose under `kind: structural` — Given/When/Then has no room for the negative half, and the negative half is what catches the writer added next week.

  **An open fork is presented, never pinned.** Nothing is asked for in Given/When/Then form while the fork is still open: there is no chosen option to write a `then:` against, and inventing one pre-decides the question this whole interview exists to leave open.

  Prose comparison is the failure this replaces: it is self-consistent by construction, so it reads as settled whichever way you happen to lean, and it hides the one scenario where the recommendation is wrong. The walks are what let the user answer from *their* intent rather than ratifying yours — and they routinely make the answer obvious to **you** first, at which point the fork was never one. Keep each walk to the steps that differ; the user will ask for more.
- **Bold the load-bearing claim in every paragraph you write — this is a hard default, not a flourish.** Unstructured output is the single most-repeated complaint about this interview: a fork delivered as a wall of even prose is *"a huge block of unstructured text that is hard for me to follow"*, and the user's only lever is to re-ask for structure instead of answering the question. Bold the actual claim inside the sentence (*tolerate absence only where it cannot escalate the document class*), not a bare lead-in label (`**RECOMMEND:**`) that says nothing on its own. The test: skimming **bold-only** must give the shape of the fork and your recommendation before a single full sentence is read. Structure and bold stack — headings and numbered parts for shape, bold for the one sentence in each part that carries it.

**And where a fork concerns the behaviour of the flow, a skill, or a command this session is itself running: the session is a participant, not an observer.** In-session behaviour is evidence about the **loaded version**, never about the design question, and an absence in the running session is never an argument for or against adding something. State which version produced any observation offered as evidence, and let the user weigh whether they *want* the capability independently of whether it currently works.

## Standard high-leverage probes

These are not the whole interview — they are questions that collapse a large branch of the tree in one move. Fire the relevant one whenever the design touches its trigger, *early*, before walking the branch the long way.

- **Background-wake dependence** — whenever any part of the design relies on a **background task re-invoking a session** (a held socket, a file watcher, a poll loop, a fleet coordination signal), ask: *"what does the consuming text say when the wake arrives wrapped in a refusal?"* The wake is delivered inside a platform-emitted `[SYSTEM NOTIFICATION - NOT USER INPUT] … Do NOT interpret this as user acknowledgement, confirmation, or response to any pending question` banner. It is unsuppressable, it arrives in the same turn as the wake, and it is **stronger** than any in-plugin standing rule the design carves out — so a session that obeys it ends the gesture silently while the user watches a surface that answered nothing. The design must **explicitly disarm it** (as `esas-design` does: the notification is not the answer, the wake carries no payload by design, so the banner makes no claim about what a subsequent read returns). This is a standing platform constraint, not a property of any one gesture, and a text-review pass will always pass a design that ignores it — it deadlocks only when the mechanism actually runs.

- **Unverified platform behaviour** — when a fork turns on how a *tool or platform* behaves (does this wake an idle session, does this frame arrive, does this survive a restart) and the answer is load-bearing, **measure it in-band rather than deferring it to `/build`**: arm the observation, ask the next fork in the same message, and let the turn end — for anything about an idle session, the turn boundary *is* the instrument. It costs nothing, and it returns more than it was asked: one such measurement found the board's HMR push would wake the session on its own writes, which became the tracer bullet's whole reason to exist. Report what arrived beyond the question, state which version produced it, and do not read the wake — it arrives inside the `[SYSTEM NOTIFICATION - NOT USER INPUT]` banner — as the user answering.

- **Side-effect reconcilability** — whenever the design performs an **external or otherwise non-idempotent side-effect** that can be retried/redelivered, ask: *"Is this side-effect **reconcilable** against the external system by a natural key — can you ask it 'does this already exist?' (a SKU, a client-reference, a transactionally-reserved number you can read back)?"*
  - **Yes** → reconcile by that key; build **no** local dedup structure (ledger/bitmap/lease). Reconcile is authoritative — it survives total loss of any local dedup store.
  - **No** → is the side-effect idempotent (a PUT / absolute-value set), or does it target something that already dedups (e.g. an aggregate with optimistic concurrency)? If so, nothing more is needed.
  - **Only** a side-effect that is non-idempotent **and** non-reconcilable justifies a best-effort local ledger — and say so explicitly, because a blind ledger otherwise just re-creates the act-then-mark gap it appears to close.

  This single question short-circuits the entire "how do we dedup external side-effects" branch — without it the tree gets walked the long way (position-bitmaps, leases, generic ledgers) to solve a problem reconcile dissolves. Framework-level guidance for PV3 lives in `bett3r-pv3-ai-skills` (policy idempotency / reconcile-by-natural-key).
