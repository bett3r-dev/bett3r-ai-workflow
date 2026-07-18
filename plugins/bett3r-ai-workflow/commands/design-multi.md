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

**3 — Collect.** Aggregate per-unit state into `run.yaml`. Resume any `in_progress` (dead agent) unit from its next incomplete step — Phase A is idempotent; a unit already at `critiqued` with a draft on disk is skipped.

**4 — Phase B: the one batched interview.** Gather **every open fork across all tickets** into a single numbered list, grouped by ticket, **recommendation first**, one line of *why* each. Do **not** use `AskUserQuestion` — the user answers free-form (standing rule, per `grill`). When a fork is between designs that differ in *how data moves*, show the **per-scenario data-flow timeline**, not prose. This one pass also does what per-ticket `/design` can't: **cross-ticket coherence** — unify overlapping glossary terms, flag conflicting decisions across tickets, and surface duplicated scope. Fold answers back into each draft; if an answer opens a new fork, resolve it here — but keep it a focused sitting, not a fresh grill.

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

**6 — Report.** Per ticket → forks auto-resolved / forks you resolved → the design written to the description → glossary/ADR deltas committed → the `BASE` it's grounded against. Then the handoff:

> Designs resolved and written to the tickets. Run `/start-multi <ids>` — it detects the resolved designs and runs `design` as a verification **second pass**, not a fresh grill, so the fleet stays unattended unless the code has drifted.

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
- **No silent decisions** — auto-resolved and human-resolved alike ride into the ticket with rejected options and evidence.
- **Glossary/ADR are durable and committed by the single writer; the design draft is ephemeral;** the resolved design in the ticket is what start-multi consumes.
- **Confirm before writing to a ticket** — it's outward-facing and (for description appends) touches a shared artifact.
