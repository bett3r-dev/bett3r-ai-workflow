---
description: Grill the design to shared understanding while sharpening the domain model, then write a reviewable design doc. Composes the grill + domain-modeling skills.
---

# /design — grill + model the design

Resolve the design through a relentless interview, sharpening the ubiquitous language as you go, and leave a **reviewable** design doc plus durable glossary/ADR updates. This is "grill-with-docs": the `grill` skill drives the interview, the `domain-modeling` skill maintains the model.

## Argument: $ARGUMENTS
The thing to design (a ticket id, a feature description, or "the active work").

---

## Step 1 — Ground the interview

- Read the ticket / context. Read the relevant bounded context's `CONTEXT.md` (locate it via `.esas.config.json` `domainEventsPath`, per the `domain-modeling` skill) so you speak the project's ubiquitous language from the first question.
- Explore the codebase for anything the design depends on — **answer from the code, not speculation**, wherever a question can be settled that way.
- **Verify the ticket against the code before trusting it — stale tickets are the norm, not the exception.** Building from the ticket text alone routinely produces the wrong change: re-implementing something that already shipped, or implementing something whose premise no longer holds. (In one 4-ticket run, three descriptions were stale — a "missing" flag had shipped months earlier, an already-fixed error, an event schema already live built-to-contract by its consumer — and a fourth's stated premise was simply false.) This is minutes of work and it is exactly what the design-first gate is for, so make it explicit:
  1. **Grep for the ticket's central symbol** — the flag, event, or command it names. Does it already exist?
  2. **`git log -S <symbol>`** — has it been shipped? Reverted? Had its tests deleted?
  3. **Check the ticket's stated *premise*, not just its ask** — if it says "this unblocks X," confirm X is blocked *only* by this, and that something actually populates what X depends on.
  4. Where the ticket and the code disagree, **the code wins** — and the design doc says so explicitly, so the reader knows the ticket text was stale and what the real change is.

## Step 1.5 — If the ticket carries a resolved-design block (second pass)

If the ticket has a `<!-- design-multi:resolved:v1 ... -->` block, its design was already resolved in an earlier `/design-multi` interview. **This run is a verification second pass, not a fresh grill.** Those are prior decisions, each with its rejected options and the evidence that settled it — treat them as **authoritative pre-answers**, the same way you treat the code:

- **Verify, don't re-derive.** For each resolved decision, confirm it still holds against the *current* code (the same step-1 protocol). Only **re-open** a fork the code now **contradicts** — e.g. the block was grounded against an older base and something it assumed has since shipped or changed.
- On a ticket whose code hasn't drifted, the grill has **nothing to ask** and flows straight to Step 2.5 / the doc. This is exactly what lets `/start-multi` run such a ticket unattended.
- Where a resolved decision no longer holds, surface it as a normal fork (Step 2). Running standalone, you ask the user; under `/start-multi`, that unit escalates.

## Step 2 — Grill (using the `grill` + `domain-modeling` skills)

Run the interview: walk every branch of the decision tree, one question at a time, each with your recommended answer; resolve dependencies between decisions before moving on. While you do:

- **Sharpen the language** — challenge terms against the glossary, propose canonical terms for fuzzy ones, stress-test relationships with concrete edge-case scenarios, and **cross-reference claims against the code**.
- **Update `CONTEXT.md` inline** the moment a term resolves (glossary only — no implementation detail).
- **Offer an ADR** only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Continue until you reach genuine shared understanding — every pivotal fork resolved, no hand-waving.

## Step 2.5 — Critique the resolved design (using the `critique` skill)

Before writing it down, turn the lens on the design. The grill was *convergent* — it built the design *with* the user; the `critique` skill is *divergent* — it attacks the resolved position. Run `critique` (default `arch,ops` lenses) against the resolved decision tree and surface the verdict: the top weaknesses, the severity, and kill-or-continue.

- If critique lands a **fix that's clearly right**, fold it back into the design before writing the doc.
- If it surfaces a **genuine fork the grill missed**, drop back into Step 2 and resolve it.
- A weakness with **no good answer** is a risk — carry it into the design doc's *Risks* section rather than pretending it's solved.

Don't let this become a second grill; it's one focused adversarial pass on what's already decided.

## Step 3 — Write the design doc → `.work/design.md`

Write the resolved design to `.work/design.md` (create `.work/` if absent; it is gitignored and ephemeral). **Markdown + Mermaid** so it renders in an editor with a mermaid preview. Aim for a doc a teammate can review in one pass:

- **Problem & intent** — what we're solving, in the ubiquitous language.
- **The resolved decision tree** — each pivotal fork and the chosen answer, with the why.
- **Seams / flow** — a Mermaid diagram of the key flow (e.g. command → event → policy → …) and any new boundary the design crosses.
- **Test seams** — where the feature will be *verified*. Prefer existing seams to new ones; use the highest seam possible; minimize their number (ideal: one). Note a prior-art test to mirror for each. These become the slices' oracles in `/plan` — confirm them with the user before finishing.
- **Risks / the gate-less seam** — the riskiest part nothing automatically catches (this becomes the tracer bullet in `/plan`).
- **Scope boundaries** — explicit in/out, and any follow-ups to spin off.

This doc is **ephemeral** — it is the review surface and the input to `/plan`. Its durable conclusions live in the glossary/ADR updates (committed) and, later, the PR body. Do **not** commit `design.md`.

## Step 4 — Hand off

Summarise: the resolved design, any `CONTEXT.md`/ADR updates made, and the open risks. Then:

> Review `.work/design.md`. When it's right, run `/plan` to cut it into vertical slices.

## Principles

- The grill is the engine; the docs are a side effect, not the goal. Don't let doc-writing slow the interview.
- `CONTEXT.md` updates are durable and committed; `design.md` is ephemeral.
- Speak the ubiquitous language — if the design needs a term the glossary lacks, that's a term to resolve and record.
