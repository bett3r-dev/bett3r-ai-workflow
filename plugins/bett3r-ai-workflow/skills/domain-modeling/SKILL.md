---
name: domain-modeling
description: Build and sharpen the project's domain model (ubiquitous language + decision records) as you design. Use when pinning down domain terminology, recording an architectural decision, or when another skill (grill/design) needs to maintain the domain model.
---

# Domain modeling

Actively build and sharpen the project's domain model *as you design* — challenge terms, invent edge-case scenarios, and write the glossary and decisions down the moment they crystallise. This is the active discipline of *changing* the model, not merely reading it. (Reading `CONTEXT.md` for vocabulary is a one-line habit any skill can do — this skill is for when you are pinning the model down.)

> Adapted from Matt Pocock's `domain-modeling` skill (github.com/mattpocock/skills), tuned for the bett3r workflow: glossaries live next to the canonical domain definitions, located via `.esas.config.json`.

## Where the model lives

The ubiquitous language belongs **next to the canonical domain definitions** (schemas/events/types), not next to the behavior — co-location with the code that embodies each term is the anti-drift mechanism. Locate it from the repo config:

- **If `.esas.config.json` exists**, read `domainEventsPath`. Contexts live at `<domainEventsPath>/src/<context>/CONTEXT.md`; the map at `<domainEventsPath>/src/CONTEXT-MAP.md`.
- **Otherwise**, fall back to repo root: a single `CONTEXT.md`, or a `CONTEXT-MAP.md` + per-area `CONTEXT.md`.

One `CONTEXT.md` per **bounded context** (the top-level domain folder) covering all its aggregates — **not** one per aggregate. A `CONTEXT-MAP.md` (when present) means the repo has multiple contexts; it lists them and their relationships (usually the domain events that flow between them).

Create files **lazily** — only when you have something to write. No `CONTEXT.md` yet? Create it when the first term is resolved. No ADR directory? Create it when the first ADR is needed.

## During the session

- **Challenge against the glossary.** When a term conflicts with `CONTEXT.md`, call it out immediately: "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"
- **Sharpen fuzzy language.** For vague or overloaded words, propose a precise canonical term: "You're saying 'account' — do you mean the Customer or the User? Those are different things."
- **Discuss concrete scenarios.** Stress-test domain relationships with specific scenarios that probe edge cases and force precision about the boundaries between concepts.
- **Cross-reference with code.** Check the glossary against the actual schemas/events in the same folder. Surface contradictions: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?" **This is the anti-rot step** — co-location makes it cheap.
- **Update `CONTEXT.md` inline.** When a term resolves, write it down right there — don't batch. Use [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md). `CONTEXT.md` is a glossary and **nothing else** — no implementation detail, no spec, no scratchpad.
- **Offer ADRs sparingly.** Only when **all three** hold: (1) hard to reverse, (2) surprising without context, (3) the result of a real trade-off. Use [ADR-FORMAT.md](./ADR-FORMAT.md).
