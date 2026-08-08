---
description: Fleet designer — ground and resolve N tickets' designs in parallel (unattended), batch the genuine forks into one human pass, then bake each resolved design into its ticket so /start-multi can pick it up without stopping to grill.
---

# /design-multi — parallel design across tickets

Take a **list of tickets** through the code-answerable half of `/design` in parallel, then compress the human half into a **single batched interview**. The output is each ticket carrying a **resolved design** that `/start-multi` consumes unattended — its design-heavy gate never trips because the human moment already happened here.

You (the main session) are the **orchestrator**: you dispatch read-only design agents, aggregate their open forks, run the one interview yourself, and write the resolved designs back. You do **not** grill inside the agents — the interview is batched (Phase B).

This is **not** "start-multi for design." `/build` is unattended because it has a mechanical gate; `/design`'s engine is `grill`, which has none. So `/design-multi` splits `/design` in two: everything the **code** can settle runs in parallel and unattended (Phase A); the few forks that need **your intent** are batched into one sitting (Phase B); the resolved design is written to the ticket (Phase C).

Run state lives in `.work/design-multi/<run-id>/run.yaml` — ephemeral, gitignored, and the **resumable** source of truth. Re-running the same set resumes it.

## Argument: $ARGUMENTS
Ticket ids (+ optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--max-parallel N` | Cap concurrent design agents (Phase A). Read-only, so higher than start-multi is safe; still respect host limits. |
| `--run-id <id>` · `--fresh` | Resume-state controls. Default run-id: `design-multi-` + sorted ids. |

## Per-unit pipeline (Phase A — parallel, unattended, read-only)
`ground → verify-against-code → draft decision tree → auto-resolve → critique → emit draft`. Each agent runs `/design`'s **code-answerable** work only and **parks** every fork it can't settle from code or the standard probes, instead of asking. Agents mutate nothing.

## Steps

**0 — Acquire & snapshot (the only tracker touch).** Resolve `run-id`. If `run.yaml` exists and not `--fresh` → **resume** (skip to step 3). Else fetch each ticket's content from the tracker **once** and snapshot it into the run dir (agents read the snapshot, never the tracker). Pin the base the designs are grounded against: `git fetch origin`; `BASE=$(git rev-parse origin/<default-branch>)` — the **same base `/start-multi` will branch from**, so the design reflects the code start-multi builds on. Write `run.yaml`, all tickets `pending`.

**1 — No worktrees.** Phase A is **read-only** — the isolation `/start-multi` needs is for parallel *writes*, which this phase doesn't do. All agents read the one working tree (recommend a clean tree at/near `BASE`; note in each design if it was grounded against uncommitted local work). Nothing to create, nothing to tear down.

**2 — Dispatch design agents.** Launch background read-only agents up to `--max-parallel` (queue the rest). Each agent is scoped to one ticket, grounds against `BASE`, and runs the Phase-A protocol:
  1. **Ground** — read the ticket snapshot and the relevant bounded context's `CONTEXT.md` (locate via `.esas.config.json` `domainEventsPath`, per `domain-modeling`).
  2. **Verify the ticket against the code** — the full `/design` step-1 protocol (grep the central symbol; `git log -S <symbol>`; check the ticket's *premise*, not just its ask). Stale tickets are the norm — where ticket and code disagree, **the code wins** and the draft says so.
  3. **Draft the decision tree** and **auto-resolve** every fork the code or the standard `grill` probes settle (side-effect reconcilability, etc.). Each auto-resolution records its **rejected options** and the **evidence** (code reference / probe) that settled it — no silent decisions.
  4. **Critique** (`critique` skill, `arch,ops`) the resolved-so-far design: fold clearly-right fixes in; **promote a missed genuine fork to the open-forks list**; carry a no-good-answer weakness to *Risks*.
  5. **Emit** a per-ticket draft to `<run>/units/<id>.design-draft.md` and update `<id>.state.yaml`. The draft is `/design`'s doc shape (problem, resolved decision tree, seams/flow Mermaid, **test seams**, risks, scope) **plus** two extra sections: **Open forks** (each with a recommendation + one line of why) and **Proposed glossary/ADR deltas** (proposed, not written).

  **Single-writer rule:** each agent writes **only** its own `units/<id>.*` files; only you write `run.yaml`. An agent that fails unrecoverably is marked `failed`; the others continue.

  In a repo with a `.esas/`, the same rule covers the design layer, and it has to be **said** rather than assumed: the `esas-design` skill's standing rules fire wherever the `mcp__esas__*` tools are visible, and they are visible inside an agent. `get_flow` and `get_design` are reads and an agent may make them — grounding against the extracted graph is exactly Phase A's job. **No agent writes to the design layer**: no `comment`, no `resolve`, no `propose`, `modify` or `remove`. N agents writing one `design.json` is N tickets' designs in a layer ADR-001 scopes to one unit of work, serialized into a single feed in dispatch order with nothing recording which ticket asserted what.

  **Learnings, not issues:** an agent that hits friction in the flow itself (a probe that misfired, a skill that misled, a step that fought the grain) appends the note to its own `<run>/units/<id>.learnings.md` — **buffer only**, never `/capture-learnings` inside an agent (it files GitHub issues one-confirm-each and dedups against the backlog; parallel agents racing it duplicate). The orchestrator captures once (step 6).

**3 — Collect.** Aggregate per-unit state into `run.yaml`. Resume any `in_progress` (dead agent) unit from its next incomplete step — Phase A is idempotent; a unit already at `critiqued` with a draft on disk is skipped.

**4 — Phase B: the one batched interview.** Gather **every open fork across all tickets** into a single numbered list, grouped by ticket, **recommendation first**, one line of *why* each. Do **not** use `AskUserQuestion` — the user answers free-form (standing rule, per `grill`). When a fork is between designs that differ in *how data moves*, show the **per-scenario data-flow timeline**, not prose. This one pass also does what per-ticket `/design` can't: **cross-ticket coherence** — unify overlapping glossary terms, flag conflicting decisions across tickets, and surface duplicated scope. Fold answers back into each draft; if an answer opens a new fork, resolve it here — but keep it a focused sitting, not a fresh grill.

  **On the canvas, where this repo has one.** Phase B is the longest numbered list anywhere in the flow — every open fork of every ticket, in one sitting — which makes it the best case for a board the flow has and the worst thing in it to read as terminal scrollback. Where `/design`'s Step 0 gates both say yes (`.esas/` plus `esas-mcp` for capability; the aggregated forks naming graph artifacts for relevance), answer them **once for the run**, not per ticket, and post the open forks as `comment`s anchored to the elements they concern — the numbered list stays as the *map*, one line per fork, ticket id and fork name, while the options, the recommendation and the *why* move into the comment that holds the fork itself. That is the split `grill` and `esas-design` describe, and it is why the list does not shrink to nothing: the map is how you and the user both still see how many decisions this run is carrying. This is the one fleet command that can do it at all: Phase A cuts no worktrees, so you are still in the main checkout, which is the only place `.esas/` exists. Where either gate says no, say nothing about boards and run the sitting in the terminal — that is the flow this command already had.

  - **Comments only: `comment` and `resolve` are the only verbs Phase B writes.** Not `propose`, not `modify`, not `remove`, however tempting it is to draw N resolved designs on one canvas. ADR-001 scopes the design layer to one unit of work, and Phase B is holding N of them; N tickets' verbs in one `design.json` is a graph that describes no single system, and nothing downstream ever reconciles it — `/start-multi` branches into worktrees that have **no `.esas/`** (a worktree answers `ESAS_DIR_MISSING`, correctly), so the verbs stay behind in the main checkout after the run that meant them is over. A comment survives that because it asserts nothing about the architecture: it is a question about an element that already exists, and a question left open is legible residue where a proposal is a lie about the design.
  - **You post the batch. No agent writes to the design layer** (step 2) — one writer here for the same reason as `run.yaml`, and one write for the reason the board exists: arrays in, one `comment` call, one op, the whole sitting appearing at once instead of N tickets' questions trickling onto the canvas in dispatch order.
  - **Arm the summon watcher after you post the batch, as the last thing you do before going idle.** Phase B posts and then waits, and unarmed the board's **Ask Claude** button implies a channel nobody is listening on. One armed watch at a time; a second over a live one costs a wake nobody asked for. **Re-arm after each wake while any fork in the batch is still `resolved: false`** — N tickets' forks arrive in bursts, one press per burst. Two quiet timeouts end the channel. Arming is not a design-layer write, so the comments-only rule above stands; and **no agent arms anything** — the orchestrator does, as it posts the batch. The loop, its deadline and the six invariants that keep it from looping or going silent are the `esas-design` skill's half; this step decides only that it goes up here.
  - **Prefix every comment with its ticket id** — `TV1-123: <the fork>`. Comments are one flat chronological list per anchor and the schema carries no ticket field, so where several tickets touch the same aggregate their questions land in one thread with nothing but the text to tell them apart. The prefix is a text convention doing a field's work; it is the honest limit of this, not a feature (see the fallback below).
  - **Folding an answer back resolves its comment**, in the same pass, never in a sweep at the end. `resolved: false` is the shared to-decide list — it is what the board's badge counts and what tells you whether Phase B is finished — so a fork answered in the terminal and left open on the canvas sends the user back to re-answer a question you already have, which is the one failure a second screen makes *worse* than no second screen.
  - **Above roughly fifteen open forks, keep the whole list in the terminal.** The flat thread does not scale and this command is the flow most able to overrun it: at ten tickets a hot anchor collects a dozen unrelated questions with no grouping, and the prefix that was a convention becomes the only structure a wall of text has. Fifteen is a judgement, not a computed threshold — the question behind it is whether any single anchor's thread has stopped being readable. Fall back to the numbered list; do not design around the limit by inventing structure the store does not have.

**5 — Phase C: finalize & write back.** Present the finalized designs and **confirm before writing to the tracker** (writing to a ticket is outward-facing). Then, once confirmed:
  - **Write the resolved design to each ticket** (fork 1): **append a delimited, marked section to the description**, preserving all existing content. The description is the single machine-readable channel — `/start-multi` reads the description, not comments. Lead the block with the marker so `/start-multi` recognizes it:

    ```
    <!-- design-multi:resolved:v1 base=<BASE-sha> run=<run-id> -->
    ## Resolved Design (design-multi)
    { resolved decision tree with rejected options + evidence · seams/flow ·
      test seams · risks · scope — the record start-multi and a human both read }
    ```
    The `:v1` is the **contract version** shared with `/start-multi`. Bump it (`:v2`, …) only if the block's *shape* changes, so an older `/start-multi` refuses to misparse a newer block instead of guessing.
  - **Apply the glossary/ADR deltas once, by you** (single writer — parallel agents never touch the shared `CONTEXT.md`). These are **durable and committed**, exactly as `/design` treats them today. The full design draft stays ephemeral in the run dir.

**6 — Report & capture.** Per ticket → forks auto-resolved / forks you resolved → the design written to the description → glossary/ADR deltas committed → the `BASE` it's grounded against. Then aggregate the per-unit `<run>/units/*.learnings.md` (plus any flow-friction you hit in Phase B/C) and run **`/capture-learnings` once**, deduped across tickets — the parallel design pass is a strong source of grill / critique / flow learnings, and one batched capture keeps them from dying with the ephemeral run dir. Then the handoff:

**If Phase B used the board, the handoff names the teardown.** This run's comments live in a layer scoped to one unit of work while the run's own lifetime spans N — so the moment the designs are written to the tickets, that layer is residue by construction, and nothing downstream clears it: `/start-multi` works in worktrees that have no `.esas/`, and the next `/design` in this checkout meets `design: present`, asks whose session it is, and is told about a run that ended days ago. Say it out loud, and **never delete the files yourself** — they are gitignored, they are the only copy of this sitting's intent, and the user may still be reading the threads. Same rule as `/design` Step 0; the difference is only that here it is *you* who left them.

> Designs resolved and written to the tickets. Run `/start-multi <ids>` — it detects the resolved designs and runs `design` as a verification **second pass**, not a fresh grill, so the fleet stays unattended unless the code has drifted.
>
> This run's questions are still on the board, in a design layer that belongs to a single unit of work. When you are done reading them, delete `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor` — nothing downstream does it, and the next design in this repo will otherwise open on this run's leftovers.

## Decisions → the ticket's resolved-design block
Every decision — auto-resolved in Phase A **and** resolved by you in Phase B — rides into the ticket's resolved-design block **with its rejected options and the evidence** that settled it. This is the design-multi analogue of start-multi's "decisions → PR body + ADRs": an unattended `/start-multi` pickup must be able to see *why*, never inherit a silent choice.

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
Orchestrator is the **sole writer** of `run.yaml`; agents write only `units/<id>.*`. `step` + the presence of the draft file determine where to resume.

## Principles (lessons baked in)
- **Split design at its natural seam.** Code-answerable → parallel & unattended (Phase A); intent-dependent → one batched interview (Phase B). Never fake the interview inside an agent.
- **Read-only, so no worktrees, no teardown.** Worktree isolation exists for parallel *writes*; this phase has none. This is the simplification `/design-multi` earns over `/start-multi`.
- **Ground against the base start-multi will branch from** — the design reflects the code it will be built on; record `groundedBaseSha` for drift detection.
- **Tracker once, then never** — the run is self-contained and resumable.
- **The batch is where cross-ticket coherence happens** — per-ticket `/design` can't see the other tickets; this pass can. Unify terms, flag conflicts, kill duplicated scope there.
- **The board carries Phase B's questions, never its answers.** Comments and `resolve`, one writer, one batch, a ticket-id prefix on every entry — and the layer they live in is named in the handoff for the user to delete, because a per-run command is borrowing a per-unit-of-work file.
- **No silent decisions** — auto-resolved and human-resolved alike ride into the ticket with rejected options and evidence.
- **Glossary/ADR are durable and committed by the single writer; the design draft is ephemeral;** the resolved design in the ticket is what start-multi consumes.
- **Confirm before writing to a ticket** — it's outward-facing and (for description appends) touches a shared artifact.
- **Capture learnings once, at the end.** Agents `record` flow-frictions to their own buffer; the orchestrator runs a single batched `/capture-learnings` over the aggregated buffers — never per-agent (it races on issue-filing), and never left to die with the ephemeral run dir.
