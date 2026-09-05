---
description: Fleet designer — resolve N tickets' designs in parallel (unattended), batch the genuine forks into one human pass, bake each resolved design into its ticket. Phase-A protocol lives in the `design-lane` agent.
---

# /design-multi — parallel design across tickets

Take a **list of tickets** through the code-answerable half of `/design` in parallel, then compress the human half into a **single batched interview**. Each ticket ends carrying a **resolved design** that `/start-multi` consumes unattended — its design-heavy gate never trips, because the human moment already happened here.

You are the **orchestrator**: you dispatch read-only [`design-lane`](../agents/design-lane.md) agents, aggregate their open forks, run the one interview yourself, and write the resolved designs back. **You do not grill inside the agents.**

This is **not** "start-multi for design." `/build` is unattended because it has a mechanical gate; `/design`'s engine is `grill`, which has none. So this splits `/design` in two: what the **code** can settle runs parallel and unattended (Phase A); what needs **your intent** is batched into one sitting (Phase B); the result is written to the ticket (Phase C).

The Phase-A protocol lives in the `design-lane` agent — dispatched at the moment it applies rather than described here for you to relay. What is left is what only the orchestrator can do.

Run state lives in `.work/design-multi/<run-id>/run.yaml` — ephemeral, gitignored, resumable.

## Argument: $ARGUMENTS
Ticket ids (+ optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--max-parallel N` | Cap concurrent design agents. Read-only, so higher than start-multi is safe; still respect host limits. |
| `--run-id <id>` · `--fresh` | Resume-state controls. Default run-id: `design-multi-` + sorted ids. |

## Steps

**0 — Acquire & snapshot (the only tracker touch).** Resolve `run-id`; resume if `run.yaml` exists and not `--fresh`. Else fetch each ticket **once** into the run dir (agents read the snapshot, never the tracker). Pin `BASE=$(git rev-parse origin/<default>)` after `git fetch origin` — **the same base `/start-multi` will branch from**, so the design reflects the code it will be built on.

  **Grep each snapshot for `design-multi:resolved:v(\d+)` before dispatching anything, and read its `run=`.** This command writes that marker and is otherwise blind to its own past output, and tickets linger in `To Do` long after their work merges. Marker with **this run's** `run=` → short-circuit to a cheap verification pass: re-check the block's *done-is-verifiable-by* and scope claims at the new base, and record `already_done` (recommend transitioning, drop the unit), `still_valid` (reuse) or `stale` (run Phase A and **replace** the old block — never append a second; the marker is the section's identity). Marker with a **different** `run=` → a concurrent or earlier sibling run owns this ticket: **stop and ask** — reuse it, redesign and replace, or drop the unit — never run a Phase A whose result Phase C cannot write. Two overlapping runs once wrote `status=ready` blocks giving opposite release-sequencing instructions for the same sibling repo, and only a write-back agent's aside surfaced it. Report short-circuited units distinctly in step 6.

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

  **On the canvas, where this repo has one.** Phase B is the longest numbered list in the flow and the worst thing in it to read as scrollback. Answer `/design`'s two gates **once for the run**, and on a double yes post the open forks as `comment`s anchored to the elements they concern — the numbered list stays as the *map*, one line per fork, while the picture, scenarios, walks and recommendation move into the comment. This is the one fleet command that can do it at all: Phase A cuts no worktrees, so you are still in the main checkout, the only place `.esas/` exists.

  - **`comment` and `resolve` are the only verbs.** The design layer is scoped to one unit of work and Phase B holds N; a proposal drawn here would be a lie about the design left behind in the main checkout, while an open question is legible residue.
  - **You post the batch; no agent writes to the design layer.** One writer, one `comment` call with arrays in, the whole sitting at once.
  - **Hold the summon channel open across the sitting** — one `Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })`, opened as you post; with it shut the **Ask Claude** press reaches nobody. `esas-design` owns what the wake runs.
  - **Prefix every comment with its ticket id *and* title** — `TV1-123 (*sync drops the watermark*): …` — because comments are one flat list per anchor with no ticket field.
  - **Resolve each comment as its fork is answered**, never in a sweep at the end: `resolved: false` is the shared to-decide list, and a fork answered in the terminal but open on the canvas gets re-answered.
  - **Above roughly fifteen open forks, keep the whole list in the terminal** — the real test is whether any one anchor's thread is still readable.
  - **Five board mechanics that silently produce wrong user-visible state:** the board is seq-driven and `comment` has **no edit verb** — an in-place edit to `design.json` is invisible until the user reloads (post a reply instead, or say "reload"); **every write to `design.json` restarts the board server and drops the summon socket with a `1006`** — expected, re-arm, do not diagnose; the legal edge triples are **not guessable from the verb's English** (`ui -[subscribes-to]-> read-model`, `event -[triggers]-> policy`) — read them out of `graph.json` before proposing edges; **`remove` on a proposed node deletes the comments anchored to it** — post an unanchored design-level record of the reasoning first; and an audit scoped to `.esas/` cannot see authorisations given in the terminal, so brief it that absence of evidence there is not evidence of absence.

**5 — Phase C: finalize & write back.** **Confirm before writing to the tracker** — it is outward-facing.

  **First, re-run each unit's premise probes and re-resolve its `groundedShas`.** Cheap (the probes are written down in the draft) and necessary: tickets are static between Phase A and Phase C only while the human *answers*; when the human **acts** (one fix shipped mid-sitting and collapsed its ticket to recurrence-prevention) the draft would instruct `/start-multi` to do work that no longer exists — and in the cross-repo case only the per-unit `groundedShas` can see it. **Stamp the block with the sha it was actually written against.**

  **The record must have one answer per fork.** `decisions.md` in the run dir is Phase B's authoritative record — cross-cutting policies first, then per-ticket resolutions — and the fold-back agents read it instead of the conversation. When the sitting **overrides** a pre-sitting auto-resolution, edit the original entry in place to `SUPERSEDED BY P<N>` (keep its rejected set); a record read top-down otherwise resolves to whichever line comes first, and that was the stale one. Before dispatching fold-back, check mechanically that every fork id has exactly one non-superseded answer.

  **Fold-back, then reconcile across units, then write — in that order.** The per-unit fold-back agents run in parallel, write-scoped to their own unit: each rewrites "Open forks" into "Resolved forks" (rejected options preserved), applies ripple edits, emits `<id>.ticket-block.md` marker-line-first as the exact text to append, **and emits an `obligations-on-siblings` list** (target ticket, the obligation, why) — fold-back routinely *discovers* that a sibling must ship a field, a command or a route, and a lane cannot patch a sibling's block. **Join those lists** and confirm each target block carries its obligation, patching or re-dispatching that unit; write-back is conditional on the join being empty. Then check every critique-promoted AC against `decisions.md`'s ownership — the critique lens is single-unit by design and will absorb a defect the board already de-collided to a sibling; record those as `owner: <ID>` cross-references, not ACs.

  **Two waves of writes, ADRs first.** The ADR/glossary agent (single writer) runs and finishes **before** the ticket and epic blocks are written, because the epic block describes the run's ADRs and a parallel agent that `ls`es for them mid-wave truthfully reports none. Cross-artifact references are **by reserved identifier from `run.yaml`**, never by an existence check at write time. Reserve the numbers against the **pinned base** (`git ls-tree origin/<default> -- <adr-dir>`, plus every sibling branch), never a working-dir listing, and **print the highest number found** — a monotonic-number query that returns nothing is a broken query (`git ls-tree` with a `./`-prefixed path matches nothing), not a clean namespace, and one such empty result handed three lanes a number already taken on `master`.

  Then, once confirmed, per ticket:

  - **The block, appended after a `---` separator — read-modify-append, never REPLACE.** The description is the single machine-readable channel; `/start-multi` reads it, not comments.

    ```
    <!-- design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id> -->
    ## Resolved Design (design-multi)
    `design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id>`
    { resolved decision tree with rejected options + evidence · seams/flow ·
      test seams · risks · unspecified seams · scope · file-overlap vs siblings }
    ```

    **`status` is required: `ready | deferred | blocked | umbrella`** — without it an unattended `/start-multi` burns a lane on a non-ready unit. A commissioned ticket that is ready **once a named sibling lands** is `status=ready deps=<TICKET-ID>`, never a coined status word: `/start-multi` reads only the four values and a fifth silently drops the unit. Every non-`ready` verdict carries three fields — `buildableNow` (what ships despite the block; forces the composition check that dissolved one near-block and rescued a live-defect slice from another), `blockProof` (needs X, dependency gives only Y, therefore Z) and `resolutionPath` (the un-defer trigger or the cheapest experiment that settles it) — because a bare `blocked` has silently removed buildable work and a bare `deferred` is indistinguishable from forgotten.

    **The marker line is the only machine-readable surface.** Emit it twice — the HTML comment *and* the visible inline-code line — and put every structured fact `/start-multi` needs (`status`, `base`, `run`, `deps`) as an attribute **on the marker**, never in the prose below. Readers match the token regex alone and tolerate any whitespace between marker and heading: Jira's round-trip inserts a blank line there, and other trackers strip comment nodes outright. `:vN` is the **contract version**; bump it only when the block's *shape* changes.

  - **The write contract, one sequential agent, never parallel** — a `200` says the write was accepted, never that the content survived. Jira Cloud's markdown → ADF → markdown round-trip is lossy in five known ways, and every one returns `200`:
    1. **Budget per ticket, in characters.** The cap is **~32,767 plain-text characters of the whole description**, existing text plus the block, so the headroom is `32767 − len(existing)` and differs per ticket (1,211 on one, 14,401 on its neighbour in one run). Count with `wc -m`, not `wc -c` — these blocks are dense in multibyte glyphs. Compose, count, then compress **markup before facts**: tables → prose bullets, drop backticks around paths, collapse multi-line risk entries — one agent cut 6,000 characters with zero fact loss that way, while another deleted content it never needed to. Citations and rejected-option evidence are the block's value and go last. Leave ~2k headroom or the next human edit is refused.
    2. **Never reproduce the preserved region by hand.** Slice the fetched description at its end (or at the marker, when replacing) and concatenate in a script; save the payload as a file and `diff` it against the fetch before sending. An agent that re-typed the prefix rendered one word into another language, and only its own disclosure caught it.
    3. **Never re-send a Jira-rendered description verbatim.** The fetched form carries hard breaks that delete the interior of a `**bold**` span straddling them on re-send, and paired `*` / `_` in prose come back as emphasis — a glob written as prose stopped being a runnable command. Rebuild from the local source of truth, and keep globs, flags and anything with paired asterisks in inline code (fenced blocks round-trip intact).
    4. **No table nested inside a list item** — the converter dropped one whole, with the load-bearing fact in it. Top-level tables or flat bullets.
    5. **Verify by a DIFF of the whole read-back against what was sent**, not a spot-check of the patch site: the bold deletion above landed three sections away from the edit. Classify each difference — bullet/fence/table-separator normalisation, `*` → `_`, escaped `~`, unwrapped bold around inline code are benign; a shortened span, a changed glob or a missing sentence **stops the run**. What is provable through `editJiraIssue` is *pre-fetch vs post-fetch of the preserved region* — claim that, not "byte-identical".

    Before writing, **compare `run=` on any marker already present**: same run → skip (partial-run residue); different run → stop and surface it with both blocks' `run=`, `base=` and `status=`, never skip silently and never overwrite. Then cross-check this run's cross-cutting policies (release sequencing, ADR allocations, shared-file ownership) against that sibling block.

  - **Capture glossary/ADR deltas in the block by default; do not commit them here.** You are on the **default branch**, which the branch-first rule puts off limits; most deltas describe code that **has not landed**, so committing them states aspirational behaviour as fact; and non-ready units must not have theirs applied at all. Name the third state: **`delta: specified, deferred to build`** — the content is written into the block as a named obligation (which section, what it must say, what it waits for), discharged by `/build` or `/verify-build` on the branch, where `/verify-build` already owns "finalize ADRs". Some deltas cannot be written now at any price — one restating measured figures cannot exist until the measurement runs.
    - **Commit a delta directly only when it documents an already-shipped decision**, and even then on a proper branch. Committing here also invalidates step 0's pin by construction.
    - **Allocate ADR numbers at Phase C even when the files land later** — deferring re-opens the collision race, and the allocator belongs outside the lane. Where a delta is cited by two tickets, name the **owning unit** so it is applied once.

**6 — Report & capture.** Per ticket → forks auto-resolved / forks you resolved → written to the description, with its **remaining character headroom** → deltas → the `BASE` grounded against. Re-derive any status you quote from the tickets, not from a mid-run table in `decisions.md` — a summary that was true when written is the most convincing kind of wrong. Then aggregate `<run>/units/*.learnings.md` plus your own Phase B/C friction and run **`/capture-learnings` once**, deduped across tickets.

  **If Phase B used the board, the handoff names the teardown.** This run's comments live in a layer scoped to one unit of work while the run spans N, so the moment the designs are written the layer is residue by construction and nothing downstream clears it — `/start-multi` works in worktrees with no `.esas/`, and the next `/design` here meets `design: present` and asks whose session it is. Say it out loud, and **never delete the files yourself**: they are gitignored, they are the only copy of this sitting's intent, and the user may still be reading the threads.

> Designs resolved and written to the tickets. Run `/start-multi <ids>` — it detects the resolved designs and runs `design` as a verification **second pass**, not a fresh grill, so the fleet stays unattended unless the code has drifted.
>
> This run's questions are still on the board, in a design layer that belongs to a single unit of work. When you are done reading them, delete `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor`.
>
> **Not before the unit is built in THIS checkout.** `/build`'s scaffold step reads `design.json` to generate the artifacts the design already fixes, so deleting it early turns every designed artifact back into hand-written work — silently, since a missing design layer is a legitimate state. It is safe to delete now for units heading into `/start-multi`, whose worktrees carry no design layer by design; it is not safe if you are about to run `/plan` and `/build` here.

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
