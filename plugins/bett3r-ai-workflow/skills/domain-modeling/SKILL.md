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

Infer the active context from the topic. If `CONTEXT-MAP.md` exists, read it to find the contexts; if it is unclear which context a topic belongs to, **ask**.

Create files **lazily** — only when you have something to write. No `CONTEXT.md` yet? Create it when the first term is resolved. No ADR directory? Create it when the first ADR is needed.

## During the session

- **Challenge against the glossary.** When a term conflicts with `CONTEXT.md`, call it out immediately: "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"
- **Sharpen fuzzy language.** For vague or overloaded words, propose a precise canonical term: "You're saying 'account' — do you mean the Customer or the User? Those are different things."
- **Discuss concrete scenarios.** Stress-test domain relationships with specific scenarios that probe edge cases and force precision about the boundaries between concepts.
- **Cross-reference with code.** Check the glossary against the actual schemas/events in the same folder. Surface contradictions: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?" **This is the anti-rot step** — co-location makes it cheap.
- **Update `CONTEXT.md` inline.** When a term resolves, write it down right there — don't batch. `CONTEXT.md` is a glossary and **nothing else** — no implementation detail, no spec, no scratchpad.
- **Offer ADRs sparingly.** Only when **all three** hold: (1) hard to reverse, (2) surprising without context, (3) the result of a real trade-off.

---

# `CONTEXT.md` format

```md
# {Context Name}

{One or two sentences: what this context is and why it exists.}

## Language

**Order**:
A customer's request to purchase one or more items.
_Avoid_: Purchase, transaction

**Publication**:
An item listed for sale on an external sales channel.
_Avoid_: Listing, posting

**Customer**:
A person or organization that places orders.
_Avoid_: Client, buyer, account
```

- **Be opinionated.** When multiple words exist for one concept, pick the best and list the others under `_Avoid_`.
- **Keep definitions tight.** One or two sentences. Define what it IS, not what it does.
- **Only context-specific terms.** General programming concepts (timeouts, error types, utility patterns) don't belong even if used heavily. Before adding a term, ask: is this unique to this context's domain, or general programming? Only the former.
- **No implementation detail.** This is a glossary, not a spec or a scratchpad.
- **Group under subheadings** when natural clusters emerge; a flat list is fine for a cohesive context.

## The map, when there is more than one context

**Single context:** one `CONTEXT.md` (at the domain root, or repo root if there is no domain package).

**Multiple contexts:** a `CONTEXT-MAP.md` lists the contexts, where they live, and how they relate — typically the domain events that flow between them:

```md
# Context Map

## Contexts

- [Sales](./sales/CONTEXT.md) — receives and tracks customer orders
- [Items Publishing](./items-publishing/CONTEXT.md) — lists items on external sales channels
- [Stock Management](./stock-management/CONTEXT.md) — tracks per-warehouse availability
- [Invoicing](./invoicing/CONTEXT.md) — generates fiscal vouchers from orders

## Relationships

- **Sales → Stock Management**: Sales emits `OrderPlaced`; Stock Management decrements warehouse availability
- **Stock Management → Items Publishing**: stock changes drive channel-stock rules that push to the channel
- **Sales → Invoicing**: an order in the right state triggers voucher generation
```

---

# ADR format

## Location & numbering — match the repo

**Detect the repo's existing ADR convention and follow it** — do not impose a new one. Scan for an existing ADR directory (commonly `docs/adr/`, `docs/development/adr/`, or `docs/decisions/`) and copy its location and filename pattern.

Only if the repo has **no** ADRs yet, default to **`docs/adr/ADR-NNN-slug.md`** — the spelling the rest of this plugin renders into every host repo (`vertical-slicing`'s `slices.yaml` schema, `verify-build`'s PR-body template). This rule fires exactly once per repo, on the *first* ADR, and every later ADR inherits whatever it produced by "match what's there" — so a default that disagrees with the templates sets a convention the repo keeps forever, and one the flow's own artifacts then fail to match. The three must agree; if the zero-padded form is ever preferred, both templates change too.

**Never take the next number from a directory listing.** A listing shows only numbers that reached *your* branch, and numbers on unmerged siblings, open PRs and long-lived stacks are already claimed — invisible and taken. Scan every ref:

```sh
git log --all --name-only --pretty=format: | grep -oE 'ADR-[0-9]+' | sort -u | tail -5
```

and go above that. The collision is **silent**: different slugs mean different filenames, so nothing conflicts, the merge is clean, and both land. It is not a parallelism artifact either — two sequential sessions on two long-lived stacks produce it just as readily, and one repo's namespace reached 22% duplicated numbers this way. Duplicates break every inbound `ADR-0NN` citation permanently, and renumbering after merge is not a cleanup but a decision about breaking references — so the cheap moment is before the number is used. Under a fleet, the orchestrator allocates numbers rather than lanes self-numbering; `/verify-build` re-checks uniqueness **against the merge target** regardless, since a number can be claimed between design and merge.

Prefer **amending an existing ADR** where one already covers the ground, and release a reserved number you did not use.

## Template

```md
# {Short title of the decision}

{1–3 sentences: the context, what we decided, and why.}
```

An ADR can be a single paragraph. The value is recording *that* a decision was made and *why* — not filling out sections.

**Optional sections** — include only when they add genuine value (most ADRs won't need them):

- **Status** (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — when decisions get revisited
- **Considered Options** — when the rejected alternatives are worth remembering
- **Consequences** — when non-obvious downstream effects need calling out

## When to offer an ADR — all three must be true

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons.

If easy to reverse, skip it — you'll just reverse it. If unsurprising, nobody will wonder. If there was no real alternative, there's nothing to record.

### What qualifies

- **Architectural shape.** "The write model is event-sourced; the read model projects to Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices with lock-in.** Database, message bus, auth provider, deployment target — the ones that would take a quarter to swap.
- **Boundary & scope decisions.** "Customer data is owned by the Customer context; others reference it by ID only." The explicit *no*s are as valuable as the *yes*es.
- **Deliberate deviations from the obvious path.** "Manual SQL instead of an ORM because X." Stops the next engineer from "fixing" something deliberate.
- **Constraints not visible in the code.** Compliance, latency budgets, partner-API contracts.
- **Rejected alternatives when the rejection is non-obvious.** So nobody re-proposes it in six months.
