# CONTEXT.md Format

> Adapted from Matt Pocock's `domain-modeling` skill.

## Structure

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

## Rules

- **Be opinionated.** When multiple words exist for one concept, pick the best and list the others under `_Avoid_`.
- **Keep definitions tight.** One or two sentences. Define what it IS, not what it does.
- **Only context-specific terms.** General programming concepts (timeouts, error types, utility patterns) don't belong even if used heavily. Before adding a term, ask: is this unique to this context's domain, or general programming? Only the former.
- **No implementation detail.** This is a glossary, not a spec or a scratchpad.
- **Group under subheadings** when natural clusters emerge; a flat list is fine for a cohesive context.

## Single vs multi-context repos

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

## Locating the files (bett3r workflow)

- If `.esas.config.json` exists, contexts live under `<domainEventsPath>/src/<context>/CONTEXT.md` and the map at `<domainEventsPath>/src/CONTEXT-MAP.md`.
- Otherwise repo root.
- Infer the active context from the topic. If `CONTEXT-MAP.md` exists, read it to find contexts. If unclear which context a topic belongs to, ask.
