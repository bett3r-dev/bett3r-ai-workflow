# PV3 aggregates — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

**Changing an existing aggregate's state or event fields?** Aggregate state rehydrates from persisted events **by field name**, so renaming or removing one is schema evolution, not a rename — read [SCHEMAS.md](./SCHEMAS.md) → *Renaming a persisted field* before touching it.

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
