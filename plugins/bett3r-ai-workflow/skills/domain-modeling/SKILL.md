---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR.
metadata:
  credits:
    author: Matt Pocock
    source: https://github.com/mattpocock/skills
    license: MIT
    notice: ../../THIRD-PARTY-LICENSES.md
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `CONTEXT.md` for vocabulary is not this skill: that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily: only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up: capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

## In this flow

**Where the model lives.** When `.esas.config.json` exists, read `domainEventsPath`: contexts live at `<domainEventsPath>/src/<context>/CONTEXT.md` and the map at `<domainEventsPath>/src/CONTEXT-MAP.md`, one `CONTEXT.md` per bounded context, never one per aggregate. Without the config, the root layout above applies.

**ADR path.** Match the repo's existing ADR directory and filename pattern. Only a repo with no ADRs yet defaults to `docs/adr/ADR-NNN-slug.md`, the spelling `vertical-slicing`'s `slices.yaml` schema and `verify-build`'s PR template render; that default fires once per repo and sets the convention every later ADR inherits. `ADR-FORMAT.md`'s `0001-slug.md` spelling and its numbering by listing are the upstream skill's: in this flow this paragraph governs the filename and the next governs the number.

**ADR numbering.** Derive the next number from every ref and sibling branch, never from a directory listing, which shows only what reached this branch:

```sh
git log --all --name-only --pretty=format: | grep -oE 'ADR-[0-9]+' | sort -u | tail -5
```

Go above the highest; a query that returns nothing is a broken query, not a clean namespace. In a fleet the orchestrator allocates against the pinned base and records the numbers in `run.yaml`; a lane re-derives at dispatch, and `/verify-build` re-checks against the merge target. Amend an ADR that already covers the ground, and release a reserved number you did not use.

**Optional `Principle` section.** The rule this decision generalises to, stated so it is true away from this ticket (no ticket ids, no local identifiers), only when it genuinely generalises. `verify-build`'s PR template carries the same field.
