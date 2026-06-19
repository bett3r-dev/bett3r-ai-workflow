---
name: seed-context
description: Bootstrap (or refresh) a complete bounded context's CONTEXT.md glossary from its existing code — code-first extraction, then grill only the gaps. Use to seed the ubiquitous language for an existing subdomain that has no/stale CONTEXT.md. Defers to domain-modeling for the glossary format and discipline.
---

# Seed context

Bootstrap a complete bounded context's `CONTEXT.md` from code that already exists — the one-time pass the inline `domain-modeling` discipline doesn't cover (that one sharpens the glossary *during* a feature; this one seeds an existing subdomain wholesale). **Code-first**, so it doesn't fabricate; **grill only what code can't settle.**

This skill owns the *seeding orchestration*. It **refers to `domain-modeling`** for the `CONTEXT.md` format, the glossary-only rule, the anti-rot cross-reference, and the sparing-ADR rule — do not duplicate those here.

## When to use

An existing subdomain has no `CONTEXT.md` (or a stale one) and you want to capture its ubiquitous language. **Not** for greenfield contexts built through the flow — those grow their glossary inline during `/design`.

## Step 1 — Locate the context

Read `.esas.config.json` for `domainEventsPath` (repo-root fallback). The target subdomain's canonical definitions live under `<domainEventsPath>/src/<context>/`; the matching server module (if any) holds its behavior. The glossary goes to `<domainEventsPath>/src/<context>/CONTEXT.md`.

## Step 2 — Extract from code (the high-confidence seed — no assumption)

Read the subdomain's schemas / events / commands / aggregates / reducers / policies and pull the **facts**:

- **Term list** — entity / event / command names. Filter to **domain concepts only** (the `domain-modeling` rule); skip general-programming / implementation fields (`correlationId`, `expectedVersion`, `additionalProperties`).
- **Relationships & cardinality** — from reducers (what state holds what), keyed maps (`x.{id}` → "many"), and policies (which events flow between contexts).
- **Lifecycles** — status enums + the commands that transition them.
- **Invariants** — the guards enforced in the aggregates.

This is reading, not inventing — it's the prescriptive ~80%.

## Step 3 — Fold in the repo's existing knowledge (priors + cross-check)

Read whatever domain knowledge the host repo already has — `${CLAUDE_PROJECT_DIR}/.claude/rules`, `AGENTS.md`, existing ADRs, an ESAS / domain graph if present — and use it BOTH as priors and as a **cross-check** against the code. Where existing docs and the code disagree, that's a flag for Step 5; do not silently trust either.

## Step 4 — Draft CONTEXT.md (grounded, per domain-modeling)

Write the draft in `domain-modeling`'s `CONTEXT.md` format. For each term, a tight one-sentence definition **cross-referenced against the schema in the same folder as you write it** (the anti-rot check, applied at seed time). Glossary only — no implementation detail.

## Step 5 — Flag the gaps, then grill ONLY those

Do **not** fabricate the parts code can't settle. Collect them and grill the user on just these:

- **Canonical term + `_Avoid_`** — where the code uses synonyms (e.g. `client` vs `customer`), list the **observed** candidates and ask which is canonical. Never invent synonyms not seen in code/docs.
- **Fuzzy boundaries** — near-terms whose prose distinction is unclear (e.g. Item vs Variation vs Publication vs Listing).
- **Intent** — the "what it IS / why it exists" that the code under-determines.
- **Inconsistencies / in-flux terms** — where the code uses a term two ways, or something is mid-migration. Don't snapshot confusion — ask.

Grilling only the flags is what keeps this short: the obvious 80% came from code; you resolve only the real decisions.

## Step 6 — Write & review

Write `CONTEXT.md` to the located path; update `CONTEXT-MAP.md` (create it once the repo has >1 context) with this subdomain and its event relationships. Open it as a **PR** — a seeded glossary is a reviewed draft, not an authority, until merged.

## Principles

- **Code-first; grill the gaps; never fabricate precision.** A wrong glossary is trusted, read every time, and poisons its own cross-reference check.
- **One bounded context per run.** Seed the high-traffic contexts first; leave the rest to grow inline via `/design`.
- **Refer to `domain-modeling`** for format and discipline — this skill is only the seeding orchestration.
