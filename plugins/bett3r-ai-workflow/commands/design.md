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

## Step 2 — Grill (using the `grill` + `domain-modeling` skills)

Run the interview: walk every branch of the decision tree, one question at a time, each with your recommended answer; resolve dependencies between decisions before moving on. While you do:

- **Sharpen the language** — challenge terms against the glossary, propose canonical terms for fuzzy ones, stress-test relationships with concrete edge-case scenarios, and **cross-reference claims against the code**.
- **Update `CONTEXT.md` inline** the moment a term resolves (glossary only — no implementation detail).
- **Offer an ADR** only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Continue until you reach genuine shared understanding — every pivotal fork resolved, no hand-waving.

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
