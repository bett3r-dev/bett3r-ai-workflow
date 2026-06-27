---
description: PV3 DDD pattern reference — the framework conventions, gotchas, and hard-won lessons for aggregates, command handlers, policies, read models, schemas, module composition, the MDU/lift dependency model, and the outbox event-delivery ordering model (within-stream strict order, cross-stream at-least-once, the per-stream version watermark, consumer dedup/idempotency rules, and the `event.metadata.isRedelivery` operator-replay signal). Read when designing or implementing PV3 DDD artifacts (aggregates, policies, read models) or reasoning about event delivery/ordering, consumer redelivery, or replay handling.
---

# DDD Module Patterns (PV3)

When working in DDD modules, follow these PV3 patterns.

## Project configuration

This skill resolves the following placeholders from your repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>` | `domainEventsPackageName` | `@bett3r-dev/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |
| `<clientLibraryPackageName>` | `clientLibraryPackageName` | `@bett3r-dev/teselly-client-library` |
| `<domainUtilsPackageName>` | `domainUtilsPackageName` *(optional; defaults to `<domainEventsPackageName>` + `-utils`)* | `@bett3r-dev/teselly-domain-utils` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Aggregates

Use `AggregateBuilder` from `@bett3r-dev/pv3`:

```typescript
import { AggregateBuilder, idempotency } from '@bett3r-dev/pv3';
import { MyEvents, MySchema } from '<domainEventsPackageName>';
import { scopeInvariant } from '<domainUtilsPackageName>';
import { Ports } from 'ports';

export const MyAggregate = ( ports: Ports ) => {
  return AggregateBuilder( MySchema, MyEvents )
    .withCommandTemplate({ invariants: [scopeInvariant()] } as any)
    .withEventReducers({
      SomethingHappened: ( _, event, metadata ) => ({ ...event, ownerId: metadata?.userId }),
      SomethingEdited: ( state, event ) => ({ ...state, ...event })
    })
    .withCommands(({ commandBuilder }) => ({
      DoSomething: commandBuilder()
        .withSchema( DoSomethingCommandSchema )
        .produces([ 'SomethingHappened' ])
        .withHandler( async( createEvent, state, data, { context }) => {
          const accountId = data.accountId || context?.user?.accountId;
          return [createEvent( 'SomethingHappened', data, { metadata: { accountId }})];
        })
    }));
};
```

Command handlers return an array of events. No `.build()` call needed.

### CommandBuilder Options

```typescript
commandBuilder()
  .withSchema( CommandSchema )           // Validates input
  .withInvariant( invariants.stateExists() )  // Declarative invariant
  .withIdempotencyCheck( idempotency.check() ) // Prevent duplicates; supports: check(v1, 'exists'), check(v1, 'eq', v2)
  .produces([ 'EventA', 'EventB' ])      // Declare produced events
  .withHandler( async( createEvent, state, data, { context }) => {
    return [createEvent( 'EventA', payload, { metadata: { accountId }})];
  })
```

Commands without a `.withHandler()` produce a single event with data as payload.

### Client Library Typing

The client library (`<clientLibraryPackageName>`) is fully typed. Never use `any` for client library inputs or outputs. **Never cast command bodies as `as any`** (`body: { ... } as any`). If types don't match, either the type definitions are wrong (fix them) or the client library is stale (regenerate with `yarn generate-all`). Casting to `any` hides regressions silently and is never an acceptable resolution.

**In-process calls — no explicit auth headers:** When creating an in-process client library via `createBackend({ baseUrl: '' }, ports.endpoints.fetch)`, do NOT pass `x-auth-account-id` / `x-auth-user-id` as the third argument. The ALS-backed `setExecutionContextProvider` wired in `setupPorts.ts` injects them automatically. Explicit headers are redundant and misleading — ALS overwrites them when present. **Exception:** ALS only propagates within the same async context chain. Code that detaches (account-scoped ALS in a rules-execution policy, `setImmediate`, external pool callbacks) may need explicit headers — verify whether `setupPorts.ts` wires ALS for the calling context before removing them.

### Transactional Side-Writes

Command handlers receive a `transaction` parameter (4th arg: `{ context, transaction }`) that gives access to the event store's database transaction. Writes via `transaction.getCollection()` are atomic with the event store commit — if events roll back, side-writes roll back too.

```typescript
.withHandler( async( createEvent, state, data, { context, transaction }) => {
  const col = transaction.getCollection( 'my_side_table' );
  await col.upsert( data.id, { nextRunAt: computeNextRun( data.cronExpression ) });
  return [createEvent( 'EntityUpdated', data, { metadata: { accountId: context?.user?.accountId }})];
})
```

**When to use:** Uniqueness constraints, counters, scheduling state, or any data that must be consistent with the event store (not eventually consistent via readmodel projection).

**Example:** a unique-email side-write on a user/account aggregate; a `nextRunAt` scheduling side-write driven by a cron-tick system; or a monotonic sequence number (a fiscal/receipt/document number) assigned via `atomicIncrement` on a side-table counter row (`{ id: 'global', value: number }`) bumped under `FOR UPDATE` inside the transaction that emits the *consumption* event. Place the increment in the handler that emits the consumption event (e.g. the "publish"/"finalize" command), not the draft handler, so discarded drafts don't burn a number.

**Anti-pattern: Redis `INCR` for must-be-unique monotonic numbers** (fiscal numbers, receipt numbers, document/sequence numbers). Redis `INCR` is not transactional with the event store; under `appendfsync everysec` a Redis crash can regress the counter and reissue an already-used number. Gaps are tolerable; duplicates are not. Use the transactional DB counter above.

**IMPORTANT:** `.produces([])` (empty array) crashes PV3's `getCommandSchemas` during endpoint registration. For side-effect-only commands that emit no events, declare at least one possible event (e.g., `.produces(['SomeEvent'])`) and return `[]` from the handler. The handler is not required to emit all declared events.

**Event namespace coverage:** `withEventReducers` must list every event in the namespace passed to `AggregateBuilder( schema, namespace )`. Two paths:

1. **Declare a subset at builder time** *(preferred when an aggregate only cares about a slice of a larger namespace)*. PV3 accepts a subset object the same way `PolicyBuilder({ SomethingHappened })` does:
   ```typescript
   const { ThingCreated, ThingUpdated, ThingDeleted } = ThingsEvents;
   AggregateBuilder( ThingAggregateSchema, { ThingCreated, ThingUpdated, ThingDeleted })
     .withEventReducers({
       ThingCreated: ...,
       ThingUpdated: ...,
       ThingDeleted: ...
     });
   ```
   No no-op stubs needed for per-row events the aggregate never sees on its own stream.

2. **Use `ReducerNOOP` (from `@bett3r-dev/pv3-types`)** *when the aggregate must declare the full namespace* — typically because it emits an event in the namespace from a multi-stream command and the event lands on a stream the aggregate doesn't reduce (e.g., a `BulkOperationCompleted` event on a per-correlation stream). PV3 still requires a reducer entry for the produce-declaration check; `ReducerNOOP` is a no-op (`state => state`) and signals "this event is produced but not reduced":
   ```typescript
   .withEventReducers({
     ThingRegistered: ...,
     ThingEdited: ...,
     BulkOperationCompleted: ReducerNOOP
   })
   ```

Prefer (1) when possible — it's load-bearing documentation of which events the aggregate is interested in. Reach for (2) only when the aggregate emits the event itself.

**Event-only metadata fields:** When an event carries a field intended for downstream projectors (e.g., `totalInBatch` for a batch-progress readmodel) but not for the aggregate's own state, do **not** rely on `{ ...event }` in the reducer — that silently leaks the field into state and either fails strict schema validation or quietly diverges from `AggregateSchema`. Destructure the event-only field out before spreading:

```typescript
SomethingStarted: ( _, event, metadata ) => {
  const { totalInBatch, ...stateData } = event;  // strip event-only field
  return { ...stateData, ownerId: metadata?.userId };
}
```

**System/infrastructure aggregates:** Global infrastructure aggregates (cronjob subscriptions, feature flags, global config) can skip `scopeInvariant()`, `ownerId` in reducers, and `accountId` in event metadata. Their readmodels skip `FilterByAccountIdTransformer` and `FilterByScopeTransformer`. These are admin-only resources, not tenant-scoped. Enforce access via route-config (`private`, no subdomain).

**Admin-only domain aggregates:** A domain aggregate that lives inside a named module directory but must still be admin-only explicitly emits an empty subdomain via `.withSubdomain( '' )` on the aggregate/readmodel builder. This overrides the filesystem auto-derivation, so the generated routes carry no `x-subdomain` and the gateway authorizes them via the admin path (`userType === 'admin'`) instead of org feature-entitlement + permission. The subdomain's block must be **absent** from `permissions-catalog.json` (an orphaned block fails the `generate-all` drift check). Every route in such a module must call `.withSubdomain( '' )`.

**Document-aggregate lifecycle status guards (defence-in-depth).** A document-shaped aggregate (any aggregate whose lifecycle is a status state machine) typically has a status field driving a state machine — e.g. `draft → published → completed/failed`, or `draft → published`/`canceled`. **Every command that transitions or operates on a status MUST throw a status-mismatch `BadRequestError` when called in the wrong state** — not as a numbered domain invariant, but as a defence-in-depth guard against a caller (or a future bug) issuing a command out of order. Without it, a `draft` document can be transitioned straight to `completed` (skipping `published` — and therefore skipping any transactional sequence-number assignment that fires at publish); a `canceled` document can be reversed; a duplicate or wrong-state callback can corrupt the stream. Idempotency checks cover the *duplicate* case (same external transaction id again); these guards cover the *wrong-state* case (different transaction id, wrong prior status).

Pattern: emit one `*_NOT_*` SCREAMING_SNAKE error code per guard (e.g. an immutability code on an already-published document, plus codes like `DOCUMENT_NOT_DRAFT`, `DOCUMENT_NOT_PUBLISHED`, `DOCUMENT_NOT_CANCELABLE`, `DOCUMENT_NOT_REVERSIBLE`). These error codes are part of the documented error contract even though they are not numbered invariants in the spec.

```typescript
FinalizeDocument: commandBuilder()
  .withSchema( FinalizeDocumentCommandSchema )
  .withInvariant( invariants.stateExists( ... ))               // INV-12
  .withIdempotencyCheck( idempotency.check( duplicateCallbackCheck, 'eq', () => true ))  // D18
  .produces([ 'DocumentFinalized', 'DocumentFailed' ])
  .withHandler( async ( createEvent, state, data ) => {
    if ( state.status !== 'published' ) {
      throw new BadRequestError(
        'Only a published document can take a finalize outcome',
        'DOCUMENT_NOT_PUBLISHED',
        { documentId: state.documentId, status: state.status }
      );
    }
    // ... emit event ...
  })
```

The **happy-path + state-rejection pair** is a required test fixture for every status-guarded command.

**Idempotency-predicate null-safety.** PV3 evaluates `withIdempotencyCheck` predicates **before** `withInvariant( invariants.stateExists() )`. A predicate that dereferences `state` must therefore null-guard, regardless of whether the same command also declares a `stateExists` invariant — the invariant fires *after* the predicate ran, too late to protect it. The bug shape is a one-character omission that throws `TypeError: Cannot read properties of null (reading 'status')` from inside PV3, surfacing as an opaque internal error rather than the expected `STATE_NOT_FOUND`:

```typescript
RetryDocument: commandBuilder()
  .withSchema( RetryDocumentCommandSchema )
  .withInvariant( invariants.stateExists( ... ))                  // fires LATER
  .withIdempotencyCheck( idempotency.check(
    ({ state }) => state?.status === 'published',                 // ← optional chaining is REQUIRED
    'eq',
    () => true
  ))
  .withHandler( ... )
```

**Required regression-test fixture.** Every command with a state-reading idempotency predicate MUST have a "Given the command on a non-existent stream / then INV-12 / stateExists throws `STATE_NOT_FOUND`" test. Without it the null-deref hides behind the happy path.

**Mutual-exclusion lock via UNIQUE-constraint side-write.** A counterpart to the sibling monotonic counter pattern above. When a domain invariant requires **at most one in-flight operation** on a key (e.g. one in-flight operation per `lockKey`), use a side-table with a `UNIQUE` constraint on the key, `insert`-ed inside the event-store transaction at the **acquiring** command and `delete`-by-pk-ed inside the event-store transaction of each terminal handler. The acquire is gated by an optional "lock-identity" parameter so non-locked dispatches of the same command (admin / one-off) bypass the lock entirely. A `UNIQUE_VIOLATION` re-throws as a domain `BadRequestError` with a stable error code (`OPERATION_IN_PROGRESS`) and rolls back the events. Release-by-pk is idempotent (a missing row is fine), so duplicate terminal events are safe.

```typescript
CreateDraft: commandBuilder()
  .withSchema( CreateDraftCommandSchema )
  .produces([ 'DraftCreated' ])
  .withHandler( async( createEvent, state, data, { transaction }) => {
    if ( data.runId ) {
      const lockCol = transaction!.getCollection(
        'operation_lock',                                 // UNIQUE(lockKey)
        'lockKey'
      );
      try {
        await lockCol.createMany([{
          lockKey: data.lockKey,
          documentId: data.documentId,
          runId: data.runId,
          acquiredAt: new Date().toISOString()
        }]);
      } catch ( e ) {
        if ( isUniqueViolation( e )) {
          throw new BadRequestError(
            'An operation is already in progress for this key',
            'OPERATION_IN_PROGRESS',
            { lockKey: data.lockKey }
          );
        }
        throw e;
      }
    }
    return [createEvent( 'DraftCreated', data, { metadata: { ... }})];
  })

// Release — mirror in every terminal handler, gated by the persisted lock-identity.
DocumentCompleted: commandBuilder()
  .withHandler( async( createEvent, state, data, { transaction }) => {
    if ( state.runId ) {
      await transaction!.getCollection( 'operation_lock', 'lockKey' )
        .destroyById( state.lockKey );                     // idempotent — missing row is fine
    }
    return [createEvent( 'DocumentCompleted', ..., { ... })];
  })
```

**Rules:**

1. **`createMany` / `destroyById` are the PV3 APIs**, not `insert` / `delete` (the latter are pseudocode in older specs). `destroyById` accepts the primary-key value directly.
2. **Persist the lock-identity on state** so terminal handlers know whether to release. The lock-identity (`runId`) is reduced from the acquiring event.
3. **Every terminal status MUST release** — every terminal handler (`DocumentCompleted`, `DocumentFailed`, `DraftCanceled`, `Cancel`) must release. A handler that transitions to a terminal status but forgets to release is the canonical "stuck lock" bug.
4. **Re-acquire on legitimate re-entry.** A retry command coming after a failure event (which released the lock) MUST re-acquire it — otherwise the at-most-one invariant is violated across the cron/retry race window.
5. **Orphan-sweep is the operational follow-up.** If a policy crashes between acquire and any terminal event, the lock row persists; a periodic sweep is the eventual fix. A reasonable mitigation is the run policy's top-level try/catch + compensating cancel.
6. **Test fixture: conflict + release pair.** Required regression tests — (a) "Given a draft exists for this key / when a second `CreateDraft` with the same `runId` is dispatched / then `OPERATION_IN_PROGRESS` and no event is emitted" using a fake collection that surfaces `UNIQUE_VIOLATION`; (b) "Given a draft with `runId` / when `DocumentCompleted` commits / then the lock row is gone" — one per terminal handler.

See the sibling monotonic counter pattern above for the related transactional side-write technique.

### Registration

```typescript
ports.eventsourcing.routeCommandHandler( MyAggregate( ports ));
```

Look at an existing aggregate under `<serverPath>/src/modules/` in your repo for a working reference.

## Schemas

Use `@bett3r-dev/jsonschema-definer` (imported as `S`):

```typescript
import S, { omitFromSchema } from '@bett3r-dev/jsonschema-definer';

export const MyCreatedEventSchema = S.shape({
  name: S.string(),
  count: S.number().minimum( 0 ),
  status: S.string().optional()
});
export const MyEditedEventSchema = MyCreatedEventSchema.partial();
```

Type extraction: `typeof Schema.type` (not `z.infer<>`).
Use `omitFromSchema( Schema, ['field'] )` (not `.omit()`).

### Schema File Layout

Domain schemas are split across two files in the domain package (`<domainEventsPackageName>`):

| File | Contains | Example |
|------|----------|---------|
| `<domain>.types.ts` | Event schemas, value objects | `<domain>.types.ts` |
| `<domain>-integration.types.ts` | Aggregate state, command, readmodel schemas | `<domain>-integration.types.ts` |

Look at an existing domain folder under `<domainEventsPath>/src/` in your repo for a working reference.

## Events

Events are factory functions with schema and friendlyName:

```typescript
import { Event } from '@bett3r-dev/pv3-types';

export const SomethingHappened = () => Event({
  schema: SomethingHappenedEventSchema,
  friendlyName: {
    es: 'Algo sucedio',
    en: 'Something happened',
    pt: 'Algo aconteceu'
  }
});
```

Location: `<domainEventsPath>/src/<domain>/<entity>.events.ts`

Look at an existing `*.events.ts` file under `<domainEventsPath>/src/` in your repo for a working reference.

## Event delivery ordering: within-stream strict order, cross-stream at-least-once

**Hard constraint — how the outbox delivers events.** The outbox **never reorders events within a single stream — full stop.** Not in normal operation, not during gap recovery, not on operator replay. What a consumer *does* face is **at-least-once** delivery: any event can arrive again. Two facts every consumer author must internalize:

**1. Within a stream: strict version order, always.** Four independent reasons it cannot reorder:
- A stream's events have **monotonic version = monotonic position**. Optimistic concurrency forces it: to write `v+1` you must have loaded `v`, so `v` commits *before* `v+1` is even written.
- A stream always routes to **one split**, dispatched position-ordered through a **concurrency-1 queue**.
- **Gap recovery cannot reorder a stream.** A gap (a lower position still uncommitted while a higher one is visible) is *only ever cross-stream* — a stream's own later versions commit after its earlier ones, so they are never visible or dispatched ahead of them.
- **Operator reposition cannot reorder.** It re-pulls a range in position order, so it produces *duplicates*, never out-of-order.

**2. Cross-stream / global position: no order guarantee.** Commit-visibility races and gap recovery *deliberately* deliver a cross-stream-late position after newer ones. Never assume global order.

**At-least-once — the full set of duplicate causes.** "Resent only when the outbox couldn't store the ACK" is the headline case, not the only one. The ACK can be lost at *two* layers — the Redis dispatched-bit **and** the HTTP response — and an operator can replay on purpose:

| # | Cause | Present in single-replica topology? |
|---|-------|-------------------------------------|
| a | Crash/interruption **after a successful send, before the `SETBIT`** → re-dispatched on recovery | Yes |
| b | Send the outbox **saw as failed** (timeout / 5xx) but the consumer **actually processed** it (lost HTTP response, not the bitmap) → retried | Yes |
| c | **Operator replay** — admin "Set Single Data Split Position" with `reprocess: true` | Yes, on demand |
| d | Cross-process **zombie / partition owner** (no fencing) | Not at 1 replica — but it's the contract *before* scale-out |

**What you do NOT need to handle:** duplicates from watchdog/coordinator re-pulls or gap-recovery re-pulls of already-delivered events. The **dispatched bitmap absorbs those** (`reprocess: false`) before they ever reach you. The duplicates that *do* reach a consumer are (a)–(d).

### The one rule that matters most: dedup per-stream on version, NEVER on global position

Deduplicate **per-stream, keyed on `version`** (or the event id) — **never** on global position.

This is the trap: because cross-stream global order is not guaranteed, a global "skip if `position ≤ last seen`" high-water mark will **drop exactly the gap-recovered events** (a legitimately cross-stream-late position arriving after newer ones) — silently re-creating a dropped-event bug. The discipline:

- Track a **per-stream last-applied version** (a watermark per stream).
- Incoming `version ≤ lastApplied[stream]` → **duplicate → skip**, but **return 2xx**. Returning an error makes the outbox retry → retry storm; a 2xx lets it set the dispatched bit and stop.
- Otherwise **apply and advance** the per-stream watermark.

Because per-stream order is guaranteed, the watermark is *sufficient* — you never need to remember every event id, just the last version per stream. A within-stream gap (`version > lastApplied + 1`) should never appear; if it does, it signals a bug or deduping on the wrong key, **not** a reordering you must tolerate.

`upsert` keyed by stream id gives *idempotency* (writing the same row twice is safe); the watermark additionally protects *observable effects* a duplicate would corrupt (see read models below). The two are independent.

### In-process PV3 consumers get this for free

**`ReadmodelBuilder` applies the per-stream version watermark internally** — the exact model above — so an in-process PV3 read model is dedup-safe by construction. **Custom / external consumers (HTTP webhooks, non-PV3 services) must replicate it themselves.**

**Read models.** Project a stream's events in version order (the framework guarantees the order and dedups duplicates via its internal watermark). A pure last-write-wins `upsert` keyed by the stream id is self-healing under duplicate redelivery — applying the same head event twice is idempotent. The watermark is *strictly* load-bearing when the projection is **non-convergent**: it appends to an array, increments/accumulates, or exposes intermediate state observable between deliveries — there a re-applied duplicate corrupts the result. The framework's watermark covers in-process read models; a custom projector must carry its own.

**Policies — case-by-case.** Within-stream order is guaranteed, so a policy never sees a stream's events reordered. What it *must* survive is **duplicate redelivery**:
- **Idempotent reaction** — re-applying the same event is a no-op (most reactions, especially idempotent per-event side effects). Nothing extra needed; let the outbox redeliver freely.
- **Non-idempotent reaction** — re-applying changes the outcome (accumulates, or fires a per-transition side effect). The policy MUST make each dispatched command idempotent (see *Policies* below) **or** hold a per-stream watermark/side-table to dedup — and must never assume **cross-stream** order.

This is the counterpart to the redelivery-safety rules in the *Policies* section below: redelivery-safety makes a handler *idempotent* under replay; the watermark makes a *dedup-requiring* handler correct under at-least-once delivery.

### Non-idempotent external side effects

If processing an event triggers a real-world action (charge a card, `createShipment`, send an email), the per-stream watermark must be committed **atomically with the side effect**, or the side effect must **carry its own idempotency key** (natural key + `ON CONFLICT DO NOTHING`, or a provider idempotency-key). Otherwise cases (a)/(b) double-fire it. This is the load-bearing work tracked as **TV1-1945**, and the flag below does **not** change it. For the *narrower* "don't re-send the shipped email when an operator replays a position we already produced" case, read `event.metadata.isRedelivery` — specified next.

### `event.metadata.isRedelivery` — the operator-replay signal (what it is, what it is NOT)

Every dispatched event carries `event.metadata.isRedelivery: boolean`. A consumer reads it straight off the metadata it already receives — **there is no new handler API**; PV3 `ReadmodelBuilder` and policy handlers already get `event.metadata`. The flag is **off by default** (absent / `false`) and is stamped `true` in exactly one situation:

> `isRedelivery === true` **iff the dispatched bit was already set at the moment the outbox decided to send this position** — i.e. a position that was previously **delivered *and* committed** (its ACK landed, so the bit is set) is being sent again. The only path that re-sends an already-committed position is the admin **"Set Single Data Split Position"** replay (`shouldReprocess` / `reprocess: true`, cause (c) above).

That makes it **false-positive-free: it is never set on a genuine first delivery.**

| Delivery path | dispatched bit when outbox decides | `isRedelivery` |
|---|---|---|
| Normal first delivery | 0 | `false` |
| Crash-before-commit re-dispatch (cause (a)) | 0 | `false` |
| Lost-HTTP-response retry (cause (b)) | 0 | `false` |
| **Operator replay of an already-committed position (cause (c))** | **1** | **`true`** |

**What it IS for.** A consumer can safely **suppress a non-idempotent side effect on a replay** — the "we already shipped; don't re-send the shipped email" case. Because the flag never fires on a real first delivery, suppressing on `isRedelivery` can **never drop a first-time effect**. Both meanings of a set flag ("recovery wanted to re-run" vs "operator asked to reprocess") collapse to the same instruction for this use case: *you have produced this before → suppress*. The original event object is **not mutated** — the flag is added to the dispatched copy's metadata only.

**What it is NOT.** It is **not a dedup primitive and not exactly-once.** It is deliberately **silent on the crash/retry redelivery paths** (causes (a) and (b)): those dispatch with the bit still `0`, so they are indistinguishable from a first delivery and arrive with `isRedelivery: false`. A consumer needing *absolute* exactly-once side effects must still dedup on **`(stream, version)` / event id**, with the effect committed atomically (or carrying its own idempotency key) — that is TV1-1945, unchanged by this flag. A single boolean also cannot distinguish "recovery redelivery" from "operator wants a reprocess"; for the suppress-side-effect use case that distinction does not matter.

**Decision rule.**
- Need to *drop duplicates correctly in all cases* → **per-stream version watermark** (above). `isRedelivery` does not help here — it's `false` on causes (a)/(b).
- Need only to *avoid re-emitting a non-idempotent effect on an operator replay* → **`event.metadata.isRedelivery`**.
- Need both → do both; they compose (watermark for correctness, flag for the replay-suppress shortcut).

### TL;DR for a consumer author

1. **Assume at-least-once** — the same event can arrive again (crash-before-bit, lost HTTP response, operator replay, future scale-out).
2. **Rely on per-stream order** (guaranteed); **never assume cross-stream / global order.**
3. **Dedup with a per-stream version watermark, not a global position** — and **2xx duplicates** (an error triggers a retry storm).
4. **Make external side effects idempotent** — commit the watermark *with* the effect, or use a dedup key.
5. **`event.metadata.isRedelivery` is a replay *hint*, not dedup.** `true` marks an operator replay of an already-committed position (cause (c)) **only** — use it to suppress re-firing a non-idempotent effect (it never fires on a first delivery, so it can't drop one). It is `false` on crash/retry redelivery (causes (a)/(b)), so it does **not** replace the watermark or `(stream, version)` dedup.

## Policies

Use `PolicyBuilder` from PV3:

```typescript
import { extractIdFromEventStream } from '@bett3r-dev/pv3';
import { MyEvents } from '<domainEventsPackageName>';
import { Ports } from 'ports';

export const MyPolicy = ( ports: Ports ) => {
  const { SomethingHappened } = MyEvents;

  return ports.eventsourcing.PolicyBuilder({ SomethingHappened })
    .withEventHandlers(() => ({
      SomethingHappened: async ( event ) => {
        const id = extractIdFromEventStream( event );
        // Execute side effects, create commands, etc.
      }
    }));
};
```

- Use `extractIdFromEventStream( event )` for stream IDs
- Always pass `correlationId` and `causationId` for tracing
- For cross-service commands, use the client library (`<clientLibraryPackageName>`)

### Partial-progress redelivery: derive policy progress from aggregate state

When a policy handler dispatches **N commands in a loop and then one wrap-up command** (e.g. it allocates an amount across N targets then creates a residual record for any leftover), it is **subject to outbox redelivery mid-progress** — any throw between commands leaves the handler restartable. Idempotency on each dispatched command is necessary but **not sufficient**: the policy's *local* accounting (a `remaining` counter, a "what's left to do" computation) must agree with the aggregate's recorded progress byte-for-byte, or the wrap-up command sees the wrong residual.

**The bug class:** a policy that recomputes `remaining` by **re-walking live downstream state** (a target's current balance, a counter on a sibling readmodel) silently disagrees with the aggregate's recorded `applications[]` / `postings[]` after a partial run. Already-settled targets report `outstanding = 0` on the redelivery; the loop hits `continue` *without decrementing `remaining`*, the wrap-up command fires for the full original amount, and the result inflates by Σ already-applied. The aggregate's identity-only idempotency on the per-target commands no-ops them, but the wrap-up command — keyed on the *event id*, not on the per-target identity — commits fresh.

**The fix shape:** seed `remaining` from the **source aggregate's recorded progress** (e.g. `record.applications[]`), and skip plan entries whose identity already appears in that progress. Live downstream balances are still read for the *per-iteration cap* (`min(remaining, target.outstanding)`), but never as the source of "what's left".

```typescript
SomethingCollected: async ( event ) => {
  const record = await sourceCollection.readById( extractIdFromEventStream( event ));
  // ...projection-lag throw...

  // Seed `remaining` from the aggregate's own recorded progress — NOT from
  // re-walking live target outstanding. Byte-for-byte agreement under
  // redelivery: a target settled by a prior run reports outstanding=0, but
  // its allocation is in `applications[]` so the entry is *skipped*, and
  // `remaining` is *not* re-walked-against-zero.
  const priorApplications = record.applications || [];
  const appliedTargetKeys = new Set(
    priorApplications.map( a => `${a.targetType}:${a.targetId}` )
  );
  const alreadyAppliedAmount = priorApplications.reduce(( s, a ) => s + a.amount.amount, 0 );
  let remaining = record.amount.amount - alreadyAppliedAmount;

  for ( const planEntry of record.allocationPlan || []) {
    if ( remaining <= 0 ) break;
    const key = `${planEntry.targetType}:${planEntry.targetId}`;
    if ( appliedTargetKeys.has( key )) continue;  // already applied on a prior run

    const outstanding = await liveOutstanding( planEntry );    // per-iteration cap only
    const allocationAmount = Math.min( remaining, outstanding );
    if ( allocationAmount <= 0 ) continue;
    await executeCommand( ..., 'ApplyAllocation' )({ ... });
    remaining -= allocationAmount;
  }

  if ( remaining > 0 ) {
    const residualId = deterministicResidualId( event.id );      // stable across redelivery
    await executeCommand( ..., 'CreateResidual' )({ ... }).catch( swallowStateExists );
  }
}
```

**When this applies.** Any policy whose handler dispatches a per-item loop plus a final wrap-up command, AND whose item-level commands record into a source-aggregate collection (`applications[]`, `postings[]`, …) the policy can read back. Per-item idempotency keyed on `(sourceId, targetId)` is required but not sufficient — the wrap-up's amount comes from the policy's local accounting, which must be derived from the aggregate's recorded progress.

**Regression test required.** Any such policy MUST have a test under "Given <TriggerEvent> REDELIVERY with prior-run applications already recorded": fixture the source readmodel with 1+ allocations and the plan re-including those targets, assert the redelivered event yields `wrap-up(amount − Σapplied)`, not `wrap-up(amount)`.

Look at an existing wrap-up-after-loop policy under `<serverPath>/src/modules/` in your repo for the reference shape.

### Multi-command fan-out must be replay-safe

A policy handler that dispatches **more than one command** — a fan-out loop (N `RemoveChildMember` + a `DeleteParent`) or a sequence of distinct commands — is **redelivery-restartable**: any throw between dispatches leaves the handler restartable from the top, and the outbox will redeliver the trigger event. Therefore **every command the handler dispatches MUST be idempotent on replay**, via `withIdempotencyCheck` or a handler that no-ops the already-applied case — OR the policy must track progress in a watermark/side-table.

**Default to per-command idempotency.** Reach for a watermark only when per-item progress cannot be derived from aggregate/readmodel state (this is the heavier `Partial-progress redelivery` case above).

**Soft-delete trap:** `stateExists` (`invariants.stateExists()`) does **NOT** protect a soft-deleted aggregate. A soft delete (`mergeLeft({ isDeleted: true })`) leaves state non-null, so `stateExists` never throws `STATE_NOT_EXISTS` and a non-idempotent terminal command **re-emits its event** on redelivery (re-firing every downstream consumer) instead of erroring — invisible to the happy path and to tests that don't simulate redelivery. A delete/terminal command on a soft-delete aggregate needs its **own** idempotency guard keyed on `state?.isDeleted`, not `stateExists`.

**Regression test required:** a "redelivery after partial progress" test asserting the second delivery of the trigger event emits **zero** duplicate events.

Look at an existing fan-out erasure/cleanup policy under `<serverPath>/src/modules/` in your repo for the reference shape.

### Dependency Declaration

Every policy must declare its aggregate dependency for deployment unit computation. Build error if missing.

```typescript
// Auto-detected: pass aggregate as 2nd param (createCommand pattern)
PolicyBuilder({ SomethingHappened }, TargetAggregate( ports ))
  .withEventHandlers(({ createCommand }) => ({ ... }));

// Manual: executeCommand policies that target aggregates imperatively
PolicyBuilder({ SomethingHappened })
  .linkedTo( 'AggregateA', 'AggregateB' )
  .withEventHandlers(() => ({ ... }));

// Standalone: side-effect-only policies (email, webhooks, external APIs)
PolicyBuilder({ SomethingHappened })
  .standalone()
  .withEventHandlers(() => ({ ... }));
```

### Policy Placement

A policy belongs in the **subdomain whose state it changes**, not in the subdomain that emits the trigger event.

**Rule:** If the policy's `createCommand` (or `executeCommand`) targets aggregate X, the policy file lives in X's module directory. Colocating a policy with its *trigger event source* is the canonical misplacement.

**Correct-placement check:** Does the policy call `createCommand`/`executeCommand` on an aggregate in the same module folder? If yes, placement is correct. If no, move the policy to the aggregate's module. Cross-module reactions import the source event's *schema* (always allowed via the domain package, `<domainEventsPackageName>`), not the source module's implementation.

*Example:* A policy reacting to `Identity/UserAccountAdded` to provision a resource owned by another module belongs in that other module's directory, not in `src/modules/identity/`.

### ACL Systems and `produces` Declarations

The `produces` array on any handler must **only list events the handler itself writes to the event store** — never downstream side-effects from aggregate commands the handler dispatches.

**Canonical gateway ACL two-step pattern:**

1. The gateway system emits a **raw gateway event** (e.g. `GatewayCallbackReceived`) capturing the external payload verbatim.
2. A **separate policy** reacts to that raw event and dispatches the aggregate command (e.g. `RecordCallbackOutcome`), which emits the domain event.

A gateway system handler that calls `executeCommand(SomeAggregate, 'DoSomething')` and returns `[]` must NOT list the downstream aggregate's events in `produces`. Those events belong to a different aggregate's stream. Declare an empty or omitted `produces` for side-effect-only handlers.

### Registration

```typescript
ports.eventsourcing.routeEventHandler( MyPolicy( ports ));
```

Look at an existing policy under `<serverPath>/src/modules/` in your repo for a working reference.

## Read Models

Use `ReadmodelBuilder` from PV3 — all inline, no separate service:

```typescript
import S from '@bett3r-dev/jsonschema-definer';
import { extractIdFromEventStream, ReadmodelBuilder } from '@bett3r-dev/pv3';
import { defaultQuerySchemas, UnauthorizedError } from '@bett3r-dev/pv3-types';
import { FilterByAccountIdTransformer, FilterByScopeTransformer } from '<domainUtilsPackageName>';
import { Ports } from 'ports';

export const MyReadmodel = ({ database, realtimeSession, databaseSessionMode }: Ports, collection = 'domain_entity_readmodel' ) => {
  const myCollection = database.getCollection<MyType>( collection, 'id' );

  database.onStarted( async () => {
    await myCollection.ensureIndex(['id']);
  });

  const { SomethingHappened, SomethingEdited } = MyEvents;

  return ReadmodelBuilder( MyReadmodelSchema, { SomethingHappened, SomethingEdited })
    .withDatabase( database, collection, databaseSessionMode )
    .withProjector(() => ({
      SomethingHappened: async ( event ) => {
        return myCollection.upsert( extractIdFromEventStream( event ), {
          ...( event.data as any ),
          accountId: event.metadata.accountId,
          ownerId: event.metadata?.userId
        });
      },
      SomethingEdited: async ( event ) => {
        return myCollection.upsert( extractIdFromEventStream( event ), event.data as any );
      }
    }))
    .withQuery({
      route: '/domain/entities/:id?',
      transformers: [FilterByAccountIdTransformer( false ), FilterByScopeTransformer()],
      subscriptions: [realtimeSession.readmodelSubscription]
    })
    .withQuery({
      route: '/domain/entities-search/:search?',
      schemas: {
        query: defaultQuerySchemas.query,
        params: S.shape({ search: S.string().optional() }),
        response: S.shape({
          items: S.array().items( MyReadmodelSchema ),
          count: S.number()
        })
      },
      transformers: [FilterByAccountIdTransformer(), FilterByScopeTransformer()],
      queryHandler: async ( _, params ) => {
        const { context: { user }} = params.params;
        if ( !user ) throw new UnauthorizedError( 'User must be authenticated' );
        const count = await myCollection.count({ filter: params.filter });
        const response = await myCollection.query({
          filter: params.filter,
          limit: params.limit,
          offset: Number( params.offset ) || 0,
          sort: [{ field: 'id', direction: 'asc' }]
        });
        return { items: response || [], count };
      }
    });
};
```

- Use `upsert` for idempotency (never `insert`)
- `extractIdFromEventStream( event )` for document IDs
- `FilterByAccountIdTransformer()` for multi-tenant filtering
- `FilterByScopeTransformer()` for permission-based scope filtering (always add AFTER `FilterByAccountIdTransformer`)
- Project `ownerId: event.metadata?.userId` in creation event projectors
- Collection names: `{domain}_{entity}_readmodel`

### Subdomain assignment reflects domain ownership

A readmodel's `.withSubdomain('X')` declaration must reflect **the domain the data conceptually belongs to** — never chosen for authorization convenience or to avoid a permissions-catalog/registry diff. The subdomain declaration and the file's module location must **agree**: a readmodel living in `identity/` must not declare `.withSubdomain('some-other-subdomain')` just to reuse that subdomain's capability gate. If the right gate doesn't exist yet, add the registry entry under the correct subdomain — don't borrow another's.

### Subscriptions require `databaseSessionMode`

If a `.withQuery({ ... })` declares `subscriptions: [...]`, you **MUST** pass `databaseSessionMode` as the **third** argument to `.withDatabase( database, collection, databaseSessionMode )` (destructure it from `Ports`). That third arg is what wires the collection change-stream `watch([...])` powering live deltas. The two-arg form **compiles and serves the initial subscription snapshot**, so the omission fails silently: projection works, reads work, only live push is dead — subscribers update only on a full page refresh.

**A `204` response to a subscription request is NORMAL**, not a failure: the snapshot and deltas go over the realtime channel (`manager.send`), not the HTTP body. Do not misdiagnose a 204 as a broken subscription.

### Cross-subdomain reads go through the client library

Never read **another subdomain's** readmodel by `ports.database.getCollection('<other-subdomain>_*_readmodel')`. A readmodel's backing table/collection is **private to its owning subdomain** — its name, document-id shape, and row schema are not a public contract; binding to them means the owner can't rename/reshape/relocate without silently breaking the consumer. A readmodel's `getCollection` accessor is for that readmodel's **own** projectors and queries only.

Cross-subdomain reads use the in-process client library against the readmodel's **published query endpoint** (`backend.queries.X`), exactly as cross-module commands go through the client library (and exactly as the no-cross-module-`executeCommand` rule requires for writes). **Red flag:** a `getCollection('<name>')` inside module `A/` whose `<name>` is prefixed with a different subdomain.

### Readmodel Schema Location

Readmodel schemas MUST be defined in the domain package (`<domainEventsPackageName>`, in `<domain>-integration.types.ts`), not inline in the readmodel file. The client library generator and OpenAPI spec derive types from the domain package. Inline schemas produce untyped or incomplete generated artifacts.

### Cross-stream counters (multi-stream keyed readmodel)

PV3's per-stream in-order guarantee protects same-stream writes (always, in order — see *Event delivery ordering* above; within a stream the outbox never reorders, though it may redeliver duplicates, which is why a non-convergent same-stream projection still needs the version watermark). It does **NOT** protect a readmodel whose key (e.g., `correlationId`) groups events from many aggregate streams — both because cross-stream order is *not* guaranteed and because a read-then-write counter under that shape is a classic lost-update race.

**Pattern:** atomic increment + CAS-filtered status write.

```typescript
RuleExecutionCompleted: async ( event ) => {
  const correlationId = event.metadata?.correlationId;
  if ( !correlationId ) return;

  // 1. DB-native atomic increment (PG: SELECT … FOR UPDATE; Mongo: $inc)
  const updated = await coll.atomicIncrement( correlationId, { completed: 1 });
  if ( !updated ) return;

  const { completed, failed, total } = updated;
  const status = computeStatus( completed, failed, total );

  // 2. CAS the status: only write if counts haven't drifted since our read.
  // A stale projector view can no longer regress a freshly-written status.
  await coll.updateMany(
    { id: correlationId, completed, failed },
    { status }
  );
}
```

Use this whenever the readmodel key is a non-stream value (`correlationId`, `userId`, etc.) and projectors mutate counters. Look at an existing batch/correlation-keyed readmodel under `<serverPath>/src/modules/` in your repo for the reference shape.

#### Brand-new-row bootstrap: identity-only upsert + per-field CAS init

Whenever no single "genesis" event opens the row (i.e. any of N aggregate streams can be the first to touch a given key), the row must be **bootstrapped without writing any counter field**, then each counter is CAS-initialized to `0` exactly once. The pre-fix `readById` → `upsert(fullSkeletonOfZeros)` pattern is a lost-update race: two first-touch events for a brand-new key can interleave so that event A's `readById` returns "no row", event B's full-skeleton + first `atomicIncrement` land, then event A's skeleton upsert shallow-merges its zeros over B's incremented field — permanently losing the delta.

**Fix shape:** identity-only upsert, then per-field CAS init.

```typescript
const initializeFieldOnce = async ( id: string, field: keyof Row ): Promise<void> => {
  // CAS filter `op: 'notExists'` emits `IS NULL`, matching a row whose field is
  // absent and ONLY then setting it to 0. A racing initializer on an
  // already-incremented field sees a non-null value, fails the CAS, and is a
  // no-op — prior increments are never clobbered.
  await coll.updateMany(
    [
      { field: 'id',  op: 'eq', value: id },
      { field, op: 'notExists' }
    ],
    { [field]: 0 } as Partial<Row>
  );
};

const ensureRow = async ( id: string ): Promise<void> => {
  // 1. Identity-only upsert — NO numeric field, nothing to clobber.
  await coll.upsert( id, { id, ...identityFields });
  // 2. Per-field CAS init — each numeric counter set to 0 exactly once.
  for ( const field of NUMERIC_FIELDS ) {
    await initializeFieldOnce( id, field );
  }
};

// Same primitive for once-only non-numeric labels (e.g. a currency or category
// label derived from the first-touched event for the key):
const setCurrencyOnce = async ( id: string, currency: string ): Promise<void> => {
  await coll.updateMany(
    [
      { field: 'id',       op: 'eq', value: id },
      { field: 'currency', op: 'notExists' }
    ],
    { currency }
  );
};
```

**Use `op: 'notExists'`, NOT `{ op: 'eq', value: null }`, for the CAS filter.** On Postgres the latter compiles to `data#>>'{field}' = NULL`, and `<x> = NULL` is never TRUE in SQL — it matches zero rows, so the field is never initialized. The bootstrap then silently does nothing and the first `atomicIncrement`'s STRICT `jsonb_set( …, NULL )` nulls out the entire `data` column (crashing with `Cannot read properties of null`). This bites ONLY on Postgres: Mongo's `$eq: null` matches absent fields, so a Mongo-backed test passes while production fails. `notExists` emits `IS NULL`, which matches the absent key. The adapter's `atomicIncrement` was also hardened with `COALESCE(( data->>'field' )::int, 0 )` so a missing field can no longer null the column.

After `ensureRow`, every numeric field is non-null — `0` for a brand-new row, or its prior incremented value for an already-touched row. `atomicIncrement` then operates safely against the PG `(data->>'field')::int + delta` arithmetic (the field being `null` resolves the arithmetic to `NULL` and silently zeros the running total — a separate footgun the bootstrap protects against).

Look at an existing cross-stream balance/counter readmodel with an `ensureRow` / `initializeFieldOnce` bootstrap under `<serverPath>/src/modules/` in your repo for the reference shape, with a regression test "Given concurrent cross-stream projection of one key / when the very first two events for a brand-new key interleave".

### Database Indexes

Call `ensureIndex()` for every field or compound field set used in query filters — not just the primary key:

```typescript
database.onStarted( async () => {
  await myCollection.ensureIndex(['id']);                    // Primary key
  await myCollection.ensureIndex(['active', 'nextRunAt']);   // Compound query filter
  await myCollection.ensureIndex(['status']);                // Single-field filter
});
```

If the readmodel is queried by `active + nextRunAt`, add `ensureIndex(['active', 'nextRunAt'])`. Missing indexes cause full table scans at scale.

#### Array-of-string fields → GIN, not the default B-tree

For fields that hold arrays of strings and are queried with `op: 'contains'` (e.g. `hierarchyEntityIds`, `triggeringEvents`, `tags`, any `*Ids: string[]`), you MUST pass `{ strategy: 'gin' }`. The default strategy materializes a `text`-typed `GENERATED ALWAYS` column from `data#>>'{field}'` — that's the JSON *text serialization* of the array (`'["abc"]'` as a literal string). The PG adapter's `getFieldAccessor` then short-circuits to that text column for `op: 'contains'` (it ignores the `asText: false` hint when a registered generated column exists), producing `text_column @> '[…]'::jsonb` — a runtime `operator does not exist: text @> jsonb` error. GIN strategy creates the index over the JSONB path `data#>'{field}'` and does NOT register a generated column, so `getFieldAccessor` falls through to the JSONB form and `@>` resolves correctly.

```typescript
database.onStarted( async () => {
  // Scalar fields → default B-tree.
  await coll.ensureIndex([ 'accountId', 'status' ]);

  // Array-of-string fields used in `op: 'contains'` queries → GIN.
  await coll.ensureIndex([ 'hierarchyEntityIds' ], { strategy: 'gin' });
  await coll.ensureIndex([ 'triggeringEvents' ], { strategy: 'gin' });
});
```

**Migrating an existing readmodel** (a prior default-strategy boot already materialized the broken text column): just changing the `ensureIndex` call is NOT enough. `loadGeneratedColumns` re-discovers existing `GENERATED ALWAYS` columns from `information_schema` at startup and re-populates the registry, so the broken accessor would persist. Drop the stale columns once:

```sql
ALTER TABLE <table> DROP COLUMN IF EXISTS <snake_case_field> CASCADE;
```

Look at an existing readmodel that indexes an array-of-string field with `{ strategy: 'gin' }` under `<serverPath>/src/modules/` in your repo for the reference shape.

### Query-route gotchas: subscribable base routes need a `params` schema; base routes reject `filter`

Two route-level traps that 400 only at runtime (invisible to unit tests), both hit when a front-end first subscribes to / filters a correlation-keyed batch readmodel:

1. **A subscribable base route (`/x/:id?`) MUST declare `schemas.params`.** Without it, PV3's default validation applies `additionalProperties: false` and rejects the optional path param the readmodel **subscription** sends — `400 VALIDATION_ERROR` ("must NOT have additional properties: <param>"). A route registered with only `transformers` + `subscriptions` (no `schemas`) is the trap. Add the params schema mirroring the path param:

   ```typescript
   .withQuery({
     route: '/rule-execution-batches/:correlationId?',
     schemas: { params: S.shape({ correlationId: S.string().optional() }) }, // REQUIRED for the subscription
     transformers: [ FilterByAccountIdTransformer( false ), FilterByScopeTransformer() ],
     subscriptions: [ports.realtimeSession.readmodelSubscription]
   })
   ```

2. **A base route with no custom `queryHandler` rejects a `filter` query param.** Only the `-search` variant — which declares `query: defaultQuerySchemas.query` and a `queryHandler` that applies `params.filter` — accepts `filter`/`limit`/`offset`/`sort`. So a *filtered* front-end query (e.g. a `status:'running'` subset) MUST call `XSearch({ filter })`, not the base `X({ filter })`. Add the `-search` route whenever the FE needs to filter/paginate; the base route is for "get one by id / get all".

### Registration

```typescript
ports.eventsourcing.routeEventHandler( MyReadmodel( ports ));
```

Look at an existing readmodel under `<serverPath>/src/modules/` in your repo for a working reference.

## Module Composition

Modules use `create()` function in `index.ts`:

```typescript
import { Ports } from 'ports';
import { MyAggregate } from './my.aggregate';
import { MyReadmodel } from './my.readmodel';
import { MyPolicy } from './my.policy';

export const create = async ( ports: Ports ) => {
  ports.eventsourcing.routeCommandHandler( MyAggregate( ports ));
  ports.eventsourcing.routeEventHandler( MyReadmodel( ports ));
  ports.eventsourcing.routeEventHandler( MyPolicy( ports ));
};
```

No `@Module` class, no `app.module.ts` imports — just `create( ports )`.

Look at an existing module `index.ts` under `<serverPath>/src/modules/` in your repo for a working reference.

## Dependency Injection

PV3 uses the Ports pattern (closure-based DI):

```typescript
export const MyComponent = ( ports: Ports ) => {
  // ports.eventsourcing, ports.database, ports.log, etc.
  return /* builder */;
};
```

No decorators, no `@Inject`, no `@Injectable`.

### Artifact Constructor Signature — the MDU/Lift Contract

**Every artifact factory — aggregate, policy, readmodel, system — takes EXACTLY `( ports )`. Never add a second constructor parameter. Never inject a dependency into an artifact any other way.**

This is not a style preference; it is a hard deployment invariant. PV3's manifest loader (`@bett3r-dev/pv3` → `selectiveLoader.ts:loadFromManifest`) instantiates every lifted artifact uniformly as `factory( scopedPorts )` — a **single argument, always**. A factory declared as `MyPolicy( ports, something )` receives `undefined` for `something` in any lifted deployment unit. It will work in the monolith, pass unit tests, and pass single-process E2E — then break **silently in production** under MDU distribution. No build, type, or test gate catches this.

Equally load-bearing: **a module's `index.ts` `create( ports )` does NOT run in the lift path.** Only an optional per-module `setup.ts` (matched by filename) plus the individual artifact factories execute. So you cannot wire per-artifact dependencies in `create()` either and expect them in a distributed deployment.

```typescript
// ❌ WRONG — undeployable. `engine` is undefined in any lifted unit.
export const RunnerPolicy = ( ports: Ports, engine: SomeEngine ) => { ... };

// ✅ RIGHT — artifact takes only ( ports ); reaches single-consumer infra
//    via a lazy process-singleton owned by the infra's library/package.
export const RunnerPolicy = ( ports: Ports ) => {
  // getX( ports ) builds-and-caches on first use, wherever this artifact lands.
  const engine = getEngine( ports );
  ...
};
```

**Pattern for infrastructure consumed by a single artifact/module** (an engine, a specialized client): do NOT put it on the global `Ports` type (a port used by one module is a smell — see the composition-root rule), and do NOT inject it. Instead **own it as a lazy process-singleton inside the owning library/package**, built from `ports` on first access, exposed via a `getX( ports )` accessor plus `setX(...)` / `resetX()` overrides for the test/E2E seam. The artifact keeps its `( ports )` signature and reaches the singleton through the accessor.

**The same `getX( ports )` singleton works for MULTI-consumer infra too** — it does NOT have to become a global port. When a piece of infrastructure (e.g. a registry) is consumed by several modules, reach it via a `getX( ports )` accessor (lazy build, with `setX` / `resetX` seams) exported from a **shared library package** the consumers import — rather than passing it as a 2nd constructor arg or cross-importing it from a sibling server module folder. The classic MDU violation is passing such a registry as a 2nd constructor arg (`( ports, registry )`) to N artifacts across multiple modules: it works in the monolith (where `create()` runs) but the registry is `undefined` in any separately-lifted unit. **Test seam for the singleton:** an integration harness calls `resetX()` per harness; unit tests inject via `setX( ... )` in `beforeEach` and `resetX()` in `afterEach` (the singleton captures `ports`, so a stale instance points at a torn-down DB / leaks across files in a shared jest worker). NOTE: runtime *helpers* called from within a handler are NOT lift-loaded artifacts — they keep taking the resolved dependency as a parameter; only artifact FACTORIES must take `( ports )` only.

This invariant is invisible to every automated test — guard it at design time. Reject any plan or diff that gives an artifact a non-`( ports )` signature or wires single-consumer infra at the composition root.

### Composition Root Boundary

`setupPorts.ts` — and its siblings `setupGenerationPorts.ts` and `setupE2ETestPorts.ts` — is the service **composition root**. It may declare **only** ports consumed by **more than one module**, or by the service infrastructure itself (logger, cache, db, eventstore, mailer, etc.).

**A port consumed by exactly one module is a defect**, not infrastructure. Single-module construction — tool catalogs, diagnostic port adapters, engine/registry registration, prompt building, a specialized client — does **not** belong in the composition root and does **not** belong on the global `Ports` type. It belongs in the owning module's library, reached via a `getX( ports )` lazy process-singleton (see the MDU/Lift contract above). The canonical violation is single-consumer assembly (a hundred-plus LOC of one module's infra) living in `setupPorts.ts` and leaking that module's engine/client as a port through `Ports`, `setupGenerationPorts`, and `setupE2ETestPorts`.

**Test/E2E seam without a global port:** when a module owns infra that E2E must mock, follow the test-server precedent (skip the uniform `loadModulesFromDirectory` loop for that module in the test-server bootstrap and call its register function directly with the mock injected), or use the singleton's `setX(...)` / `resetX()` overrides. Do **not** reintroduce the dependency as a global port just to get a test seam.

**Review heuristic:** any net addition to `setupPorts.ts` (or the two parallel setups) must be justified by multi-consumer or infrastructure use. A net-new port consumed by a single module is a placement defect — move the construction into that module.

### Logger

Use `ports.log` — a pre-scoped `LoggerType` instance automatically named after the module directory (e.g., `"accounting"`). Injected by `loadModulesFromDirectory`.

```typescript
const logger = ports.log;
logger.info( 'Processing something' );
```

Only use `ports.logger.createLoggerInstance('custom-name')` if you need a sub-scoped logger within a module.

## Auth Endpoints: Use `context.user`, Not `x-auth-*` Headers

Every PV3-registered endpoint has the authenticated user available in `context.user` (userId, accountId, userType, roles, permissions, scopes). This is populated by `AddDevAuthUserToRequest` in all environments (dev, E2E, and production-behind-gateway).

**Never read `req.headers['x-auth-user-id']`, `req.headers['x-auth-account-id']`, etc. directly in endpoint action code.** These are gateway transport headers set by the gateway (e.g. Traefik ForwardAuth) between the gateway and the backend — not a public endpoint API. In E2E, `AddDevAuthUserToRequest` only populates `context.user`, not `x-auth-*` headers; any endpoint reading those headers will silently receive `undefined` in tests.

**E2E debugging note:** Source file changes in workspace packages (the auth package, the domain package, etc.) are NOT picked up live during E2E tests — those packages have `"main": "build/index.js"` and `ts-node` resolves the pre-compiled output. To instrument them, edit the `build/` folder or rebuild the package first. Files in `<serverPath>/` are loaded from source.

## Endpoint Properties

PV3 endpoints have two independent identity properties:

| Property | Type | Purpose |
|----------|------|---------|
| `loggingModule` | `string` (always set, kebab-case) | Log grouping/filtering. Auto-derived from artifact name. |
| `subdomain` | `string \| undefined` (kebab-case) | Business domain for authorization. Auto-derived from `modules/<name>/` directory. Validated against `SubdomainModules` at startup. |

**Auto-derivation:** Both are extracted from the filesystem via `getStackTrace()`. Explicit overrides via `withSubdomain()` on builders or factory params on external packages.

**Manual endpoints** use `subdomain: 'xxx' satisfies SubdomainModule` for compile-time validation:

```typescript
endpoints.registerEndpoint({
  loggingModule: 'my-endpoint',
  subdomain: 'my-subdomain' satisfies SubdomainModule,
  // ...
});
```

## Invariant Placement

Every domain invariant must live on — be enforced synchronously by — an **aggregate**. If an invariant ends up validated in a policy (async, eventually consistent) or a readmodel (a projection), that is a **design defect** — wrong aggregate boundaries or a malformed invariant — to fix at the design level, never a placement to rationalize. The aggregate is the consistency boundary; an invariant enforced elsewhere is not actually guaranteed.

When an invariant seems hard to place — e.g. it needs visibility across sibling streams — do NOT move it to a policy. Surface the boundary tension and re-examine the aggregate. (Example: an overlap/uniqueness invariant that needs cross-row visibility stays on the aggregate that owns the rows / windows it needs to check.)

## Gating Non-Production Features

Dev-only / non-production backend features (test channels, dev tooling, debug endpoints) must be gated with a single registration-time guard at the **module composition root** — the module's `create( ports )` or the registry registration — e.g. `if ( process.env.NODE_ENV !== 'production' ) { ... }`. A dev-tools module that registers no route in prod produces no Fastify route and no OpenAPI entry — that's the precedent.

**Never** gate by conditionally adding commands to an aggregate's `.withCommands(...)` map (the `let additionalCommands = {}; if ( !prod ) { ... }; return { ...additionalCommands, ... }` pattern). An aggregate's command surface feeds build-time generated artifacts that are environment-invariant by design — `.deployment-units.json`, `.openapi.json`, the generated client library, and the rules-engine `node-registry.json`. A command that exists only outside production makes those artifacts depend on the build environment, so a dev-built manifest/OpenAPI/client advertises a command prod doesn't have at runtime. Reinforce at the deployment layer by leaving the unit out of production `lift:` patterns. (Anti-pattern: a dev-only authorize command conditionally added to a tenant aggregate's command map.)

## Realtime Subscriptions: Signal Mode

pv3's realtime-session signal mode (`x-subscription-changes: signal`) delivers `{ type: 'signal' }` to the consumer's `onChange` — it does **not** re-execute the original query, and it should stay that way. The consumer (data policy) implements refetch itself: on a signal, call `backend.queries.X({ ...currentFilter })` and dispatch the result, with a small (~200ms) debounce to coalesce bursts. Don't extend the client-library generator to auto-refetch — different consumers have different filter sources, debounce windows, and ordering needs.
