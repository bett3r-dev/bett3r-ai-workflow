---
description: PV3 DDD pattern reference — the framework conventions, gotchas, and hard-won lessons for aggregates, command handlers, policies, read models, schemas, module composition, the MDU/lift dependency model, and the outbox event-delivery ordering model (within-stream strict order, cross-stream at-least-once, the per-stream version watermark, consumer dedup/idempotency rules, and the `event.metadata.isRedelivery` operator-replay signal). Read when designing or implementing PV3 DDD artifacts (aggregates, policies, read models) or reasoning about event delivery/ordering, consumer redelivery, or replay handling.
---

# DDD Module Patterns (PV3)

When working in DDD modules, follow these PV3 patterns.

## Project configuration

This skill resolves placeholders from your repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>` | `domainEventsPackageName` | `@bett3r-dev/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |
| `<clientLibraryPackageName>` | `clientLibraryPackageName` | `@bett3r-dev/teselly-client-library` |
| `<domainUtilsPackageName>` | `domainUtilsPackageName` *(optional; defaults to `<domainEventsPackageName>` + `-utils`)* | `@bett3r-dev/teselly-domain-utils` |

`@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the `ports` module are PV3 framework — identical in every repo — and appear verbatim below.

**Working references:** for every artifact type here (aggregate, policy, readmodel, module `index.ts`), an existing example lives under `<serverPath>/src/modules/` in your repo; domain schemas/events under `<domainEventsPath>/src/`. Read one before writing your first. Where a section says "reference shape: …", find the file under `<serverPath>/src/modules/` matching that description — grep for the concrete symbols it names (e.g. `ensureRow`, `guardExternalEffect`, `strategy: 'gin'`) when it names any.

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
Registration: `ports.eventsourcing.routeCommandHandler( MyAggregate( ports ));`

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

- Commands without `.withHandler()` produce a single event with data as payload.
- **`idempotency.check(value1, op, value2?)` semantics:** `value1`/`value2` are selector functions receiving the command-handler state (`({ state, data }) => …`); `op` is a comparator (`'exists'`, `'eq'`, …). When the comparison holds, the command **short-circuits as a success with zero events** — the handler never runs and no error is returned. Duplicates look like a normal 2xx to the caller.
- **`.produces([])` (empty array) crashes PV3's `getCommandSchemas` during endpoint registration.** For side-effect-only commands, declare at least one possible event and return `[]` from the handler. The handler is not required to emit all declared events.

### Client Library Typing

The client library (`<clientLibraryPackageName>`) is fully typed. Never use `any` for its inputs/outputs; **never cast command bodies as `as any`**. If types don't match, either the type definitions are wrong (fix them) or the client library is stale (`yarn generate-all`). Casting hides regressions silently.

**In-process calls — no explicit auth headers:** with `createBackend({ baseUrl: '' }, ports.endpoints.fetch)`, do NOT pass `x-auth-account-id` / `x-auth-user-id` as the third argument — the ALS-backed `setExecutionContextProvider` wired in `setupPorts.ts` injects them (and overwrites explicit ones). **Exception:** ALS only propagates within the same async context chain; code that detaches (account-scoped ALS in a rules-execution policy, `setImmediate`, external pool callbacks) may need explicit headers — verify whether `setupPorts.ts` wires ALS for the calling context before removing them.

### Transactional Side-Writes

Handlers receive a `transaction` parameter (4th arg: `{ context, transaction }`). Writes via `transaction.getCollection()` are atomic with the event store commit — if events roll back, side-writes roll back. **Testing caveat:** this atomicity holds in *production* (`PostgresEventstore`), but the in-memory integration harness wires `DatabaseEventstore`, which *discards* the transaction — so a harness-based test cannot validate rollback or in-transaction read-your-writes semantics, in either direction (see `create-integration-test` → *Harness fidelity*). Verify those against the real server on local infra.

```typescript
.withHandler( async( createEvent, state, data, { context, transaction }) => {
  const col = transaction.getCollection( 'my_side_table' );
  await col.upsert( data.id, { nextRunAt: computeNextRun( data.cronExpression ) });
  return [createEvent( 'EntityUpdated', data, { metadata: { accountId: context?.user?.accountId }})];
})
```

**When to use:** uniqueness constraints, counters, scheduling state — anything that must be consistent with the event store, not eventually consistent via readmodel projection. Examples: a unique-email side-write; a `nextRunAt` scheduling side-write; a monotonic sequence number (fiscal/receipt/document number) via `atomicIncrement` on a counter row (`{ id: 'global', value: number }`) bumped under `FOR UPDATE` inside the transaction that emits the *consumption* event — put the increment in the handler that emits it (publish/finalize), not the draft handler, so discarded drafts don't burn a number.

**Anti-pattern: Redis `INCR` for must-be-unique monotonic numbers.** Redis `INCR` is not transactional with the event store; under `appendfsync everysec` a crash can regress the counter and reissue a used number. Gaps are tolerable; duplicates are not. Use the transactional DB counter.

**Mutual-exclusion lock via UNIQUE-constraint side-write.** When an invariant requires **at most one in-flight operation** per key, use a side-table with `UNIQUE(lockKey)`: `insert` inside the acquiring command's transaction, `delete`-by-pk inside each terminal handler's transaction. Acquire is gated by an optional lock-identity parameter so non-locked dispatches (admin / one-off) bypass it. `UNIQUE_VIOLATION` re-throws as `BadRequestError` with a stable code (`OPERATION_IN_PROGRESS`) and rolls back the events. Release-by-pk is idempotent (missing row is fine), so duplicate terminal events are safe.

```typescript
CreateDraft: commandBuilder()
  .withSchema( CreateDraftCommandSchema )
  .produces([ 'DraftCreated' ])
  .withHandler( async( createEvent, state, data, { transaction }) => {
    if ( data.runId ) {
      const lockCol = transaction!.getCollection( 'operation_lock', 'lockKey' ); // UNIQUE(lockKey)
      try {
        await lockCol.createMany([{ lockKey: data.lockKey, documentId: data.documentId,
          runId: data.runId, acquiredAt: new Date().toISOString() }]);
      } catch ( e ) {
        if ( isUniqueViolation( e )) {
          throw new BadRequestError( 'An operation is already in progress for this key',
            'OPERATION_IN_PROGRESS', { lockKey: data.lockKey });
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

Rules:
1. **`createMany` / `destroyById` are the PV3 APIs**, not `insert` / `delete` (pseudocode in older specs). `destroyById` takes the pk value directly.
2. **Persist the lock-identity on state** (reduced from the acquiring event) so terminal handlers know whether to release.
3. **Every terminal handler MUST release** (`DocumentCompleted`, `DocumentFailed`, `DraftCanceled`, `Cancel`). Forgetting one is the canonical "stuck lock" bug.
4. **Re-acquire on legitimate re-entry:** a retry command after a failure event (which released) must re-acquire, or the invariant is violated across the cron/retry race window.
5. **Orphan-sweep is the operational follow-up** if a policy crashes between acquire and terminal event; a reasonable mitigation is the run policy's top-level try/catch + compensating cancel.
6. **Required test fixtures:** (a) second `CreateDraft` with same key → `OPERATION_IN_PROGRESS`, no event (fake collection surfacing `UNIQUE_VIOLATION`); (b) per terminal handler: after commit, the lock row is gone.

### Event namespace coverage

`withEventReducers` must list every event in the namespace passed to `AggregateBuilder( schema, namespace )`. Two paths:

1. **Declare a subset at builder time** *(preferred — load-bearing documentation of which events the aggregate cares about)*, same as `PolicyBuilder({ SomethingHappened })`:
   ```typescript
   const { ThingCreated, ThingUpdated, ThingDeleted } = ThingsEvents;
   AggregateBuilder( ThingAggregateSchema, { ThingCreated, ThingUpdated, ThingDeleted })
   ```
   No no-op stubs needed for events the aggregate never sees on its own stream.

2. **`ReducerNOOP` (from `@bett3r-dev/pv3-types`)** — reach for this **only when the aggregate itself emits the event**, from a multi-stream command whose event lands on a stream it doesn't reduce (e.g. `BulkOperationCompleted` on a per-correlation stream). PV3 still requires a reducer entry for the produce-declaration check; `ReducerNOOP` (`state => state`) signals "produced but not reduced":
   ```typescript
   .withEventReducers({ ThingRegistered: ..., ThingEdited: ..., BulkOperationCompleted: ReducerNOOP })
   ```

### Event-only metadata fields

When an event carries a field for downstream projectors (e.g. `totalInBatch`) but not for aggregate state, do **not** `{ ...event }` in the reducer — that leaks the field into state and either fails strict schema validation or silently diverges from `AggregateSchema`. Destructure it out:

```typescript
SomethingStarted: ( _, event, metadata ) => {
  const { totalInBatch, ...stateData } = event;  // strip event-only field
  return { ...stateData, ownerId: metadata?.userId };
}
```

### System / admin-only aggregates

- **Global infrastructure aggregates** (cronjob subscriptions, feature flags, global config) can skip `scopeInvariant()`, `ownerId` in reducers, and `accountId` in event metadata; their readmodels skip `FilterByAccountIdTransformer` / `FilterByScopeTransformer`. Admin-only, not tenant-scoped; enforce access via route-config (`private`, no subdomain).
- **Tenant-scoped, NOT row-scoped aggregates (org-global config)** — the middle bucket between the two above. A tenant resource whose capability is collapsed to `['all']`-only in the permissions/resources registry (org-global config with no per-user delegation — e.g. a price-list or size-guide shared by the whole account) models **no per-row ownership**. Such aggregates **omit `ownerId` from reducers AND `scopeInvariant()` from commands**, and their readmodel creation projectors **omit the `ownerId` projection** — but they **keep** `accountId` in event metadata and `FilterByAccountIdTransformer` on the readmodel (they ARE tenant-isolated, just not row-scoped). Do NOT "restore" `ownerId`/`scopeInvariant` on these under the blanket security rule — it is dead machinery once the resource is collapsed to `all` (`scopeInvariant()` short-circuits on `all`, and no `FilterByScopeTransformer` reads the field). Verify against the actual `['all']`-only collapse decision before applying this carve-out to a resource — it doesn't apply just because an aggregate happens to skip `ownerId` today.
- **Admin-only domain aggregates** inside a named module directory emit an empty subdomain via `.withSubdomain( '' )` on the aggregate/readmodel builder. This overrides filesystem auto-derivation: routes carry no `x-subdomain` and the gateway authorizes via the admin path (`userType === 'admin'`) instead of org feature-entitlement + permission. The subdomain's block must be **absent** from `permissions-catalog.json` (an orphaned block fails the `generate-all` drift check). Every route in such a module must call `.withSubdomain( '' )`.

### Lifecycle status guards (defence-in-depth)

Any aggregate whose lifecycle is a status state machine (`draft → published → completed/failed`, `draft → published`/`canceled`, …): **every command that transitions or operates on a status MUST throw a status-mismatch `BadRequestError` when called in the wrong state** — not as a numbered domain invariant, but as defence-in-depth against a caller (or future bug) issuing commands out of order. Without it: a `draft` can jump straight to `completed` (skipping `published` and any transactional sequence-number assignment fired at publish); a `canceled` document can be reversed; a wrong-state callback can corrupt the stream. Idempotency checks cover the *duplicate* case (same external transaction id); these guards cover the *wrong-state* case (different transaction id, wrong prior status).

Pattern: one `*_NOT_*` SCREAMING_SNAKE code per guard (e.g. an immutability code on an already-published document, plus `DOCUMENT_NOT_DRAFT`, `DOCUMENT_NOT_PUBLISHED`, `DOCUMENT_NOT_CANCELABLE`, `DOCUMENT_NOT_REVERSIBLE`). These are part of the documented error contract even though they are not numbered invariants.

```typescript
FinalizeDocument: commandBuilder()
  .withSchema( FinalizeDocumentCommandSchema )
  .withInvariant( invariants.stateExists( ... ))
  .withIdempotencyCheck( idempotency.check( duplicateCallbackCheck, 'eq', () => true ))
  .produces([ 'DocumentFinalized', 'DocumentFailed' ])
  .withHandler( async ( createEvent, state, data ) => {
    if ( state.status !== 'published' ) {
      throw new BadRequestError( 'Only a published document can take a finalize outcome',
        'DOCUMENT_NOT_PUBLISHED', { documentId: state.documentId, status: state.status });
    }
    // ... emit event ...
  })
```

The **happy-path + state-rejection pair** is a required test fixture for every status-guarded command.

### Idempotency-predicate null-safety

PV3 evaluates `withIdempotencyCheck` predicates **before** `withInvariant( invariants.stateExists() )` — the invariant fires too late to protect the predicate. A predicate that dereferences `state` must null-guard. The bug shape is a one-character omission that throws `TypeError: Cannot read properties of null (reading 'status')` from inside PV3 — an opaque internal error instead of `STATE_NOT_FOUND`:

```typescript
.withInvariant( invariants.stateExists( ... ))                  // fires LATER
.withIdempotencyCheck( idempotency.check(
  ({ state }) => state?.status === 'published',                 // ← optional chaining is REQUIRED
  'eq', () => true ))
```

**Required regression test:** every command with a state-reading idempotency predicate needs a "Given the command on a non-existent stream / then stateExists throws `STATE_NOT_FOUND`" test — without it the null-deref hides behind the happy path.

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

Type extraction: `typeof Schema.type` (not `z.infer<>`). Use `omitFromSchema( Schema, ['field'] )` (not `.omit()`).

Domain schemas split across two files in `<domainEventsPackageName>`:

| File | Contains |
|------|----------|
| `<domain>.types.ts` | Event schemas, value objects |
| `<domain>-integration.types.ts` | Aggregate state, command, readmodel schemas |

## Events

Factory functions with schema and friendlyName, at `<domainEventsPath>/src/<domain>/<entity>.events.ts`:

```typescript
import { Event } from '@bett3r-dev/pv3-types';

export const SomethingHappened = () => Event({
  schema: SomethingHappenedEventSchema,
  friendlyName: { es: 'Algo sucedio', en: 'Something happened', pt: 'Algo aconteceu' }
});
```

### Renaming a persisted field is schema evolution, not a rename

Renaming or removing a field on a **persisted event** schema (`<domain>.types.ts`) — or on the **aggregate state** that rehydrates from those events — requires an **upcaster or event-type version bump, never a bare rename.** PV3 rehydrates aggregates by reading event fields **by name**, so any event persisted under the old name rehydrates to `undefined` for that field (e.g. `accounts["undefined"]`), silently breaking replay and every command that depends on that state (`*_NOT_FOUND`).

- **The tell** — a PR scoped as a "pure rename" that edits `*.types.ts` event schemas, or the `applyEvent` / rehydration field reads on aggregate state. That is a data-store change, not a symbol rename.
- **The check** — does a pre-existing (old-shaped) event still rehydrate correctly? Is there a test that persists an old-shaped event and replays it? A green *targeted* test run does **not** cover this — the replay path usually has no test.
- **The safe contrast** — PV3 derives stream / route / subscription identity from the **filename**, not the const, so renaming *code symbols* (const names, type names) is safe and has zero data-store impact. Renaming *persisted fields* is not. Apply the rule to the persisted half only; don't over-apply it to symbol renames.

Cross-ref: this is why `create-schema` / `create-aggregate` renames on existing modules are not mechanical.

## Event delivery: within-stream strict order, cross-stream at-least-once

**Hard contract — how the outbox delivers events:**

**1. Within a stream: strict version order, always** — never reordered, in normal operation, gap recovery, or operator replay. Four independent reasons:
- Monotonic version = monotonic position (optimistic concurrency: to write `v+1` you must have loaded `v`, so `v` commits first).
- A stream always routes to **one split**, dispatched position-ordered through a **concurrency-1 queue**.
- A gap (lower position uncommitted while a higher one is visible) is *only ever cross-stream* — a stream's later versions commit after its earlier ones.
- Operator reposition re-pulls a range in position order → produces *duplicates*, never out-of-order.

**2. Cross-stream / global position: no order guarantee.** Commit-visibility races and gap recovery *deliberately* deliver a cross-stream-late position after newer ones. Never assume global order.

**3. At-least-once — the full set of duplicate causes.** The ACK can be lost at two layers (Redis dispatched-bit AND HTTP response), and an operator can replay on purpose:

| # | Cause | Present at single replica? |
|---|-------|----------------------------|
| a | Crash **after a successful send, before the `SETBIT`** → re-dispatched on recovery | Yes |
| b | Send the outbox **saw as failed** (timeout / 5xx) but the consumer **actually processed** (lost HTTP response) → retried | Yes |
| c | **Operator replay** — admin "Set Single Data Split Position" with `reprocess: true` | On demand |
| d | Cross-process **zombie / partition owner** (no fencing) | Not at 1 replica — but it's the contract *before* scale-out |

You do **NOT** need to handle duplicates from watchdog/coordinator or gap-recovery re-pulls of already-delivered events — the dispatched bitmap absorbs those (`reprocess: false`). Only (a)–(d) reach a consumer.

### The one rule that matters most: dedup per-stream on version, NEVER on global position

Because cross-stream order is not guaranteed, a global "skip if `position ≤ last seen`" high-water mark **drops exactly the gap-recovered events** (a legitimately cross-stream-late position) — silently re-creating a dropped-event bug. The discipline:

- Track a **per-stream last-applied version** watermark.
- Incoming `version ≤ lastApplied[stream]` → duplicate → skip, **but return 2xx** (an error makes the outbox retry → retry storm; a 2xx lets it set the dispatched bit and stop).
- Otherwise apply and advance the watermark.

Per-stream order makes the watermark *sufficient* — no need to remember every event id. A within-stream gap (`version > lastApplied + 1`) should never appear; if it does, it signals a bug or deduping on the wrong key, not a reordering to tolerate.

`upsert` keyed by stream id gives *idempotency* (same row twice is safe); the watermark additionally protects *observable effects* a duplicate would corrupt. The two are independent.

### Who needs the watermark

- **In-process PV3 read models: free.** `ReadmodelBuilder` applies the per-stream version watermark internally — dedup-safe by construction. **Custom / external consumers (HTTP webhooks, non-PV3 services) must replicate it.**
- **Read models:** a pure last-write-wins `upsert` keyed by stream id is self-healing under duplicates. The watermark is *strictly* load-bearing when the projection is **non-convergent** — appends to an array, increments/accumulates, or exposes intermediate observable state — where a re-applied duplicate corrupts the result.
- **Policies — case-by-case.** Order within a stream is guaranteed; what a policy must survive is duplicate redelivery. *Idempotent reaction* (re-applying is a no-op): nothing needed. *Non-idempotent reaction* (accumulates, or fires a per-transition side effect): make each dispatched command idempotent (see *Policies*) **or** hold a per-stream watermark/side-table — and never assume cross-stream order. (Redelivery-safety makes a handler idempotent under replay; the watermark makes a dedup-requiring handler correct under at-least-once.)

### Non-idempotent external side effects

If processing an event triggers a real-world action (charge a card, `createShipment`, send an email), the watermark must be committed **atomically with the side effect**, or the side effect must **carry its own idempotency key** (natural key + `ON CONFLICT DO NOTHING`, or a provider idempotency-key) — otherwise causes (a)/(b) double-fire it. This is the load-bearing work tracked as **TV1-1945**; the `isRedelivery` flag below does **not** change it.

### `event.metadata.isRedelivery` — the operator-replay signal

Every dispatched event carries `event.metadata.isRedelivery: boolean` — read straight off the metadata handlers already receive (no new API). Off by default; stamped `true` in exactly one situation:

> `isRedelivery === true` **iff the dispatched bit was already set when the outbox decided to send this position** — a previously delivered-*and*-committed position being sent again. The only such path is the admin **"Set Single Data Split Position"** replay (`reprocess: true`, cause (c)).

So it is **false-positive-free — never set on a genuine first delivery** — and **silent on the crash/retry paths**: causes (a)/(b) dispatch with the bit still `0`, indistinguishable from a first delivery, `isRedelivery: false`.

| Delivery path | dispatched bit when outbox decides | `isRedelivery` |
|---|---|---|
| Normal first delivery | 0 | `false` |
| Crash-before-commit re-dispatch (a) | 0 | `false` |
| Lost-HTTP-response retry (b) | 0 | `false` |
| **Operator replay of committed position (c)** | **1** | **`true`** |

**What it IS for:** safely suppressing a non-idempotent side effect on a replay ("we already shipped; don't re-send the shipped email"). Since it never fires on a first delivery, suppressing on it can never drop a first-time effect. The original event is not mutated — the flag is on the dispatched copy's metadata only.

**What it is NOT:** a dedup primitive or exactly-once. Absolute exactly-once still requires dedup on `(stream, version)` / event id with the effect committed atomically or carrying its own idempotency key (TV1-1945). A single boolean also can't distinguish "recovery" from "operator reprocess" — irrelevant for the suppress use case.

**Decision rule:** drop duplicates correctly in all cases → per-stream version watermark (`isRedelivery` doesn't help — false on (a)/(b)). Only avoid re-firing a non-idempotent effect on operator replay → `isRedelivery`. Both → both; they compose.

### TL;DR for a consumer author

1. **Assume at-least-once** — the same event can arrive again.
2. **Rely on per-stream order; never on cross-stream / global order.**
3. **Dedup with a per-stream version watermark, not global position — and 2xx duplicates.**
4. **Make external side effects idempotent** — commit the watermark *with* the effect, or use a dedup key.
5. **`isRedelivery` is a replay *hint*, not dedup** — true only on operator replay (c); false on (a)/(b).

### Redelivery-safe external effects: the A/B/C layer model

When a non-idempotent external effect must survive at-least-once redelivery, three distinct questions each get their own layer. They compose in a fixed order; use whichever layers the hazard requires.

| Layer | Answers | Mechanism |
|---|---|---|
| **A — aggregate invariant** | "already *recorded* this fact?" | `withIdempotencyCheck` on state — a bounded key-set (`array.slice(-N)`, keyed on an inbound-trigger id riding event **metadata**, never payload) for a many-times fact, or an O(1) boolean marker when at most one occurrence is possible |
| **B — policy checkpoint** | "already *performed* this external action?" | A shared `guardExternalEffect` helper (lives in `<domainUtilsPackageName>`) wrapping `transactionalIdempotencyCheckpoint(event.id)` — durable (Postgres), survives cache/snapshot loss, keyed on the trigger's committed `event.id` |
| **C — reconcile-by-natural-key** | "did the external system already accept it (crashed before we recorded)?" | Query the external system by its own natural key, run **unconditionally** on every delivery — see *reconcile by natural key* under Policies |

**Guard order at the boundary:** `isRedelivery`-skip **FIRST** (ACK, zero I/O, zero checkpoint mutation — an operator force-replay reprojects read models via reconcile only), **THEN** the B/C dedup. Do **not** use `isRedelivery` as the dedup gate — it is `false` on exactly the crash-before-mark duplicate B/C exist to close (`isRedelivery` ⇔ `version ≤ watermark`; a crash-window duplicate is `version > watermark`), so it is a no-op precisely where duplication happens.

**The graceful-no-op / no-throw contract:** every dedup/skip path MUST resolve as command **success**. A throw on a null-version stream dead-letters and trips the outbox circuit breaker; on a versioned stream it halts the stream. A shared guard returns a value the caller branches on — e.g. `guardExternalEffect(...) → { performed: boolean, result?: T }` — rather than signalling "already done" by throw/catch. Even in a repo without that exact package, the composition (event-id-keyed checkpoint + optional reconcile, in the fixed order above) is the reusable part.

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
- Cross-service commands go through the client library (`<clientLibraryPackageName>`)
- Registration: `ports.eventsourcing.routeEventHandler( MyPolicy( ports ));`

### Partial-progress redelivery: derive policy progress from aggregate state

A handler that dispatches **N commands in a loop plus one wrap-up command** (e.g. allocate an amount across N targets, then create a residual record) is subject to outbox redelivery mid-progress — any throw between commands leaves it restartable. Per-command idempotency is necessary but **not sufficient**: the policy's local accounting (`remaining`, "what's left") must agree byte-for-byte with the aggregate's recorded progress, or the wrap-up sees the wrong residual.

**The bug class:** recomputing `remaining` by **re-walking live downstream state** (a target's current balance) silently disagrees with the aggregate's recorded `applications[]` / `postings[]` after a partial run. Already-settled targets report `outstanding = 0` on redelivery; the loop `continue`s *without decrementing `remaining`*; the wrap-up fires for the full original amount, inflating by Σ already-applied. The per-target commands no-op via identity idempotency, but the wrap-up — keyed on the *event id*, not per-target identity — commits fresh.

**The fix shape:** seed `remaining` from the **source aggregate's recorded progress**, and skip plan entries whose identity already appears there. Live downstream balances are read only for the *per-iteration cap* (`min(remaining, target.outstanding)`), never as the source of "what's left".

```typescript
SomethingCollected: async ( event ) => {
  const record = await sourceCollection.readById( extractIdFromEventStream( event ));
  // ...projection-lag throw...

  // Seed `remaining` from the aggregate's own recorded progress — NOT from
  // live target outstanding. A target settled by a prior run reports
  // outstanding=0, but its allocation is in `applications[]` so it's skipped.
  const priorApplications = record.applications || [];
  const appliedTargetKeys = new Set( priorApplications.map( a => `${a.targetType}:${a.targetId}` ));
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

**Applies to** any policy dispatching a per-item loop plus a final wrap-up, whose item-level commands record into a source-aggregate collection the policy can read back. **Required regression test:** "Given <TriggerEvent> REDELIVERY with prior-run applications already recorded" — fixture the source readmodel with 1+ allocations and a plan re-including those targets; assert the redelivery yields `wrap-up(amount − Σapplied)`, not `wrap-up(amount)`. Reference shape: an existing wrap-up-after-loop policy.

### Multi-command fan-out must be replay-safe

A handler dispatching **more than one command** — a fan-out loop (N `RemoveChildMember` + a `DeleteParent`) or a sequence — is redelivery-restartable from the top. **Every dispatched command must be idempotent on replay** (`withIdempotencyCheck` or a handler that no-ops the already-applied case), OR the policy must track progress in a watermark/side-table. **Default to per-command idempotency**; reach for a watermark only when per-item progress can't be derived from aggregate/readmodel state (the heavier partial-progress case above).

**Soft-delete trap:** `invariants.stateExists()` does **NOT** protect a soft-deleted aggregate — `mergeLeft({ isDeleted: true })` leaves state non-null, so a non-idempotent terminal command **re-emits its event** on redelivery (re-firing every downstream consumer) instead of erroring. Invisible to the happy path and to tests that don't simulate redelivery. A delete/terminal command on a soft-delete aggregate needs its own guard keyed on `state?.isDeleted`.

**Required regression test:** "redelivery after partial progress" asserting the second delivery emits **zero** duplicate events. Reference shape: an existing fan-out erasure/cleanup policy.

### Non-idempotent external side-effects: reconcile by natural key, not a blind ledger

For a side-effect targeting an aggregate, redelivery is handled by the rules above. This is the harder case: a **non-idempotent external call** (list a product, issue an invoice) with no idempotency key, which must not run twice.

**Classify first — the classification picks the tool:**

- **(a) Idempotent** — PUT, absolute-value set, upsert by stable id. → Nothing needed.
- **(b) Targets an aggregate** — via `executeCommand`. → The aggregate dedups (optimistic concurrency / `withIdempotencyCheck`). Nothing extra in the policy.
- **(c) Non-idempotent external, no idempotency key** — a create-style call with real effect each time. → **Reconcile against the external system by a natural key** before/instead of re-doing it: ask "does this already exist?" using a key the external knows (a SKU or client-reference for a listing, a transactionally-reserved number you read back for an invoice). Exists → skip; else create.

**Do NOT use a blind processed-events ledger / bitmap / lease (Redis or Postgres) for case (c).** A ledger marks *processed* **after** the effect — `read-ledger → POST → write-ledger` — and a crash between POST and write re-POSTs on redelivery: the same act-then-mark gap, plus machinery. **Reconcile is authoritative** — it trusts the external system, not local memory, and survives total loss of the local dedup store. A best-effort ledger is justified only when the effect is non-idempotent **AND** non-reconcilable (no read-back, no natural key) — state that explicitly when building one.

**Prefer pushing dedup into the external** via an idempotency key derived from `event.id` when the API supports one (Stripe-style `Idempotency-Key`) — that converts (c) into (a) at the boundary.

**Do NOT gate the reconcile on `isRedelivery`.** It looks like a free optimization, but `isRedelivery` is `false` on the crash/retry redeliveries (causes (a)/(b) — the *dominant* duplicate paths; see the delivery section), so a "create directly when false" fast-path double-creates exactly there. The reconcile read (or external idempotency key) must run **unconditionally**. There is no `deliveryAttempt` in PV3.

This is the same decision the `bett3r-ai-workflow` **grill** skill's *side-effect-reconcilability* probe forces at design time. If scaffolding the policy, see also `create-policy` → *Critical Constraints*.

### Dependency Declaration

Every policy must declare its aggregate dependency for deployment-unit computation. Build error if missing.

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

A policy belongs in the **subdomain whose state it changes**, not the one that emits the trigger event. If its `createCommand` / `executeCommand` targets aggregate X, the file lives in X's module directory — colocating with the *trigger event source* is the canonical misplacement. Cross-module reactions import the source event's *schema* (always allowed via `<domainEventsPackageName>`), never the source module's implementation. *Example:* a policy reacting to `Identity/UserAccountAdded` to provision a resource owned by another module belongs in that other module, not `src/modules/identity/`.

### ACL Systems and `produces` Declarations

`produces` must **only list events the handler itself writes to the event store** — never downstream side-effects of aggregate commands it dispatches. A gateway system handler that calls `executeCommand(SomeAggregate, 'DoSomething')` and returns `[]` must NOT list the downstream aggregate's events (they belong to a different stream); declare empty/omitted `produces`.

**Canonical gateway ACL two-step:** (1) the gateway system emits a **raw gateway event** (e.g. `GatewayCallbackReceived`) capturing the external payload verbatim; (2) a **separate policy** reacts to it and dispatches the aggregate command (e.g. `RecordCallbackOutcome`), which emits the domain event.

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
- `FilterByAccountIdTransformer()` for multi-tenant filtering; `FilterByScopeTransformer()` for permission-based scope filtering (always AFTER `FilterByAccountIdTransformer`)
- Project `ownerId: event.metadata?.userId` in creation event projectors — **except** for the tenant-scoped-but-not-row-scoped carve-out above (`['all']`-only collapsed resources), which omit it entirely
- Collection names: `{domain}_{entity}_readmodel`
- Registration: `ports.eventsourcing.routeEventHandler( MyReadmodel( ports ));`
- **Schema location:** readmodel schemas MUST live in the domain package (`<domain>-integration.types.ts`), not inline — the client library generator and OpenAPI spec derive types from the domain package; inline schemas produce untyped/incomplete generated artifacts.
- **Subdomain assignment reflects domain ownership:** `.withSubdomain('X')` must name the domain the data conceptually belongs to — never chosen for authorization convenience or to dodge a permissions-catalog/registry diff — and must agree with the file's module location. If the right gate doesn't exist, add the registry entry under the correct subdomain; don't borrow another's.

### Subscriptions require `databaseSessionMode`

If a `.withQuery({ ... })` declares `subscriptions: [...]`, you **MUST** pass `databaseSessionMode` as the **third** argument to `.withDatabase( database, collection, databaseSessionMode )` (destructured from `Ports`) — it wires the collection change-stream `watch([...])` powering live deltas. The two-arg form compiles and serves the initial snapshot, so the omission fails silently: projection and reads work, only live push is dead (subscribers update only on full page refresh).

**A `204` response to a subscription request is NORMAL** — the snapshot and deltas go over the realtime channel (`manager.send`), not the HTTP body. Don't misdiagnose a 204 as broken.

### Cross-subdomain reads go through the client library

Never read **another subdomain's** readmodel via `ports.database.getCollection('<other-subdomain>_*_readmodel')`. A readmodel's backing table is **private to its owning subdomain** — name, id shape, and row schema are not a public contract; binding to them blocks the owner from renaming/reshaping. `getCollection` is for the readmodel's **own** projectors and queries. Cross-subdomain reads use the in-process client library against the **published query endpoint** (`backend.queries.X`) — exactly as cross-module writes go through the client library (no cross-module `executeCommand`). **Red flag:** a `getCollection('<name>')` inside module `A/` whose name is prefixed with a different subdomain.

### Projector read-modify-write: `upsert` does NOT deep-merge on the update path

The natural projector shape — `readById` → mutate a nested `jsonb` map → `upsert(fullDoc)` — relies on assumptions that don't hold (verified against `pv3-adapter-database-postgres` / `pv3-library-outbox-manager`):

- **`upsert`'s merge is asymmetric.** The row-exists **UPDATE** path is a shallow `data = data || $2` — a full nested object **wholesale-replaces** the stored one. `jsonb_recursive_merge` (deep) runs **only** on the INSERT `ON CONFLICT` race path. Only **dot-notation** keys get a JS-side `mergeDeepRight`.
- **`readById` + `upsert` are non-atomic** — separate connections/transactions; the `FOR UPDATE` inside `upsert` covers only its own re-read+write.
- A same-stream RMW is loss-safe **only** because the outbox serializes same-stream events through a per-split `concurrency:1` queue — NOT because of deep-merge.

**So loss-safety is topology-dependent.** Single consumer = safe; a multi-instance rebalance **fencing gap** (a zombie/GC-paused old owner with an in-flight dispatch) can overlap two same-stream projections and the shallow overwrite drops a sub-key. Same hazard if two *different* streams project into the same doc id with `splitCount > 1`, or any non-outbox writer touches the row. No single-consumer test reproduces this — it only bites under multi-split.

**For additive-across-concurrent-writers semantics on a nested map:** use **dot-notation keys** (which get `mergeDeepRight`), an atomic increment / per-field CAS (below), or an explicit lock — never a full-nested-object `upsert`.

#### A complete-state write needs `{ replace: true }`; removing a key needs `unset`

"Rebuild the whole row from current state" is a common projector idiom — bootstrap on a genesis event, recompute on a lifecycle change. On the default merge it is **silently unable to remove a field**: a merge only adds and overwrites, never deletes, so keys present in the stored row but absent from the recomputed object survive. A resume that recomputed only the *enabled* flag definitions could not drop the `false`s a suspension had baked in, and eight nav sections stayed collapsed forever.

- A write representing the **complete** state of a row (full rebuild / snapshot / re-projection) MUST pass **`{ replace: true }`**.
- To clear a field, use **`unset( id, key, options? )`** (`pv3-types/src/database.ts`; Postgres `data #- '{…}'`, MemoryDb `dissocPath`). **`upsert` with `undefined` is a no-op** — a deep merge cannot drop a key. These are the two halves of "how do I remove something from a projected row".

**MemoryDb-green is not Postgres-green — and here the harness cannot even express the bug.** MemoryDb's `upsert( id, data )` takes **no options argument at all**, so `{ replace: true }` is *silently ignored*; its object-valued upsert replaces subtrees regardless, so a MemoryDb test of a rebuild passes for the wrong reason and reassures in exactly the place it must not. **Prove a complete-state-with-removals write on the real adapter (testcontainer Postgres), or state in the PR that it is unproven.** Two sibling divergences deserve the same treatment: an **absent** field (`undefined !== 'x'` keeps the row in MemoryDb, while `NULL <> 'x'` is NULL and **drops** it in Postgres), and **`op:'contains'`**, which is array containment — it substring-matches a string field in MemoryDb and matches **nothing** in Postgres (six live admin search boxes were dead in production because of it).

### Cross-stream counters (multi-stream keyed readmodel)

The per-stream in-order guarantee does **NOT** protect a readmodel whose key (e.g. `correlationId`) groups events from many streams — cross-stream order is not guaranteed, and read-then-write counters are a classic lost-update race. (A non-convergent *same-stream* projection still needs the version watermark for duplicates — see *Event delivery* above.)

**Pattern: atomic increment + CAS-filtered status write.**

```typescript
RuleExecutionCompleted: async ( event ) => {
  const correlationId = event.metadata?.correlationId;
  if ( !correlationId ) return;

  // 1. DB-native atomic increment (PG: SELECT … FOR UPDATE; Mongo: $inc)
  const updated = await coll.atomicIncrement( correlationId, { completed: 1 });
  if ( !updated ) return;

  const { completed, failed, total } = updated;
  const status = computeStatus( completed, failed, total );

  // 2. CAS the status: only write if counts haven't drifted since our read,
  // so a stale projector view can't regress a freshly-written status.
  await coll.updateMany({ id: correlationId, completed, failed }, { status });
}
```

Use whenever the readmodel key is a non-stream value (`correlationId`, `userId`, …) and projectors mutate counters.

#### Redelivery-idempotent increments: delta-vs-applied contribution ledger

**Plain `atomicIncrement` is NOT redelivery-idempotent.** It solves the concurrency race, but an at-least-once **redelivered** event re-adds its contribution and double-counts the total — which then corrupts anything the total gates (a period-close equilibrium check, a zero-balance lock guard). For an *accumulating* cross-stream counter, pair the increment with an idempotency ledger:

- Record each contribution as an **immutable fact keyed by a deterministic id** (e.g. `${entryId}-${lineIndex}`) in a sibling `_applied` collection.
- Increment the total only by the **delta versus what that key already recorded**: a redelivery finds the same stored contribution → delta 0 → true no-op. Two distinct events touch different contribution keys and different `atomicIncrement`s, so cross-stream concurrency is unaffected.
- **Known residual (document it):** read-contribution → increment → record-contribution is not one transaction, so a crash mid-sequence or a genuinely *concurrent* double-delivery of the same event can over-count once. Sequential redelivery (the common case) is closed; the rare windows are recoverable by recomputing the rollup from the ledger facts — reconcile is the belt-and-suspenders follow-up.

Reference shape: an existing cross-stream balance/rollup readmodel with a sibling `_applied` contribution-ledger collection.

#### Brand-new-row bootstrap: identity-only upsert + per-field CAS init

When no single "genesis" event opens the row (any of N streams can be first to touch a key), bootstrap the row **without writing any counter field**, then CAS-init each counter to `0` exactly once. The `readById` → `upsert(fullSkeletonOfZeros)` pattern is a lost-update race: event A's `readById` sees "no row", event B's skeleton + first `atomicIncrement` land, then A's skeleton shallow-merges zeros over B's incremented field — permanently losing the delta.

```typescript
const initializeFieldOnce = async ( id: string, field: keyof Row ): Promise<void> => {
  // `op: 'notExists'` emits `IS NULL`: matches a row whose field is absent and
  // ONLY then sets it to 0. A racing initializer on an already-incremented
  // field fails the CAS and is a no-op — prior increments are never clobbered.
  await coll.updateMany(
    [{ field: 'id', op: 'eq', value: id }, { field, op: 'notExists' }],
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

// Same primitive for once-only non-numeric labels (e.g. a currency/category
// derived from the first-touched event for the key):
const setCurrencyOnce = async ( id: string, currency: string ): Promise<void> => {
  await coll.updateMany(
    [{ field: 'id', op: 'eq', value: id }, { field: 'currency', op: 'notExists' }],
    { currency }
  );
};
```

**Use `op: 'notExists'`, NOT `{ op: 'eq', value: null }`.** On Postgres the latter compiles to `data#>>'{field}' = NULL`, never TRUE in SQL — zero rows match, the field is never initialized, and the first `atomicIncrement`'s STRICT `jsonb_set( …, NULL )` nulls the entire `data` column (crashing with `Cannot read properties of null`). Postgres-only: Mongo's `$eq: null` matches absent fields, so a Mongo-backed test passes while production fails. `notExists` emits `IS NULL`, which matches the absent key. (The adapter's `atomicIncrement` was also hardened with `COALESCE(( data->>'field' )::int, 0 )`.)

After `ensureRow`, every numeric field is non-null — `0` for a new row, or its prior incremented value. `atomicIncrement` then operates safely against PG's `(data->>'field')::int + delta` (a `null` field resolves the arithmetic to `NULL` and silently zeros the running total — a separate footgun the bootstrap prevents). Reference shape: an existing cross-stream balance/counter readmodel with `ensureRow` / `initializeFieldOnce`, plus a regression test "Given concurrent cross-stream projection of one key / when the first two events for a brand-new key interleave".

### Database Indexes

Call `ensureIndex()` for every field or compound field set used in query filters — not just the primary key. Missing indexes cause full table scans at scale.

```typescript
database.onStarted( async () => {
  await myCollection.ensureIndex(['id']);                    // Primary key
  await myCollection.ensureIndex(['active', 'nextRunAt']);   // Compound query filter
  await myCollection.ensureIndex(['status']);                // Single-field filter
});
```

#### Array-of-string fields → GIN, not the default B-tree

Fields holding arrays of strings queried with `op: 'contains'` (e.g. `hierarchyEntityIds`, `triggeringEvents`, `tags`, any `*Ids: string[]`) MUST pass `{ strategy: 'gin' }`. The default strategy materializes a `text`-typed `GENERATED ALWAYS` column from `data#>>'{field}'` — the JSON *text serialization* (`'["abc"]'` as a literal string). The PG adapter's `getFieldAccessor` then short-circuits to that text column for `op: 'contains'` (ignoring the `asText: false` hint when a registered generated column exists), producing `text_column @> '[…]'::jsonb` — a runtime `operator does not exist: text @> jsonb`. GIN indexes the JSONB path `data#>'{field}'` and registers no generated column, so the accessor falls through to the JSONB form and `@>` resolves.

```typescript
database.onStarted( async () => {
  await coll.ensureIndex([ 'accountId', 'status' ]);                 // scalars → default B-tree
  await coll.ensureIndex([ 'hierarchyEntityIds' ], { strategy: 'gin' });
  await coll.ensureIndex([ 'triggeringEvents' ], { strategy: 'gin' });
});
```

**Migrating an existing readmodel** (a prior default-strategy boot already materialized the broken text column): changing `ensureIndex` is NOT enough — `loadGeneratedColumns` re-discovers existing `GENERATED ALWAYS` columns from `information_schema` at startup and re-populates the registry. Drop the stale columns once:

```sql
ALTER TABLE <table> DROP COLUMN IF EXISTS <snake_case_field> CASCADE;
```

Reference shape: an existing readmodel calling `ensureIndex` with `{ strategy: 'gin' }`.

### Query-route gotchas: subscribable base routes need a `params` schema; base routes reject `filter`

Two route-level traps that 400 only at runtime (invisible to unit tests), typically hit when a front-end first subscribes to / filters a correlation-keyed batch readmodel:

1. **A subscribable base route (`/x/:id?`) MUST declare `schemas.params`.** Without it, PV3's default validation applies `additionalProperties: false` and rejects the optional path param the readmodel **subscription** sends — `400 VALIDATION_ERROR` ("must NOT have additional properties: <param>"). A route registered with only `transformers` + `subscriptions` (no `schemas`) is the trap:

   ```typescript
   .withQuery({
     route: '/rule-execution-batches/:correlationId?',
     schemas: { params: S.shape({ correlationId: S.string().optional() }) }, // REQUIRED for the subscription
     transformers: [ FilterByAccountIdTransformer( false ), FilterByScopeTransformer() ],
     subscriptions: [ports.realtimeSession.readmodelSubscription]
   })
   ```

   Two refinements, because the rule as usually stated is both too loose and too absolute:

   - **The schema must declare *the route's own* param**, matching `.withIdProperty(…)` where one is set. A route on `:documentId?` declaring `params: S.shape({ id: … })` is exactly as broken as declaring nothing — and just as invisible, because the plain GET keeps working and only the subscription fails. "Needs a params schema" reads as satisfied by any params schema.
   - **It is a hardening, not an absolute.** A subscribable `:id?` route with **no** params schema works today on this PV3 version. Say so, because the over-absolute form is the more corrosive error: someone debugging an unrelated 400 seizes on a missing params schema as the root cause and "fixes" something that was never broken.

   Greppable symptom either way: subscription `400 must NOT have additional properties: <param>`, with the plain GET unaffected — so it presents as *"live updates don't arrive but a refresh fixes it"*, which gets misattributed to realtime plumbing rather than route validation.

2. **A base route with no custom `queryHandler` rejects a `filter` query param.** Only the `-search` variant — which declares `query: defaultQuerySchemas.query` and a `queryHandler` applying `params.filter` — accepts `filter`/`limit`/`offset`/`sort`. A *filtered* front-end query (e.g. `status:'running'`) MUST call `XSearch({ filter })`, not the base `X({ filter })`. Add the `-search` route whenever the FE needs filter/pagination; the base route is "get one by id / get all".

## Module Composition

Modules export `create()` from `index.ts` — no `@Module` class, no `app.module.ts`:

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

### `onStarted` is not a queue — a boot hook must be correct under **both** boot orders

`createPort.onStarted` (`pv3/packages/pv3/src/ports/base.ts`) runs the callback **immediately** if the port has already started, and only queues it otherwise:

```ts
onStarted: ( fn ) => {
  if ( instance.isStarted ) { runStartedCallback( fn ); return; }   // ← runs NOW
  emitter.once( 'started', () => runStartedCallback( fn ));
}
```

| boot order | who | `onStarted` |
|---|---|---|
| modules load → `eventstore.start()` | the real server (`setupPorts` → `setupServices` → `ports.eventstore.start()`) | callbacks **queued**, fired together once every declaration exists |
| `start()` → modules load | the **Postgres integration harness**, and any lazy module load | each callback fires **immediately, interleaved** with the declarations after it |

**Rule: code that reconciles a *set* inside a boot hook must tolerate declarations arriving while a reconcile is in flight.** A single-flight guard must **re-arm** — a dirty / `redrainRequested` flag that re-runs the loop — never `return` and drop the request. Under the second order a bare `if ( draining ) return` discards everything after the first declaration:

```
A declares → A's hook fires NOW → drain snapshots [A], awaits, yields
B declares → B's hook fires NOW → drain sees `draining` → returns; B DROPPED
C declares → same → C DROPPED
```

B and C never even *attempt* — no success log, no failure log, no metric. Two production cron subscriptions stopped registering, while the monolith was unaffected, `yarn test` was green across 399 suites, and a per-unit lift gate was 288/288 green: it probes one unit per process, so it never has two such policies sharing state.

**Testing note.** The MemoryDb harness does not call `eventstore.start()`, so hooks never fire there; the **Postgres** harness does, and is the only in-process gate that exercises the start-first order. A regression test for this class must drive the *immediate* branch deliberately — a rig that collects callbacks and fires them later reproduces only the monolith order and passes on broken code. This inverts the usual intuition that integration tests are the slow, redundant tier: here they were the only tier with the coverage. (`create-policy`'s "register your cron subscription at boot" idiom is exactly this shape.)

## Dependency Injection

PV3 uses the Ports pattern (closure-based DI) — no decorators, no `@Inject`/`@Injectable`:

```typescript
export const MyComponent = ( ports: Ports ) => {
  // ports.eventsourcing, ports.database, ports.log, etc.
  return /* builder */;
};
```

### Artifact Constructor Signature — the MDU/Lift Contract

**Every artifact factory — aggregate, policy, readmodel, system — takes EXACTLY `( ports )`. Never add a second constructor parameter or inject a dependency any other way.**

This is a hard deployment invariant, not style. PV3's manifest loader (`@bett3r-dev/pv3` → `selectiveLoader.ts:loadFromManifest`) instantiates every lifted artifact uniformly as `factory( scopedPorts )` — one argument, always. `MyPolicy( ports, something )` receives `undefined` for `something` in any lifted deployment unit: it works in the monolith, passes unit tests and single-process E2E, then breaks **silently in production** under MDU distribution. No build, type, or test gate catches it.

Equally load-bearing: **a module's `create( ports )` does NOT run in the lift path** — only an optional per-module `setup.ts` (matched by filename) plus the individual artifact factories execute. So per-artifact dependencies cannot be wired in `create()` either.

```typescript
// ❌ WRONG — undeployable. `engine` is undefined in any lifted unit.
export const RunnerPolicy = ( ports: Ports, engine: SomeEngine ) => { ... };

// ✅ RIGHT — artifact takes only ( ports ); reaches its infra via a lazy
//    process-singleton owned by the infra's library/package.
export const RunnerPolicy = ( ports: Ports ) => {
  const engine = getEngine( ports );  // builds-and-caches on first use, wherever this artifact lands
  ...
};
```

**The `getX( ports )` lazy process-singleton pattern** — for infra consumed by a single artifact/module (an engine, a specialized client) AND for multi-consumer infra (e.g. a registry shared by several modules): own it inside the owning (or a shared) library package, built from `ports` on first access, exposed via `getX( ports )` plus `setX(...)` / `resetX()` overrides as the test/E2E seam. Do NOT put single-module infra on the global `Ports` type (see composition-root rule), do NOT pass it as a 2nd constructor arg, do NOT cross-import from a sibling server module folder. The classic MDU violation is passing a registry as `( ports, registry )` to N artifacts across modules — fine in the monolith, `undefined` in any lifted unit.

**Singleton test seam:** integration harness calls `resetX()` per harness; unit tests `setX(...)` in `beforeEach` and `resetX()` in `afterEach` (the singleton captures `ports`, so a stale instance points at a torn-down DB / leaks across files in a shared jest worker).

NOTE: runtime *helpers* called from within a handler are NOT lift-loaded artifacts — they keep taking resolved dependencies as parameters; only artifact FACTORIES must take `( ports )` only.

This invariant is invisible to every automated test — guard it at design time. Reject any plan or diff that gives an artifact a non-`( ports )` signature or wires single-consumer infra at the composition root.

### Composition Root Boundary

`setupPorts.ts` — and its siblings `setupGenerationPorts.ts` / `setupE2ETestPorts.ts` — may declare **only** ports consumed by **more than one module**, or by service infrastructure itself (logger, cache, db, eventstore, mailer, …).

**A port consumed by exactly one module is a defect.** Single-module construction — tool catalogs, diagnostic adapters, engine/registry registration, prompt building, a specialized client — belongs in the owning module's library via a `getX( ports )` lazy singleton (above), not in the composition root or on the global `Ports` type. Canonical violation: hundred-plus LOC of one module's infra in `setupPorts.ts`, leaking its engine/client as a port through `Ports` and both parallel setups.

**Test/E2E seam without a global port:** follow the test-server precedent (skip the uniform `loadModulesFromDirectory` loop for that module in the test-server bootstrap and call its register function directly with the mock injected), or use the singleton's `setX` / `resetX`. Never reintroduce a global port just for a test seam.

**Review heuristic:** any net addition to `setupPorts.ts` (or the two parallel setups) must be justified by multi-consumer or infrastructure use; a net-new single-module port is a placement defect.

### Logger

Use `ports.log` — a pre-scoped `LoggerType` automatically named after the module directory (e.g. `"accounting"`), injected by `loadModulesFromDirectory`. Only use `ports.logger.createLoggerInstance('custom-name')` for a sub-scoped logger within a module.

## Auth Endpoints: Use `context.user`, Not `x-auth-*` Headers

Every PV3-registered endpoint has the authenticated user in `context.user` (userId, accountId, userType, roles, permissions, scopes), populated by `AddDevAuthUserToRequest` in all environments (dev, E2E, production-behind-gateway).

**Never read `req.headers['x-auth-user-id']` / `x-auth-account-id` etc. in endpoint action code.** They are gateway transport headers (e.g. Traefik ForwardAuth) between gateway and backend, not a public API. In E2E, `AddDevAuthUserToRequest` populates only `context.user`, so header reads silently receive `undefined` in tests.

**E2E debugging note:** source changes in workspace packages (auth package, domain package, …) are NOT picked up live during E2E — they have `"main": "build/index.js"` and `ts-node` resolves the compiled output. Edit `build/` or rebuild the package to instrument; files under `<serverPath>/` load from source.

## Endpoint Properties

Two independent identity properties, both auto-derived from the filesystem via `getStackTrace()`; explicit overrides via `withSubdomain()` on builders or factory params on external packages:

| Property | Type | Purpose |
|----------|------|---------|
| `loggingModule` | `string` (always set, kebab-case) | Log grouping/filtering. Auto-derived from artifact name. |
| `subdomain` | `string \| undefined` (kebab-case) | Business domain for authorization. Auto-derived from `modules/<name>/` directory. Validated against `SubdomainModules` at startup. |

Manual endpoints use compile-time validation:

```typescript
endpoints.registerEndpoint({
  loggingModule: 'my-endpoint',
  subdomain: 'my-subdomain' satisfies SubdomainModule,
  // ...
});
```

## Invariant Placement

Every domain invariant must be enforced synchronously by an **aggregate** — the consistency boundary; an invariant enforced anywhere else is not actually guaranteed. An invariant validated in a policy (async, eventually consistent) or a readmodel (a projection) is a **design defect** — wrong aggregate boundaries or a malformed invariant — to fix at the design level, never a placement to rationalize. When an invariant seems hard to place (e.g. needs visibility across sibling streams), do NOT move it to a policy: surface the boundary tension and re-examine the aggregate. (Example: an overlap/uniqueness invariant needing cross-row visibility stays on the aggregate that owns the rows/windows it checks.)

## Gating Non-Production Features

Dev-only backend features (test channels, dev tooling, debug endpoints) get a single registration-time guard at the **module composition root** — the module's `create( ports )` or registry registration, e.g. `if ( process.env.NODE_ENV !== 'production' ) { ... }`. A dev-tools module that registers no route in prod produces no Fastify route and no OpenAPI entry — that's the precedent.

**Never** gate by conditionally adding commands to an aggregate's `.withCommands(...)` map (`let additionalCommands = {}; if ( !prod ) { ... }`). The command surface feeds build-time generated artifacts that are environment-invariant by design — `.deployment-units.json`, `.openapi.json`, the generated client library, the rules-engine `node-registry.json` — so an env-conditional command makes a dev-built manifest/OpenAPI/client advertise a command prod doesn't have. Reinforce at the deployment layer by leaving the unit out of production `lift:` patterns. (Anti-pattern: a dev-only authorize command conditionally added to a tenant aggregate.)

## Realtime Subscriptions: Signal Mode

Signal mode (`x-subscription-changes: signal`) delivers `{ type: 'signal' }` to the consumer's `onChange` — it does **not** re-execute the original query, and should stay that way. The consumer (data policy) implements refetch itself: on a signal, call `backend.queries.X({ ...currentFilter })` and dispatch the result, with a small (~200ms) debounce to coalesce bursts. Don't extend the client-library generator to auto-refetch — consumers differ in filter sources, debounce windows, and ordering needs.
