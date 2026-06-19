---

## description: Scaffold an event-driven read model (projection) for querying. Use when adding query-side projections from events.

# Skill: Create Readmodel

Scaffold a PV3 read model that projects events into a queryable collection.

## Project configuration

This skill resolves the following placeholders from your repo's `.esas.config.json`:


| Placeholder                  | `.esas.config.json` field                                                                 | Example value                        |
| ---------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------ |
| `<domainEventsPath>`         | `domainEventsPath`                                                                        | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>`  | `domainEventsPackageName`                                                                 | `@bett3r-dev/teselly-domain`         |
| `<serverPath>`               | `serverPath`                                                                              | `src/services/server`                |
| `<clientLibraryPackageName>` | `clientLibraryPackageName`                                                                | `@bett3r-dev/teselly-client-library` |
| `<domainUtilsPackageName>`   | `domainUtilsPackageName` *(optional; defaults to `<domainEventsPackageName>` + `-utils`)* | `@bett3r-dev/teselly-domain-utils`   |


The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Pattern

```typescript
import S from '@bett3r-dev/jsonschema-definer';
import { extractIdFromEventStream, ReadmodelBuilder } from '@bett3r-dev/pv3';
import { defaultQuerySchemas, UnauthorizedError } from '@bett3r-dev/pv3-types';
import { MyEvents } from '<domainEventsPackageName>';
import { FilterByAccountIdTransformer, FilterByScopeTransformer } from '<domainUtilsPackageName>';
import { Ports } from 'ports';

export const MyReadmodel = (
  { database, realtimeSession, databaseSessionMode }: Ports,
  collection: string = 'domain_entity_readmodel'
) => {
  const myCollection = database.getCollection<MyReadmodelType>( collection, 'id' );

  database.onStarted( async () => {
    await myCollection.ensureIndex(['id']);
  });

  const { EntityCreated, EntityEdited, EntityStatusChanged } = MyEvents;

  return ReadmodelBuilder( MyReadmodelSchema, { EntityCreated, EntityEdited, EntityStatusChanged })
    .withDatabase( database, collection, databaseSessionMode )
    .withProjector(() => ({
      EntityCreated: async ( event ) => {
        return myCollection.upsert( extractIdFromEventStream( event ), {
          ...( event.data as any ),
          accountId: event.metadata.accountId,
          ownerId: event.metadata?.userId
        });
      },
      EntityEdited: async ( event ) => {
        return myCollection.upsert( extractIdFromEventStream( event ), event.data as any );
      },
      EntityStatusChanged: async ( event ) => {
        return myCollection.upsert( extractIdFromEventStream( event ), {
          status: event.data!.status
        });
      }
    }))
    // Default query: get by ID with real-time subscription
    .withQuery({
      route: '/domain/entities/:id?',
      transformers: [FilterByAccountIdTransformer( false ), FilterByScopeTransformer()],
      subscriptions: [realtimeSession.readmodelSubscription]
    })
    // Search query with pagination
    .withQuery({
      route: '/domain/entities-search/:search?',
      schemas: {
        query: defaultQuerySchemas.query,
        params: S.shape({
          search: S.string().optional()
        }),
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
    })
    // Count query
    .withQuery({
      route: '/domain/entities-count/',
      schemas: {
        query: defaultQuerySchemas.query,
        response: S.shape({
          count: S.number()
        })
      },
      transformers: [FilterByAccountIdTransformer(), FilterByScopeTransformer()],
      queryHandler: async ( _, params ) => {
        const { context: { user }} = params.params;
        if ( !user ) throw new UnauthorizedError( 'User must be authenticated' );
        const count = await myCollection.count({ filter: params.filter });
        return { count: count || 0 };
      }
    });
};
```

## File Location

```
<serverPath>/src/modules/<module-name>/<entity>.readmodel.ts
```

All inline — no separate service file, no controller file.

## Registration

In the module's `index.ts`:

```typescript
ports.eventsourcing.routeEventHandler( MyReadmodel( ports ));
```

## Collection Naming

Follow the pattern: `{domain}_{entity}_readmodel`

Examples:

- `sales_orders_readmodel`
- `inventory_warehouses_readmodel`
- `billing_entities_readmodel`

## Projector Patterns

### Simple upsert

```typescript
EntityCreated: async ( event ) => {
  return myCollection.upsert( extractIdFromEventStream( event ), {
    ...( event.data as any ),
    accountId: event.metadata.accountId,
    ownerId: event.metadata?.userId
  });
}
```

### Merge/update

```typescript
EntityEdited: async ( event ) => {
  return myCollection.upsert( extractIdFromEventStream( event ), event.data as any );
}
```

### Cross-aggregate event (ID from event data, not stream)

```typescript
DocumentGenerated: async ( event ) => {
  if ( !event.data!.entityId ) return;
  return myCollection.upsert( event.data!.entityId!, {
    documentFileUrl: event.data!.fileUrl
  });
}
```

### Enriching with external data

```typescript
RelatedEntityAssigned: async ( event ) => {
  const clientLibrary = createClientLibrary( { baseUrl: '' }, endpoints.fetch );
  const relatedEntity = await clientLibrary.queries.RelatedEntitiesById(
    event.data!.relatedEntityId
  );
  return myCollection.upsert( extractIdFromEventStream( event ), { relatedEntity });
}
```

## Query Patterns

### Default by-ID query (with real-time subscription)

```typescript
.withQuery({
  route: '/domain/entities/:id?',
  transformers: [FilterByAccountIdTransformer( false ), FilterByScopeTransformer()],
  subscriptions: [realtimeSession.readmodelSubscription]
})
```

### Search with pagination

Requires `schemas` with query/params/response and a `queryHandler`.

### Count-only query

Returns just the count, useful for dashboards.

### Distinct field query

```typescript
const byDistinctField = params.params.query?.byDistinctField || null;
const count = await myCollection.count({
  filter: params.filter,
  ...( byDistinctField ? { byDistinctField } : {})
});
```

## Schema Import Convention

Readmodel schemas **MUST** be defined in the domain package (`<domainEventsPackageName>`, in `*-integration.types.ts` files) — never inline in the readmodel file. The client library generator and OpenAPI spec derive types from the domain package. Inline schemas produce untyped or incomplete generated artifacts:

```typescript
// CORRECT — import from the domain package in server modules
import { MyReadmodelSchema } from '<domainEventsPackageName>';
```

## Critical Constraints

- **Route params require `schemas.params`** — If `route` contains `:param` tokens (e.g. `:userId?`), declare them in `schemas.params`. Without it the framework cannot extract or validate the param, and transformers won't receive it. Optional tokens must still be declared (mark the field `.optional()`):
  ```typescript
  .withQuery({
    schemas: {
      params: S.shape({ userId: S.string().optional() })
    },
    route: '/identity/auth-user-security/:userId?',
    transformers: [ FilterByAccountIdTransformer(), FilterByScopeTransformer() ]
  })
  ```
- **Subscriptions require `databaseSessionMode`** — If a `.withQuery({ ... })` declares `subscriptions: [...]`, you MUST pass `databaseSessionMode` as the THIRD arg: `.withDatabase( database, collection, databaseSessionMode )` (destructure it from `Ports`). It wires the change-stream `watch` that powers live deltas. The two-arg form compiles and even serves the initial subscription snapshot, so the omission fails **silently** — subscribers get the snapshot but no live updates (UI refreshes only on full page reload). NOTE: a subscription request correctly returns **204** (snapshot/deltas flow over the realtime channel, not the HTTP body) — a 204 is NOT evidence the subscription is broken.
- **Subdomain reflects domain ownership** — `.withSubdomain('X')` must name the domain the data conceptually belongs to, and must agree with the readmodel file's module location. Never pick a subdomain for authorization convenience or to avoid a permissions-catalog/registry diff (don't borrow another subdomain's capability gate). If the right gate doesn't exist, add it under the correct subdomain.
- **No cross-subdomain `getCollection`** — A readmodel's `database.getCollection('<name>')` accessor is for that readmodel's OWN projectors/queries only. Never open **another** subdomain's readmodel table (`ports.database.getCollection('<other-subdomain>_*_readmodel')`) — its table name/id-shape/schema are private. Cross-subdomain reads go through the client library (`backend.queries.X`), exactly as cross-module writes go through it.
- **Always use `upsert`** — Never `insert`. Upsert ensures idempotency on replay.
- **No separate controller** — All HTTP endpoints defined via `.withQuery()`
- **No separate service file** — Projection logic lives inline
- **No `.withName()`** — PV3 ReadmodelBuilder doesn't need it
- **No `.withControllerPrefix()`** — Routes are defined per-query
- **Always authenticate queries** — Check `user` exists, throw `UnauthorizedError` if not
- **Always use `FilterByAccountIdTransformer()`** — For multi-tenant data isolation
- **Always use `FilterByScopeTransformer()`** — For permission-based scope filtering (add AFTER `FilterByAccountIdTransformer`)
- **Admin-operated readmodels** — When a readmodel is admin-only and `accountId` is an ordinary caller-supplied filter (no tenant scoping), do NOT use `FilterByAccountIdTransformer`. Use `RequireAdminTransformer()` (from `<domainUtilsPackageName>`) instead — it rejects non-admin and unauthenticated callers. Authentication alone is insufficient when a route exposes a `accountId` query parameter.
- **Always project `ownerId`** — Add `ownerId: event.metadata?.userId` in creation event projectors
- **Handle missing data gracefully** — Return empty arrays/0 counts, don't throw
- **Defensive guards** — Check `if ( !event.data!.field ) return;` for cross-aggregate events
- **NULL-safe default-exclude filters on optional fields** — When adding a transformer that filters out rows by an optional field (e.g. "hide rows whose `kind` equals a particular value by default"), a plain `{ field: 'kind', op: 'neq', value: 'excludedKind' }` is WRONG. In SQL three-valued logic `data#>>'{kind}' != 'excludedKind'` evaluates to NULL (treated as false in WHERE) for every row where the field is absent — silently hiding every ordinary row. Use an OR that handles absence explicitly: `{ OR: [{ field: 'kind', op: 'notExists' }, { field: 'kind', op: 'neq', value: 'excludedKind' }] }`. Note: nested AND/OR clause-detection issues are easy to flag, but the NULL handling of the appended exclusion itself is easy to miss — when reviewing default-exclude transformers, test the **ordinary-row-survives** case explicitly.

## Database Indexes

Ensure indexes on the primary key AND every field or compound field set used in query filters:

```typescript
database.onStarted( async () => {
  await myCollection.ensureIndex(['id']);                    // Primary key (always)
  await myCollection.ensureIndex(['active', 'nextRunAt']);   // Compound query filter
  await myCollection.ensureIndex(['status']);                // Single-field filter
});
```

Missing indexes cause full table scans at scale. If the readmodel is queried by `active + nextRunAt`, add `ensureIndex(['active', 'nextRunAt'])`.

## Cross-stream counters (multi-stream keyed readmodel)

If the readmodel key (e.g., `correlationId`) groups events from multiple aggregate streams and the projector mutates counters, PV3's per-stream in-order guarantee does not protect you — concurrent read-modify-write loses updates. Use atomic increment + CAS:

```typescript
RuleExecutionCompleted: async ( event ) => {
  const correlationId = event.metadata?.correlationId;
  if ( !correlationId ) return;
  const updated = await coll.atomicIncrement( correlationId, { completed: 1 });
  if ( !updated ) return;
  const { completed, failed, total } = updated;
  await coll.updateMany(
    { id: correlationId, completed, failed },     // CAS filter on captured counts
    { status: computeStatus( completed, failed, total ) }
  );
}
```

This is the pattern for any batch-rollup readmodel keyed by a correlation id whose per-batch counters are advanced by events from many sibling streams. See the `ddd-patterns` skill → "Cross-stream counters".

### Brand-new-row bootstrap when no "genesis" event exists

When the key (e.g. `clientAccountId`) has no single opening event — any of N aggregate streams can be the first to touch the row — DO NOT bootstrap with `readById` → `upsert(fullSkeletonOfZeros)`. Two first-touch events for a brand-new key can interleave so event A's `readById` returns "no row", event B's full skeleton + first `atomicIncrement` land, then A's skeleton upsert shallow-merges its zeros over B's incremented field — permanently losing the delta.

Use **identity-only upsert + per-field CAS-init** instead:

```typescript
const initializeFieldOnce = async ( id, field ) => {
  // CAS filter `value: null` matches a row whose field is null OR absent.
  // A racing init that loses sees the field already non-null, fails the CAS, no-op.
  await coll.updateMany(
    [
      { field: 'id',  op: 'eq', value: id },
      { field, op: 'eq', value: null as unknown as number }
    ],
    { [field]: 0 }
  );
};

const ensureRow = async ( id ) => {
  await coll.upsert( id, { id, ...identityFields });  // NO numeric field
  for ( const field of NUMERIC_FIELDS ) await initializeFieldOnce( id, field );
};
```

Same primitive shape for once-only non-numeric labels (e.g. an account `currency` derived from the first-touched ledger event) — a `setCurrencyOnce` helper with a `{ currency: null }` CAS filter.

NOTE on `notExists` vs `eq null`: the two CAS-filter forms are NOT interchangeable across database engines. On PostgreSQL a `{ field, op: 'eq', value: null }` filter matches a row whose JSON field is literally `null` AND a row where the field is absent (both reduce to "no concrete value"); some Mongo-style adapters distinguish absent (`notExists`) from explicitly-`null`. When the brand-new row is created identity-only (the numeric field truly absent, not written as `null`), confirm your adapter's `op: 'eq', value: null` matches absent fields — if it does not, use `op: 'notExists'` for the init CAS filter. A regression test should cover the case where the very first two events for a brand-new key interleave.

## Bulk-projection branch (completion-event trigger)

For spreadsheet-style bulk save flows, the projector reacts to a `*BulkOperationCompleted` event, reads the correlated per-row events via `ports.eventstore.read({ correlationId, events: [perRowEventName] })`, and applies one `UPDATE … FROM unnest(...)` plus `notifyInvalidate` inside one PG transaction. Per-row events have no direct projector subscriber. Look at an existing bulk-completion readmodel under `<serverPath>/src/modules/` in your repo for a working reference — the interesting parts are a `projectBulkCompletion` helper and the raw-SQL transactional update pattern. CAS / per-item watermarks are unnecessary here because per-stream in-order delivery already serializes the relevant events.

```typescript
BulkOperationCompleted: async ( event ) => {
  const correlationId = event.metadata?.correlationId;
  const accountId = event.metadata?.accountId;
  if ( !correlationId || !accountId ) return;

  const perRowEvents = await ports.eventstore.read({
    correlationId,
    events: [ 'ItemValueChanged' ]
  });
  if ( !perRowEvents.length ) return;

  const { pool, notifyInvalidate } = ports.database._adapter();
  const client = await pool.connect();
  try {
    await client.query( 'BEGIN' );
    await client.query(
      `UPDATE ${collection}
         SET data = jsonb_set( data, ARRAY['values', $1::text], to_jsonb( u.value ))
         FROM unnest($2::text[], $3::numeric[]) AS u( itemId, value )
        WHERE id = u.itemId AND data->>'accountId' = $4`,
      [columnKey, itemIds, values, accountId]
    );
    await notifyInvalidate( client, collection, { accountId });
    await client.query( 'COMMIT' );
  } catch ( err ) {
    await client.query( 'ROLLBACK' );
    throw err;
  } finally {
    client.release();
  }
}
```

## Variant: event-ID-keyed audit-timeline read model

A read model can be an **audit / navigation timeline** rather than a per-aggregate
projection. Instead of one row per aggregate keyed on `extractIdFromEventStream( event )`,
it writes **one row per event** keyed on `event.id!`, fanning in from *all* the aggregate
streams in a module. It is a navigation surface, **not a source of truth** — each row is a
thin pointer the UI hydrates from the dedicated read model the `ref` points at. A worked
reference is an activity timeline that spans every aggregate stream in a module via
one projector per relevant event.

Key differences from the default pattern above:

- **Key on `event.id!`, not `extractIdFromEventStream( event )`.** Granularity is per
*event* (one timeline row per event), not per aggregate. The event id is unique and
stable, so `upsert( event.id!, row )` is naturally idempotent under outbox redelivery —
and **no `atomicIncrement` / CAS** is needed (every row is independent; there is no
cross-stream counter race, unlike a rollup such as a balances readmodel).
- **Append-only.** Every projector does exactly one `upsert( event.id!, row )` — never
`updateMany` on an existing row. A correction is its own new row.
- **Fan in from many event namespaces.** Destructure the events you want from each
aggregate's `*Events` export and pass the union to `ReadmodelBuilder`:
  ```typescript
  const { EntityCreated, EntityArchived } = EntityAEvents;
  const { EntityBSettled, EntityBFailed } = EntityBEvents;
  ReadmodelBuilder( ActivitySchema, { EntityCreated, EntityArchived, EntityBSettled, EntityBFailed })
  ```
- **Guard `event.data`.** Every projector starts with
`const data = event.data!; if ( !data.<groupingKey> ) return;` so an event missing the
grouping key is skipped, not projected as a partial row.
- **Thin typed `ref`.** Project a flat `ref: { id, type }` (defined as
`S.shape({ id: S.string(), type: S.string() })` in the domain package), not the full source
payload. A flat `{ id, type }` references entities across many aggregates without a
discriminated union (jsonschema-definer cannot express one).
- `**actor` resolution.** `actor = event.metadata?.userId ?? '<fallback>'` — the user for
admin-initiated events; the emitting policy's name constant for system events; a shared
`'system'` sentinel for admin events that lost their `userId`.
- **Index the listing sort field.** If the timeline exposes an unfiltered "all rows,
most-recent-first" listing, `ensureIndex` the bare sort field (e.g. `['timestamp']`) — the
fan-in table is unbounded and would otherwise full-scan + in-memory-sort.
- **Admin-operated?** If the route exposes a caller-supplied account filter with no tenant
scope, use `.withSubdomain( '' )` + `RequireAdminTransformer()` instead of
`FilterByAccountIdTransformer` / `FilterByScopeTransformer`.

## Reference Files

Look at an existing readmodel under `<serverPath>/src/modules/` in your repo for a working
reference. Useful variants to study if your repo has them: a standard per-aggregate
projection; an event-ID-keyed multi-stream audit timeline; a bulk-completion projector (with
a `projectBulkCompletion` helper).

## Final Checklist

- [ ] File named `<entity>.readmodel.ts`
- [ ] Destructures `{ database, realtimeSession, databaseSessionMode }` from Ports
- [ ] **Factory takes a single `Ports`-shaped parameter — never a second constructor argument.** The MDU/lift loader instantiates every artifact as `factory( ports )`; an injected arg is `undefined` in any lifted deployment unit. Single-consumer infra → a lazy library singleton reached via `getX( ports )`, never the global `Ports` type. See the `ddd-patterns` skill → "Artifact Constructor Signature — the MDU/Lift Contract".
- [ ] Collection named `{domain}_{entity}_readmodel`
- [ ] Database index ensured on primary key AND all queried fields
- [ ] Uses `ReadmodelBuilder( Schema, Events )`
- [ ] All projectors use `upsert` (not `insert`)
- [ ] `extractIdFromEventStream()` for document IDs
- [ ] Creation event projector includes `ownerId: event.metadata?.userId`
- [ ] Default by-ID query with `realtimeSession.readmodelSubscription`
- [ ] If any query declares `subscriptions: [...]`, `databaseSessionMode` is passed as the 3rd `.withDatabase` arg
- [ ] `.withSubdomain()` matches the data's true domain AND the file's module location (not chosen for auth convenience)
- [ ] No `getCollection()` opening another subdomain's `_readmodel` table (cross-subdomain reads use `backend.queries.X`)
- [ ] Every `:param` token in `route` has a matching field in `schemas.params`
- [ ] All queries include `FilterByAccountIdTransformer()` AND `FilterByScopeTransformer()`
- [ ] `FilterByScopeTransformer()` placed AFTER `FilterByAccountIdTransformer()` in transformers array
- [ ] Authentication check in query handlers
- [ ] No separate service or controller files
- [ ] Readmodel schema defined in the domain package (`<domainEventsPackageName>`) `*-integration.types.ts` (not inline)
- [ ] Registered via `routeEventHandler()` in `index.ts`