# PV3 read models — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

**If the projection is not a pure last-write-wins `upsert`** — it appends, increments, accumulates, or exposes intermediate state — **read [DELIVERY.md](./DELIVERY.md) first.** `ReadmodelBuilder` applies the per-stream version watermark for you, but the duplicate/ordering contract it is protecting you from is stated there, and it is what a cross-stream-keyed projection has to handle itself.

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
- Project `ownerId: event.metadata?.userId` in creation event projectors — **except** for the tenant-scoped-but-not-row-scoped carve-out in [AGGREGATES.md](./AGGREGATES.md) (`['all']`-only collapsed resources), which omit it entirely
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

The per-stream in-order guarantee does **NOT** protect a readmodel whose key (e.g. `correlationId`) groups events from many streams — cross-stream order is not guaranteed, and read-then-write counters are a classic lost-update race. (A non-convergent *same-stream* projection still needs the version watermark for duplicates — see [DELIVERY.md](./DELIVERY.md).)

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
