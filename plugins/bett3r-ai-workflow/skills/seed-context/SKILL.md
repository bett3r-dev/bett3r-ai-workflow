---
name: seed-context
description: Bootstrap or refresh a whole bounded context's CONTEXT.md glossary from its existing code, code first, then grill only the gaps. For an existing subdomain with no or a stale CONTEXT.md.
disable-model-invocation: true
---

# Seed context

Seed a complete bounded context's `CONTEXT.md` from code that already exists: the one-time pass, where `/design` grows a glossary inline during a feature. Code first, so nothing is fabricated; grill only what code cannot settle. Not for greenfield contexts, which grow their glossary through `/design`.

`Call the Skill tool with "domain-modeling"` for the `CONTEXT.md` format, the glossary-only rule, the anti-rot cross-reference and the sparing-ADR rule. This skill owns only the seeding.

## Step 1 — Locate the context

Read `.esas.config.json` for `domainEventsPath` (repo root when absent). The subdomain's canonical definitions live under `<domainEventsPath>/src/<context>/`, its server module holds the behaviour, and the glossary goes to `<domainEventsPath>/src/<context>/CONTEXT.md`. Done when all three paths are named.

## Step 2 — Extract from code

Read the subdomain's schemas, events, commands, aggregates, reducers and policies and pull the facts: the term list (entity, event and command names, domain concepts only, so implementation fields like `correlationId` or `expectedVersion` are skipped); relationships and cardinality (reducers say what holds what, keyed maps `x.{id}` mean many, policies say which events cross contexts); lifecycles (status enums plus the commands that transition them); invariants (the guards the aggregates enforce). Done when each fact cites the file it was read from.

## Step 3 — Fold in existing knowledge

Read `${CLAUDE_PROJECT_DIR}/.claude/rules`, `AGENTS.md`, existing ADRs and any domain graph, as priors and as a cross-check against the code. A disagreement between docs and code is a flag for Step 5, not a fact to pick. Done when every disagreement is listed.

## Step 4 — Draft CONTEXT.md

Write the draft in `domain-modeling`'s format: one tight sentence per term, cross-referenced against the schema in the same folder as you write it. Glossary only. Done when every term from Step 2 has an entry.

## Step 5 — Grill the gaps only

Collect what code cannot settle and grill the user on exactly those: the canonical term and its `_Avoid_` list where the code uses synonyms (offer the observed candidates, never an invented one); fuzzy boundaries between near-terms; intent, the "what it is and why it exists" the code under-determines; terms used two ways or mid-migration (ask rather than snapshot the confusion). Done when every flag has an answer or is recorded as open.

## Step 6 — Write and review

Write `CONTEXT.md` to the located path; update `CONTEXT-MAP.md` (create it once the repo has more than one context) with this subdomain and its event relationships. Open a PR: a seeded glossary is a reviewed draft until merged. One bounded context per run; seed the high-traffic contexts first and let the rest grow through `/design`. Done when the PR is open.
