---
description: (experimental, v2 of /design-multi) Fleet designer — resolve N tickets' designs in parallel (unattended), batch the genuine forks into one human pass, bake each resolved design into its ticket. Phase-A protocol lives in the `design-lane` agent.
---

# /design-multi-2 — parallel design across tickets

Take a **list of tickets** through the code-answerable half of `/design-2` in parallel, then compress the human half into a **single batched interview**. Each ticket ends carrying a **resolved design** that `/start-multi` consumes unattended — its design-heavy gate never trips, because the human moment already happened here.

You are the **orchestrator**: you dispatch read-only [`design-lane`](../agents/design-lane.md) agents, aggregate their open forks, run the one interview yourself, and write the resolved designs back. **You do not grill inside the agents.**

This is **not** "start-multi for design." `/build` is unattended because it has a mechanical gate; `/design`'s engine is `grill`, which has none. So this splits `/design` in two: what the **code** can settle runs parallel and unattended (Phase A); what needs **your intent** is batched into one sitting (Phase B); the result is written to the ticket (Phase C).

**This is the experimental v2 of `/design-multi`.** The Phase-A protocol moved into the `design-lane` agent — dispatched at the moment it applies rather than described here for you to relay. What is left is what only the orchestrator can do.

Run state lives in `.work/design-multi/<run-id>/run.yaml` — ephemeral, gitignored, resumable.

## Argument: $ARGUMENTS
Ticket ids (+ optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--max-parallel N` | Cap concurrent design agents. Read-only, so higher than start-multi is safe; still respect host limits. |
| `--run-id <id>` · `--fresh` | Resume-state controls. Default run-id: `design-multi-` + sorted ids. |

## Steps

**0 — Acquire & snapshot (the only tracker touch).** Resolve `run-id`; resume if `run.yaml` exists and not `--fresh`. Else fetch each ticket **once** into the run dir (agents read the snapshot, never the tracker). Pin `BASE=$(git rev-parse origin/<default>)` after `git fetch origin` — **the same base `/start-multi` will branch from**, so the design reflects the code it will be built on.

  **Grep each snapshot for `design-multi:resolved:v(\d+)` before dispatching anything.** This command writes that marker and is otherwise blind to its own past output — the one command guaranteed to meet its own work, and tickets linger in `To Do` long after their work merges. Where the marker is present, **short-circuit to a cheap verification pass**: re-check the block's *done-is-verifiable-by* and scope claims at the new base, and record `already_done` (recommend transitioning, drop the unit), `still_valid` (reuse, no re-design) or `stale` (run Phase A and **replace** the old block). **Never append a second block** — the marker is the section's identity. Report short-circuited units distinctly in step 5, so the human sees "already done" rather than silence. Unchecked, the cost is a wasted agent *plus* a corrupted ticket carrying two blocks, one describing finished work, that `/start-multi` then picks up unattended.

**1 — No worktrees.** Phase A is read-only; the isolation `/start-multi` needs is for parallel *writes*. All agents read the one working tree (recommend it clean and at/near `BASE`; note in a draft if it was grounded against uncommitted local work). Nothing to create, nothing to tear down. This is the simplification this command earns over `/start-multi`.

**2 — Dispatch `design-lane` agents**, up to `--max-parallel`, one per ticket, each grounded at `BASE`. The agent owns the protocol; you own three things it cannot:

  - **Single-writer rule** — only you write `run.yaml`. An agent that fails unrecoverably is `failed`; the others continue.
  - **Verify emission from disk before collecting a unit.** `stat` the `units/<id>.*` files. **A task-completion notification is evidence the agent stopped, never evidence it produced anything** — and `run.yaml` is written from your bookkeeping, not from disk, so nothing else would catch it.
  - **Label every handed-down fact** *applies; respect it* vs *verify whether it applies*. Passing possibly-irrelevant facts is right; the label is what stops them hardening into constraints.

**3 — Collect.** Aggregate per-unit state into `run.yaml`. Resume any `in_progress` unit from its next incomplete step; a unit already at `critiqued` with a draft on disk is skipped.

**4 — Phase B: the one batched interview.** Gather **every open fork across all tickets** into one numbered list, grouped by ticket, recommendation first, one line of why each. That list is the **map**; each fork is then *asked* in full.

  **Every fork is presented picture → scenarios → per-option walk** — `grill`'s *Presenting a fork*, under its literal headings (**The Problem** / **Use Case** / **Options** / **Recommendation**), bolding the load-bearing claim and **restating every ticket key, requirement number and coined label at every mention**. Do **not** use `AskUserQuestion`; the user answers free-form.

  This is load-bearing here rather than merely good manners, for three structural reasons: the user arrives **cold on N tickets** and holds context for none, so the picture is what re-grounds them per fork; the answers feed a block `/start-multi` executes **unattended**, so a fork answered against a mis-imagined subject has **no downstream gate** (the second pass verifies the block's claims, never that the question meant what the user thought); and the walks are what make the two collapses below visible at all.

  Four things only this sitting can do:

  - **Collapse dependent forks before presenting.** A draft can carry two recommendations that contradict each other — one led with *"partition, unless Fork 2 comes back 'UI appropriateness'"* and then recommended exactly that on Fork 2, so its stated lead was **B** while its own recommendations composed to **A**. Nothing is wrong per-fork; the inconsistency exists only across them, so neither the drafting agent nor the critique can see it. Present the **root** first; resolve the dependent one to a single recommendation or mark it *depends on #N*.
  - **Re-frame an answer that names an impossible combination.** When the answer needs two properties the code cannot provide together ("a rule, and idempotent" — a send inside a rule graph cannot be idempotent, because a transient failure re-runs the graph from node 0), say so with the evidence and map the intent onto the option that delivers it. Recording the literal words gets a *correct* answer to a *mis-framed* question, which is worse than no answer because it looks resolved.
  - **Re-verify — after the answers, never before — the one or two claims those answers made load-bearing.** Which claims are load-bearing *changes* when the human answers: one draft rejected a cross-repo signature change partly on its cost, the user said that cost was acceptable, and that instantly promoted a different claim (whether the seam could even see the caller) to load-bearing — verifying it reversed the recommendation. A verification pass placed before the sitting would have checked the wrong things.
  - **Cross-ticket coherence** — unify overlapping glossary terms, flag conflicting decisions, kill duplicated scope. Per-ticket `/design` cannot see the other tickets; this pass can.

  Where every scenario walks identically across the options it was never a fork: resolve it, record it as auto-resolved with rejected options, and take it off the list before the sitting.

  **Where a fork concerns the behaviour of this flow itself, the running session is a participant, not an observer.** In-session behaviour is evidence about the **loaded version**, never about the design question, and **an absence in the running session is never an argument against adding something** — one fork was argued from "you're answering in the terminal right now" while the session ran a stale build in which the alternative did not exist at all. State which version produced any observation cited as evidence.

  **On the canvas, where this repo has one.** Phase B is the longest numbered list in the flow and the worst thing in it to read as scrollback. Answer `/design-2`'s two gates **once for the run**, and on a double yes post the open forks as `comment`s anchored to the elements they concern — the numbered list stays as the *map*, one line per fork, while the picture, scenarios, walks and recommendation move into the comment. This is the one fleet command that can do it at all: Phase A cuts no worktrees, so you are still in the main checkout, the only place `.esas/` exists.

  - **`comment` and `resolve` are the only verbs**, however tempting it is to draw N resolved designs on one canvas. The design layer is scoped to one unit of work and Phase B holds N; the verbs would stay behind in the main checkout after the run is over, because `/start-multi` branches into worktrees that have no `.esas/`. A comment survives that: it asserts nothing about the architecture, and a question left open is legible residue where a proposal is a lie about the design.
  - **You post the batch; no agent writes to the design layer.** One writer, one write — arrays in, one `comment` call, the whole sitting appearing at once instead of trickling on in dispatch order.
  - **Hold the summon channel open across the sitting** — one `Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })`, opened once as you post. Phase B posts and then waits, which makes it the strongest case in the flow for the **Ask Claude** button having somebody on the other end; with the channel shut the press reaches nobody and the sitting ends in silence with the canvas full of open questions. N tickets' forks are answered in bursts and the user presses once per burst, and a persistent socket serves every press without re-arming. `esas-design-2` owns what the wake then runs.
  - **Prefix every comment with its ticket id *and* the ticket's title** — `TV1-123 (*sync drops the watermark*): …`. Comments are one flat chronological list per anchor with no ticket field, so where several tickets touch the same aggregate their questions land in one thread with nothing but the text to tell them apart. It is a text convention doing a field's work — the honest limit of this, not a feature.
  - **Resolve each comment as its fork is answered**, in the same pass, never in a sweep at the end. `resolved: false` is the shared to-decide list and what the badge counts, so a fork answered in the terminal and left open on the canvas sends the user back to re-answer a question you already have.
  - **Above roughly fifteen open forks, keep the whole list in the terminal.** The flat thread does not scale and this is the command most able to overrun it. Fifteen is a judgement, not a threshold — the real question is whether any single anchor's thread has stopped being readable. Fall back to the numbered list; do not invent structure the store does not have.

**5 — Phase C: finalize & write back.** **Confirm before writing to the tracker** — it is outward-facing.

  **First, re-run each unit's premise probes and re-resolve its `groundedShas`.** Cheap (the probes are written down in the draft) and necessary, because this command assumes tickets are static between Phase A and Phase C — which holds only while the human *answers*. When the human **acts** it fails: for a ticket blocked only on understanding, **the interview is itself a repair tool**, and one fix shipped mid-sitting, ~35 minutes in, collapsing its ticket from "build the watcher" to recurrence-prevention. The Phase-A draft would have instructed `/start-multi` to perform work that no longer existed. This is **not** detectable from the pinned base alone in the cross-repo case — that run's base never moved; the change was in the other repo, which only the per-unit `groundedShas` records. **Stamp the block with the sha it was actually written against.**

  Then, once confirmed, per ticket:

  - **Append a delimited, marked section to the description** — read-modify-append, preserving all existing content. **Never a REPLACE-based edit**, which silently destroys ticket bodies. The description is the single machine-readable channel; `/start-multi` reads it, not comments.

    ```
    <!-- design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id> -->
    ## Resolved Design (design-multi)
    `design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id>`
    { resolved decision tree with rejected options + evidence · seams/flow ·
      test seams · risks · unspecified seams · scope · file-overlap vs siblings }
    ```

    **`status` is required: `ready | deferred | blocked | umbrella`.** Non-ready units are the common case, not an edge one, and without the field an unattended `/start-multi` picks one up exactly as designed, burns a lane, and may open a bad PR.

    **Emit the marker twice** — the HTML comment *and* the visible inline-code line — and treat the greppable token as normative. The comment survives Jira Cloud's markdown → ADF → markdown round-trip (verified), but other trackers strip comment nodes, and if it is the only signal the block silently stops being machine-readable and `/start-multi` falls back to a fresh grill: the exact attended stop this contract prevents. (That round-trip also normalizes bullets and strips bold around inline code — verify read-back on **substance**, never bytes, and never let formatting carry meaning.)

    `:vN` is the **contract version** shared with `/start-multi`. Bump it only when the block's *shape* changes, so an older reader refuses to misparse a newer block instead of guessing.

  - **Write-back procedure, one sequential agent, never parallel:** get the description → **skip if the marker is already present** (idempotency guard for partial-run residue) → append after a `---` separator → read back and verify **both** the marker **and** a distinctive phrase from the original first paragraph survived. Any failure stops the run.

  - **Capture glossary/ADR deltas in the block by default; do not commit them here.** You are on the **default branch**, which the branch-first rule puts off limits; most deltas describe code that **has not landed**, so committing them states aspirational behaviour as fact; and non-ready units must not have theirs applied at all. Name the third state: **`delta: specified, deferred to build`** — the content is written into the block as a named obligation (which section, what it must say, what it waits for), discharged by `/build` or `/verify-build` on the branch, where `/verify-build` already owns "finalize ADRs". Some deltas cannot be written now at any price — one restating measured figures cannot exist until the measurement runs.
    - **Commit a delta directly only when it documents an already-shipped decision**, and even then on a proper branch. Committing here also invalidates step 0's pin by construction.
    - **Allocate ADR numbers at Phase C even when the files land later** — deferring re-opens the collision race, and the allocator belongs outside the lane. Where a delta is cited by two tickets, name the **owning unit** so it is applied once.

  - The draft stays ephemeral. Phase B's authoritative record is a single `decisions.md` in the run dir — cross-cutting policies first, then per-ticket resolutions — which the per-unit fold-back agents read instead of re-deriving from the conversation. Those run in parallel, write-scoped to their own unit, and each rewrites "Open forks" into "Resolved forks" (rejected options preserved), applies ripple edits, and emits `<id>.ticket-block.md` marker-line-first as the exact text to append.

**6 — Report & capture.** Per ticket → forks auto-resolved / forks you resolved → written to the description → deltas → the `BASE` grounded against. Then aggregate `<run>/units/*.learnings.md` plus your own Phase B/C friction and run **`/capture-learnings` once**, deduped across tickets.

  **If Phase B used the board, the handoff names the teardown.** This run's comments live in a layer scoped to one unit of work while the run spans N, so the moment the designs are written the layer is residue by construction and nothing downstream clears it — `/start-multi` works in worktrees with no `.esas/`, and the next `/design` here meets `design: present` and asks whose session it is. Say it out loud, and **never delete the files yourself**: they are gitignored, they are the only copy of this sitting's intent, and the user may still be reading the threads.

> Designs resolved and written to the tickets. Run `/start-multi <ids>` — it detects the resolved designs and runs `design` as a verification **second pass**, not a fresh grill, so the fleet stays unattended unless the code has drifted.
>
> This run's questions are still on the board, in a design layer that belongs to a single unit of work. When you are done reading them, delete `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor`.

## run.yaml (ephemeral, gitignored)
```yaml
runId: design-multi-...
groundedBaseSha: <pinned origin/default>          # start-multi verifies drift against this
flags: { maxParallel: 4 }
units:
  - { id: TV1-123, step: critiqued, status: in_progress,
      draft: units/TV1-123.design-draft.md,
      openForks: 2, ticketWritten: false }
    # step: pending | drafting | critiqued | resolved | written | done
```

## Principles
- **Split design at its natural seam.** Code-answerable → parallel and unattended; intent-dependent → one batched interview. Never fake the interview inside an agent.
- **Read-only, so no worktrees, no teardown.**
- **Ground against the base start-multi will branch from**, and record it for drift detection.
- **Tracker once, then never.**
- **A fork is asked as picture → scenarios → per-option walk, never as two labels.**
- **The batch is where cross-ticket coherence happens.**
- **The board carries Phase B's questions, never its answers** — and the layer they live in is named in the handoff, because a per-run command is borrowing a per-unit-of-work file.
- **No silent decisions** — auto-resolved and human-resolved alike ride into the ticket with rejected options and evidence.
- **Every inherited statement is a claim with a provenance and an expiry** — the ticket's, the brief's, the draft's, and your own recall. [EVIDENCE.md](../EVIDENCE.md) §3.
- **Confirm before writing to a ticket.**
- **Capture learnings once, at the end.**
