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

## Which reference to open

The per-artifact material lives in sibling files. Each row is a **condition, not a topic** — evaluate it against what you are about to write, and open the file *before* writing, not to check afterwards. Rows compose: a policy that calls an external API opens two.

| When you are… | Open | What skipping it has cost |
|---|---|---|
| writing or reviewing an **aggregate** — command handlers, invariants, idempotency checks, transactional side-writes, event reducers, lifecycle/status guards, admin-only or non-tenant-scoped aggregates | [AGGREGATES.md](./AGGREGATES.md) | `.produces([])` crashing endpoint registration; a state-reading idempotency predicate throwing an opaque `TypeError` instead of `STATE_NOT_FOUND`; a `draft` jumping straight to `completed` and skipping the number assignment; a Redis `INCR` reissuing a used receipt number |
| defining or **changing a schema / event** in the domain package — above all **renaming or removing a persisted field**, or a field on the state that rehydrates from it | [SCHEMAS.md](./SCHEMAS.md) | a PR scoped as a "pure rename" rehydrating the aggregate to `accounts["undefined"]` — replay silently broken, and the replay path usually has no test to go red |
| writing **any consumer that can be handed the same event twice** — policy, read model, HTTP webhook, non-PV3 service — or reasoning about ordering, gap recovery, operator replay, or `isRedelivery` | [DELIVERY.md](./DELIVERY.md) | deduping on **global position** instead of a per-stream version watermark, which drops exactly the gap-recovered events and silently re-creates a dropped-event bug; a non-idempotent external effect double-fired by a lost ACK |
| writing or reviewing a **policy** — event handlers, multi-command fan-out, partial-progress restart, non-idempotent external calls, `linkedTo`/`standalone` dependency declaration, placement, gateway ACLs, a cron- or system-triggered dispatch | [POLICIES.md](./POLICIES.md) | a fan-out restarted from the top re-emitting every event, because `invariants.stateExists()` does not protect a soft-deleted aggregate; a wrap-up command firing for the full original amount after a mid-progress redelivery; a blind processed-events ledger that re-POSTs anyway; a second `PolicyBuilder` in one file silently never registering |
| writing or reviewing a **read model** — projectors, complete-state rewrites, cross-stream counters, brand-new-row bootstrap, indexes, query routes and subscriptions, **changing its key property**, reading a projection from server-side code | [READMODELS.md](./READMODELS.md) | a rebuild unable to remove a key without `{ replace: true }`, leaving eight nav sections collapsed forever; `{ op: 'eq', value: null }` matching zero rows on Postgres and then nulling the whole `data` column; `op: 'contains'` on a default B-tree index leaving six live admin search boxes dead in production |
| composing a **module** `index.ts`, or registering/reconciling anything from a **boot hook** (`onStarted`) | [MODULES.md](./MODULES.md) | a single-flight guard that returns instead of re-arming, silently dropping every declaration after the first under the start-first boot order — two production cron subscriptions stopped registering while 399 suites and a 288/288 lift gate stayed green |

Everything below this table is cross-cutting: it applies to **every** artifact kind, so it stays inline and is not repeated in the references.

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

Dev-only backend features (dev tooling, debug endpoints, anything that logs a credential) get a single registration-time guard at the **module composition root** — the module's `create( ports )` or registry registration. A dev-tools module that registers no route in prod produces no Fastify route and no OpenAPI entry — that's the precedent.

**The predicate is an allowlist of local environments, never `!== 'production'`.** A denylist fails *open* on every environment name it did not anticipate, and a PV3 deployment has more than two (`staging`, `prodlocal`, …): `NODE_ENV !== 'production'` once shipped live magic-link and password-reset tokens into a deployed log aggregator, where one was harvested. List the environments the gate **opens** on, so a reader can check the list against the deployment's real env names:

```ts
const LOCAL_NODE_ENVS = [ 'development', 'test', 'e2e' ];
export const devSurfaceEnabled = (): boolean => {
  const env = process.env.NODE_ENV;
  return env === undefined || env === '' || LOCAL_NODE_ENVS.includes( env );
};
```

Where a dev-only feature must reach production for **chosen accounts** (a test channel), the gate is **per-account and request-time** — a server-side flag read — not environment-wide at registration; that trades two gates for one, so the read path must be tenant-scoped to be sound.

**An optional feature's cron is gated at the composition root on the same flag that gates the feature**, never registered from inside the policy on config the root has not proven present. A registration that throws on absent config **latches the `cron-subscriptions` readiness probe at 503**, and no local gate can see it: nothing in a normal test run constructs a config with the flag off.

**Never** gate by conditionally adding commands to an aggregate's `.withCommands(...)` map (`let additionalCommands = {}; if ( !prod ) { ... }`). The command surface feeds build-time generated artifacts that are environment-invariant by design — `.deployment-units.json`, `.openapi.json`, the generated client library, the rules-engine `node-registry.json` — so an env-conditional command makes a dev-built manifest/OpenAPI/client advertise a command prod doesn't have. Reinforce at the deployment layer by leaving the unit out of production `lift:` patterns. (Anti-pattern: a dev-only authorize command conditionally added to a tenant aggregate.)

## Realtime Subscriptions: Signal Mode

Signal mode (`x-subscription-changes: signal`) delivers `{ type: 'signal' }` to the consumer's `onChange` — it does **not** re-execute the original query, and should stay that way. The consumer (data policy) implements refetch itself: on a signal, call `backend.queries.X({ ...currentFilter })` and dispatch the result, with a small (~200ms) debounce to coalesce bursts. Don't extend the client-library generator to auto-refetch — consumers differ in filter sources, debounce windows, and ordering needs.
