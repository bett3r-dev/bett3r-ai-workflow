---
description: Scaffold a new event-sourced aggregate with PV3 AggregateBuilder pattern. Use when adding a new aggregate to handle commands and emit events.
---

# Skill: Create Aggregate

Scaffold an event-sourced aggregate using PV3's `AggregateBuilder`.

**Read [`ddd-patterns` → AGGREGATES.md](../ddd-patterns/AGGREGATES.md) before writing the file.** It is this skill's reference half: command-handler options, `idempotency.check` semantics, transactional side-writes and the UNIQUE-constraint lock, event-namespace coverage, system/admin-only and tenant-but-not-row-scoped aggregates, lifecycle status guards, and the idempotency-predicate null-safety bug. Changing an *existing* aggregate's fields also means [SCHEMAS.md](../ddd-patterns/SCHEMAS.md) → *Renaming a persisted field*.

**What the scaffolder does and does not do here.** It never generates an aggregate file — an
aggregate's reducers and invariants are judgment, and there is nothing in the graph to derive them
from. But a **new command on an aggregate that already exists** is generated, as a fragment: the
`commandBuilder()` block with its `.withSchema(...)` and `.produces([...])`, for you to place
inside `.withCommands({…})`. What it deliberately does not guess is the part that matters most —
the handler body, the invariants, the idempotency check, and any stream override. A generated
command declaration that emits its event unconditionally is correct **only** for the simplest
case; read [AGGREGATES.md](../ddd-patterns/AGGREGATES.md) before assuming yours is one.

## Project configuration

Resolve these placeholders from the `.esas.config.json` at your repo root:

| Placeholder | `.esas.config.json` field |
|---|---|
| `<serverPath>` | `serverPath` |
| `<domainEventsPackageName>` | `domainEventsPackageName` |
| `<domainUtilsPackageName>` | `domainUtilsPackageName` *(optional; defaults to `<domainEventsPackageName>` + `-utils`)* |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Pattern

```typescript
import { AggregateBuilder, idempotency } from '@bett3r-dev/pv3';
import { MyEvents, MySchema, CreateCommandSchema, EditCommandSchema } from '<domainEventsPackageName>';
import { scopeInvariant } from '<domainUtilsPackageName>';
import { Ports } from 'ports';

export const MyAggregate = ( ports: Ports ) => {
  return AggregateBuilder( MySchema, MyEvents )
    .withCommandTemplate({ invariants: [scopeInvariant()] } as any)
    .withEventReducers({
      EntityCreated: ( _, event, metadata ) => ({ ...event, ownerId: metadata?.userId }),
      EntityEdited: ( state, event ) => ({ ...state, ...event }),
      EntityStatusChanged: ( state, event ) => ({ ...state, ...event })
    })
    .withCommands(({ commandBuilder }) => ({
      CreateEntity: commandBuilder()
        .withSchema( CreateCommandSchema )
        .produces([ 'EntityCreated' ])
        .withHandler( async( createEvent, state, data, { context }) => {
          const accountId = data.accountId || context?.user?.accountId;
          return [createEvent( 'EntityCreated', data, { metadata: { accountId }})];
        }),

      EditEntity: commandBuilder()
        .withSchema( EditCommandSchema )
        .produces([ 'EntityEdited' ])
        .withHandler( async( createEvent, state, data, { context }) => {
          const accountId = context?.user?.accountId;
          return [createEvent( 'EntityEdited', data, { metadata: { accountId }})];
        }),

      ChangeStatus: commandBuilder()
        .withSchema( ChangeStatusCommandSchema )
        .produces([ 'EntityStatusChanged' ])
        .withHandler( async( createEvent, state, data, { context }) => {
          const accountId = context?.user?.accountId;
          return [createEvent( 'EntityStatusChanged', {
            status: data.status,
            previousStatus: state?.status
          }, { metadata: { accountId }})];
        })
    }));
};
```

## File Location

```
<serverPath>/src/modules/<module-name>/<entity>.aggregate.ts
```

Just ONE file. No controller, no module, no service wrapper.

## Registration

In the module's `index.ts`:

```typescript
ports.eventsourcing.routeCommandHandler( MyAggregate( ports ));
```

## CommandBuilder API

### Basic command (no handler needed)

When the command simply passes data through to the event:

```typescript
AssignCategory: commandBuilder()
  .withSchema( CategoryAssignedEventSchema )
  .produces([ 'CategoryAssigned' ])
```

No `.withHandler()` — PV3 creates the event with data as payload automatically.

### Command with invariants

```typescript
UpdateEntity: commandBuilder()
  .withSchema( UpdateCommandSchema )
  .withInvariant( invariants.stateExists() )
  .withIdempotencyCheck( idempotency.check() )
  .produces([ 'EntityUpdated' ])
  .withHandler( async( createEvent, state, data, { context }) => {
    return [createEvent( 'EntityUpdated', data, { metadata: { accountId: context?.user?.accountId }})];
  })
```

### Idempotency checks

`withIdempotencyCheck( idempotency.check( value1Fn, op, value2Fn? ) )` — declarative idempotency that skips the command silently (no event emitted) when the check passes. Prefer this over inline handler checks.

```typescript
// State exists — skip if aggregate already has state
.withIdempotencyCheck( idempotency.check(( state ) => state, 'exists' ))

// Value equality — skip if current value already matches target
.withIdempotencyCheck( idempotency.check(
  ({ state, data }) => state.warehouses[data.warehouseId]?.stock || 0,
  'eq',
  ({ data }) => data.stock
))
```

**Operators:** `'exists'` (value1 is truthy), `'eq'` (value1 === value2)

**Multi-stream exception:** `withIdempotencyCheck` is all-or-nothing — it can't make per-item decisions. For `multiStream` commands, use inline checks in the handler instead:

```typescript
SetMultipleItems: commandBuilder( multiStream( ports, 'itemId' ))
  .withHandler( async ( createEvent, state, data ) => {
    return data.flatMap(({ itemId, value }) => {
      const current = ( state || {} )[`Stream-${itemId}`];
      if ( current?.value === value ) return []; // per-item idempotency
      return [createEvent( 'ItemSet', { value }, { stream: `Stream-${itemId}` })];
    });
  })
```

### Bulk command + completion-event pattern

For spreadsheet-style bulk save flows, follow the unified pattern — N per-row events + 1 `*BulkOperationCompleted` event emitted in one event-store transaction, projector reacts only to the completion event:

```typescript
ApplyBulkItemsChange: commandBuilder( multiStream( ports, 'itemId' ))
  .withSchema( ApplyBulkItemsChangeCommandSchema )  // schema-cap maxItems: 2000
  .produces([ 'ItemRegistered', 'ItemEdited', 'ItemDeleted', 'ItemsBulkOperationCompleted' ])
  .withHandler( async ( createEvent, state, data, { context, metadata }) => {
    const accountId = context?.user?.accountId;
    const correlationId = metadata?.correlationId;
    const events = data.rows.flatMap(({ itemId, intent, payload }) => {
      const stream = `Items-${itemId}`;
      // per-row branching using state[stream] for register vs edit, etc.
      return [createEvent( intentToEventName( intent ), payload, { stream, metadata: { accountId }})];
    });
    // completion event on a per-correlation stream — single trigger for the projector
    events.push( createEvent( 'ItemsBulkOperationCompleted', { count: data.rows.length, accountId }, {
      stream: `ItemsBulkOperationCompleted-${correlationId}`,
      metadata: { accountId, correlationId }
    }));
    return events;
  })
```

Pair with a `ReducerNOOP` entry for the completion event (it lands on a per-correlation stream the aggregate doesn't reduce — see "Event namespace coverage" note (2) in [`ddd-patterns` → AGGREGATES.md](../ddd-patterns/AGGREGATES.md)).

**Two multi-stream shapes — pick by what state the handler needs:**

1. **Per-row-state shape — `commandBuilder( multiStream( ports, 'itemId' ))`** (e.g. items, stock). PV3 pre-loads N per-row snapshots (one batched query) because the handler diffs each row against its own per-row state (`state[`Stream-${itemId}`]`). Use when per-row state drives the emitted events.
2. **Single-parent-metadata shape — default load + `.withCommitFunction( multiStreamCommit )`** (e.g. a bulk change whose decision needs shared parent metadata such as a currency or locale). Keep PV3's **default aggregate load** (one cheap parent-stream read, e.g. `Parent-${id}`, for shared metadata + ownership) and override **only the commit** so per-event `stream` overrides survive into the event store. Use when the bulk decision needs *parent* metadata, not per-row state.

```typescript
ApplyBulkChildChange: commandBuilder()
  .withSchema( ApplyBulkChildChangeCommandSchema )   // maxItems: 2000
  .withInvariant( scopeInvariant() as any )
  .withInvariant( invariants.stateExists())          // real now — state is loaded
  .withCommitFunction( multiStreamCommit )           // overrides commit only; default load preserved
  .produces([ 'ChildItemChanged', 'ChildItemRemoved', 'BulkOperationCompleted' ])
  .withHandler( async ( createEvent, state, data, { metadata }) => {
    const currencyIsoCode = state!.currency;          // strongly-consistent parent metadata
    // …emit per-row events on `${id}::${itemId}` streams + one completion event…
  })
```

- `multiStreamCommit` is a ~30-line function (group events by per-event `stream`, `appendToMultipleStreams( streams, handlerState.transaction )`); copy it from an existing parent-metadata bulk aggregate in your repo. It composes with the default load because **PV3 ignores `withLoadFunction` for aggregates** — only the commit is swapped.
- For `scopeInvariant()`/`stateExists()` to be *real* (not stateless no-ops), the creation reducer must project the scoping fields onto state, e.g. `ParentCreated: ( _, event, metadata ) => ({ ...event, ownerId: metadata?.userId, accountId: metadata?.accountId })` — the aggregate state schema declares them optional.
- The command is atomic with a caller's transaction when invoked as `executeCommand( Aggregate( ports ), 'ApplyBulkChildChange', tx )` — `multiStreamCommit` honors `handlerState.transaction`.

**A streamable external system (`ExternalSystemBuilder(events, undefined, { isStreamable: true })`) is a possible substrate for bulk, but is usually the wrong choice.** Prefer aggregate-side commands for bulk editors. Reach for a streamable external system only for a genuinely stateless bulk case with no foreseeable invariants — but note that the "zero state-load" advantage is moot for bulk (one metadata load, not N per row) and is outweighed the moment any consumer needs read-your-writes state.


### Command producing multiple events

```typescript
PlaceOrder: commandBuilder()
  .withSchema( PlaceOrderCommandSchema )
  .produces([ 'OrderPlaced', 'OrderEdited', 'OrderStatusChanged' ])
  .withHandler( async( createEvent, state, data, { context }) => {
    const events: any[] = [];
    const accountId = data.accountId || context?.user?.accountId;

    if ( state ) {
      // Existing entity — emit edit events
      const diff = deepDiff( state, data );
      if ( Object.keys( diff ).length > 0 ) {
        events.push( createEvent( 'OrderEdited', diff, { metadata: { accountId }}));
      }
    } else {
      // New entity — emit created event
      events.push( createEvent( 'OrderPlaced', data, { metadata: { accountId }}));
    }

    return events;
  })
```

## Transactional Side-Writes (Advanced)

Command handlers receive a `transaction` parameter (4th arg) for ACID-transactional side-writes alongside event emission:

```typescript
DoSomething: commandBuilder()
  .withSchema( DoSomethingCommandSchema )
  .produces([ 'SomethingDone' ])
  .withHandler( async( createEvent, state, data, { context, transaction }) => {
    // Atomic side-write — rolls back if events roll back
    const col = transaction.getCollection( 'my_unique_constraints' );
    await col.upsert( data.email, { entityId: data.id });
    return [createEvent( 'SomethingDone', data, { metadata: { accountId: context?.user?.accountId }})];
  })
```

**When to use:** Uniqueness constraints, counters, scheduling state — any data requiring atomicity with the event store (not eventual consistency via readmodel).

**Reference:** Look at an existing aggregate with transactional side-writes under `<serverPath>/src/modules/` in your repo — e.g. a unique-email constraint, a scheduling `nextRunAt` side-write, or a monotonic sequence counter emitted via `atomicIncrement` on a dedicated counter collection.

**Anti-pattern: Redis `INCR` for monotonic document numbers.** A Redis counter is NOT transactional with the event store — under `appendfsync everysec` a Redis crash can regress the counter and reissue an already-used number. Gaps (a discarded draft burning a number) are tolerable; duplicates are not. For any "must-be-unique" sequence (e.g. document numbers, fiscal/legal numbering, receipt numbers), use the transactional DB counter pattern above. Counter increment lives in the handler that emits the *consumption* event (the one that finalizes/publishes the document, not the one that creates a draft) so discarded intermediates don't burn numbers.

## Scope Enforcement

All user-facing aggregates MUST include scope enforcement:

### scopeInvariant via withCommandTemplate

```typescript
import { scopeInvariant } from '<domainUtilsPackageName>';

AggregateBuilder( MySchema, MyEvents )
  .withCommandTemplate({ invariants: [scopeInvariant()] } as any)
```

This applies `scopeInvariant()` to ALL commands in the aggregate. It reads `context.user.permissionScopes` — a SET of `ScopeLevel`s — and OR-s the per-scope predicates against the aggregate state. The command passes if any granted scope authorizes it; throws `ForbiddenError` only when every scope in the set fails.

- Uses default config: `ownerIdField='ownerId'`
- Passes through when `context.user` is missing (system/policy calls)
- Passes through on creation (no existing state to check)

**When to skip:** Only skip for internal/system aggregates (auth sync, global config, reference data).

### ownerId in event reducers

Creation event reducers MUST capture `ownerId` from event metadata:

```typescript
EntityCreated: ( _, event, metadata ) => ({ ...event, ownerId: metadata?.userId }),
```

Note the third `metadata` parameter in the reducer — this is how PV3 passes event metadata to reducers.

### Aggregates with snapshot

For aggregates that already have `.withCommandTemplate( snapshot(...) )`, merge the invariants:

```typescript
.withCommandTemplate({ ...snapshot( ports, collection, N ), invariants: [scopeInvariant()] })
```

## Event Reducers

Reducers transform state based on events:

| Pattern | Use When |
|---------|----------|
| `( _, event, metadata ) => ({ ...event, ownerId: metadata?.userId })` | Creation event (captures owner) |
| `( state, event ) => ({ ...state, ...event })` | Merge event data into state |
| `deepMerge` | Deep merge (import from `@bett3r-dev/bett3r-utils`) |
| `( state ) => state` | Event doesn't change state (side-effect only) |

## Critical Constraints

- **No `.build()` call** — PV3 AggregateBuilder doesn't need it
- **No `.withStreamIdPrefix()`** — PV3 handles this differently
- **No `.withInitialState()`** — PV3 starts with `null` by default
- **No `.withDependencies()`** — Use ports closure instead
- **No controller file** — No `@AggregateController`, no `*.controller.ts`
- **No module file** — No `@Module`, no `*.module.ts`
- **No service file** — No `*.service.ts` wrapping the aggregate
- **Handler returns array** — Always return `[createEvent(...)]`, even for single events
- **Metadata accountId** — Always include `metadata: { accountId }` for multi-tenant tracking

## Imports

```typescript
import { AggregateBuilder, idempotency } from '@bett3r-dev/pv3';
import { scopeInvariant } from '<domainUtilsPackageName>';
import { omit } from 'ramda';
import { deepDiff, deepMerge } from '@bett3r-dev/bett3r-utils';
```

## Schema Import Convention

Aggregate and command schemas are defined in the domain package (`<domainEventsPackageName>`, in `*-integration.types.ts` files):

```typescript
// CORRECT — import directly from the domain package in server modules
import { MyAggregateSchema } from '<domainEventsPackageName>';
```

## Reference Files

Look at an existing aggregate under `<serverPath>/src/modules/` in your repo for a working reference — including one with multi-stream / bulk commands if you are scaffolding a bulk editor.

## Final Checklist

- [ ] File named `<entity>.aggregate.ts`
- [ ] Uses `AggregateBuilder( Schema, Events )` pattern
- [ ] **Factory signature is EXACTLY `( ports: Ports )` — never a second constructor argument.** The MDU/lift loader instantiates every artifact as `factory( ports )`; an injected arg is `undefined` in any lifted deployment unit. Single-consumer infra → a lazy library singleton reached via `getX( ports )`, never the global `Ports` type. See the `ddd-patterns` skill → "Artifact Constructor Signature — the MDU/Lift Contract".
- [ ] `.withCommandTemplate({ invariants: [scopeInvariant()] })` applied (unless internal/system aggregate)
- [ ] Creation event reducer captures `ownerId: metadata?.userId`
- [ ] Event reducers defined for all events
- [ ] Commands use `commandBuilder()` API
- [ ] `.produces([])` lists all possible events
- [ ] Handler returns array of events
- [ ] Metadata includes `accountId`
- [ ] No `.build()`, no controller, no module, no service
- [ ] Registered via `routeCommandHandler()` in `index.ts`
