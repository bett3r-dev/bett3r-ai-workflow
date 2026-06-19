---
description: Transform Event Storming output into a DDD specification. Use after event storming sessions to generate structured specifications for your flow's design/refine step or the create-module skill.
---

# Skill: Event Storming to Spec

Transform structured event storming output (Mermaid flowcharts or text) into a complete DDD specification document.

## Project configuration

Resolve these placeholders from the repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |
| `<clientLibraryPackageName>` | `clientLibraryPackageName` | `@bett3r-dev/teselly-client-library` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Input

Accepts one of:
- Mermaid flowcharts from the `miro-to-mermaid` skill (in your active work/design directory, e.g. `.work/`)
- Pasted structured text with DDD components (commands, events, aggregates, policies, read models)

## Output

A complete DDD specification document saved to your active work/design directory (e.g. `.work/specification.md` — wherever your flow keeps design docs).

## Process

### Step 1: Parse Input

If a Mermaid flowchart from the `miro-to-mermaid` skill exists in your active work/design directory (e.g. `.work/`), use it.
Otherwise, ask user to paste the event storming output.

Parse all DDD components:
- **Commands** — Imperative actions (PascalCase with domain prefix)
- **Events** — Past tense outcomes
- **Aggregates** — State owners
- **Invariants** — Business rules / constraints
- **Policies** — Event reactions
- **Read Models** — Query projections

### Step 2: Identify Aggregate Ownership

Each command targets exactly one aggregate. Each event is emitted by exactly one aggregate. Map ownership:

```
Aggregate: OrdersAggregate
  Commands: PlaceOrder, EditOrder, ChangeOrderStatus
  Events: OrderPlaced, OrderEdited, OrderStatusChanged
  State: OrderSchema
```

### Step 3: Extract Value Objects

Look for repeating field groups (3+ fields that appear together). Extract as value objects:

```typescript
// Example: Address appears in customer info, shipping, billing
export const AddressSchema = S.shape({
  line1: S.string().optional(),
  city: S.string().optional(),
  state: S.string().optional(),
  country: S.string().optional(),
  postalCode: S.string().optional()
});
```

### Step 4: Generate Specification

Write the specification to your active work/design directory (e.g. `.work/specification.md`):

```markdown
# DDD Specification: [Module Name]

## Module

**Service:** server
**Module Location:** <serverPath>/src/modules/<module-name>/
**Domain Location:** <domainEventsPath>/src/<domain>/
**Bounded Context:** [context name]

## Purpose

[What this module does and why]

## State

### [AggregateName] State

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| ... | ... | ... | ... |

## Value Objects

### [ValueObjectName]

| Field | Type | Description |
|-------|------|-------------|
| ... | ... | ... |

## Events

| Event | Schema | Aggregate | Description |
|-------|--------|-----------|-------------|
| OrderPlaced | OrderPlacedEventSchema | OrdersAggregate | Order was created |
| ... | ... | ... | ... |

## Commands

| Command | Schema | Target Aggregate | Description |
|---------|--------|-----------------|-------------|
| PlaceOrder | PlaceOrderCommandSchema | OrdersAggregate | Create or update an order |
| ... | ... | ... | ... |

## Invariants

| ID | Rule | Error Code | Owner Aggregate |
|----|------|-----------|----------------|
| INV-1 | [Business rule description] | RULE_VIOLATION_CODE | [Aggregate] |
| ... | ... | ... | ... |

## Dependencies

| Dependency | Type | Usage |
|-----------|------|-------|
| the client library (<clientLibraryPackageName>) | internal | Cross-service commands |
| ... | ... | ... |

## Policies

| Policy | Trigger Event | Action | Description |
|--------|--------------|--------|-------------|
| MyPolicy | SomethingHappened | Execute downstream command | Reacts to X by doing Y |
| ... | ... | ... | ... |

## Read Models

| Read Model | Collection | Subscribes To | Queries |
|-----------|-----------|---------------|---------|
| OrdersReadmodel | sales_orders_readmodel | OrderPlaced, OrderEdited | /sales/orders/:id?, /sales/orders-search/ |
| ... | ... | ... | ... |

## Test Cases

### Happy Path
- [ ] [Flow description] — expected events/state

### Invariant Violations
- [ ] [Violation scenario] — expected error code

### Policy Reactions
- [ ] [Event] triggers [Policy] which [action]

### Readmodel Projections
- [ ] [Event] projects [data] into [collection]

### Boundary Tests
- [ ] [Boundary condition] — edge case description
```

### Step 5: Generate Test Cases Automatically

From the specification:
- **Happy path:** One per command flow
- **Invariant violation:** One per invariant
- **Policy reaction:** One per policy
- **Readmodel projection:** One per readmodel event handler
- **Boundary test:** For numeric invariants (min, max, zero, negative)

### Step 6: Design Quality Gate

Before presenting the specification, audit and critique it for accidental complexity, technical depth, and anti-patterns. Read the generated `specification.md` and check each item in a general sense. Starter questions can be, for example:

**Accidental complexity:**
Is the proposed solution the simplest thing that solves the problem? Or does it solve a harder, more general version of the problem than what's actually needed? Are there new abstractions, layers, or components whose value isn't clear? Could anything be removed without losing the core outcome?. Take two steps back and critique the approach. Ask yourself the question: what are we missing? Is there a better way to do this?. Specifically about the new Domain-Driven Design artifact:
- [ ] Is every new aggregate justified, or would a state field on an existing one do?
- [ ] Does any policy enforce what belongs as an aggregate invariant?
- [ ] Is there unnecessary indirection — event chains where a direct command would be cleaner?
- [ ] Premature generalization: a pattern built for one instance?

**Technical depth:**
Is the design cutting corners? Are there any footguns? Does the design introduce patterns, dependencies, or concepts that increase long-term maintenance cost without proportional benefit? Is it building infrastructure that will only ever have one consumer? Does it add concepts that a future developer would need special knowledge to understand?. Specifically about domain-driven design:
- [ ] Does the spec introduce patterns not in the `ddd-patterns` skill? If yes, justified?
- [ ] Does any component read a readmodel inside a command handler when state suffices?
- [ ] Any custom utilities duplicating PV3 built-ins?. Consider we have control over the PV3 repo as well, and we should extend its functionality before hacking around the framework.

**Anti-patterns:**
oes anything in the design contradict established project decisions, known failure modes from past work, or rules documented in the host repo's rules? Are there shortcuts in the design (e.g. type casts, raw HTTP calls, inline schemas) that paper over a deeper problem rather than solving it?. In regards to domain-driven design:
- [ ] Every policy is in the module of the aggregate it mutates
- [ ] Every readmodel schema belongs in the domain package
- [ ] No `produces([])` on side-effect-only commands
- [ ] No gateway ACL `produces` listing downstream aggregate events
- [ ] Route params in `withQuery` have matching `schemas.params`

Flag and resolve any failures before continuing.

### Step 7: Ask for Clarification

If any ambiguities exist:
- Which aggregate owns a command?
- What's the exact business rule for an invariant?
- Should a policy trigger synchronously or asynchronously?

Ask **one question at a time**. Let each answer inform the next question.

## Naming Conventions (PV3 DDD naming conventions)

- **Commands:** Imperative PascalCase with domain prefix — e.g. `RegisterShipment`
- **Events:** Past tense PascalCase with domain prefix — e.g. `ShipmentRegistered`
- **Aggregates/Systems:** PascalCase ending with `System` or `Aggregate` — e.g. `FulfillmentSystem`
- **Policies:** PascalCase ending with `Policy` — `OrderFulfillmentPolicy`
- **Readmodels:** PascalCase ending with `Readmodel` — `OrdersReadmodel`
- **Error codes:** SCREAMING_SNAKE_CASE — `ORDER_ALREADY_EXISTS`

## Schema References

Use `@bett3r-dev/jsonschema-definer` (S) for all schema references in the spec.
NOT Zod.

## Critical Constraints

- Parse flows completely — don't skip components
- Identify aggregate ownership for every command and event
- Error codes SCREAMING_SNAKE_CASE
- Ask for clarification on ambiguities — don't guess
- Aggregate IDs in stream, NOT in event payloads (use `extractIdFromEventStream()`)
- Extract Value Objects for repeating 3+ field groups
- Generate test cases automatically (don't wait to be asked)
- Event names must be past tense
- Command names must be imperative

## Final Checklist

- [ ] All commands mapped to an aggregate
- [ ] All events mapped to an aggregate
- [ ] All invariants have error codes
- [ ] All policies have trigger event and action
- [ ] All readmodels have collection name and subscribed events
- [ ] Value objects extracted for repeating field groups
- [ ] Test cases generated for all flows
- [ ] Naming follows PV3 DDD naming conventions
