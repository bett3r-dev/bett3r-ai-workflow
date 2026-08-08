---
description: Scaffold a full-pipeline in-process integration test suite for a server module using createIntegrationHarness. Use when you want to exercise the real command → aggregate → eventstore → outbox → readmodel pipeline for a subdomain (choreography, policies, gateway callbacks), not mocked unit tests.
---

# Skill: Create Integration Test

Scaffold an **in-process integration test suite** that drives a server module's full PV3 pipeline — command → aggregate → eventstore → outbox → readmodel — through the typed client library, with no network and in-memory ports. Modeled on the host repo's dedicated integration-tests package: a separate package holding `*.integration.test.ts` files that build a harness via `createIntegrationHarness`, with in-memory ports, exercising the full pipeline through the typed client library.

## Project configuration

This skill resolves the following placeholders from your repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<serverPath>` | `serverPath` | `src/services/server` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## When to use this vs. `create-tests`

| | `create-tests` (co-located unit) | **this skill** (integration suite) |
|---|---|---|
| Location | `<serverPath>/src/modules/<m>/*.test.ts` (next to source) | the host repo's integration-tests package, `<domain>/*.integration.test.ts` (dedicated package) |
| Ports | All mocked (`createTestPorts()`) | Real in-memory pipeline (eventstore, outbox, readmodels) |
| Tests | One component in isolation | Cross-component flows: choreography, policies firing via the outbox, gateway callback chains |
| Async | Synchronous | Outbox-driven — assert with `h.waitFor(...)` |
| Run by | Default `yarn test` | **Excluded** from default run; dedicated script (see Running) |

Reach for this skill when the behavior under test only emerges once events flow through the outbox — e.g. a policy reacting to an event, account-registration choreography, or an async gateway refund callback. For a single aggregate/policy/readmodel's logic in isolation, use the `create-tests` skill.

## What the harness gives you

`createIntegrationHarness({ modules, loggerName, testUser })` (the harness factory in the integration-tests package, e.g. `<testsPackage>/src/e2e/createIntegrationHarness.ts`) returns:

```typescript
type IntegrationHarness = {
  backend: ClientLibraryType;   // typed client → backend.commands.X / backend.queries.Y
  ports: any;                   // raw PV3 ports (rarely needed directly)
  waitFor: <T>( check: () => Promise<T>, predicate: ( r: T ) => boolean,
                opts?: { timeout?: number; interval?: number } ) => Promise<T>;
  cleanup: () => Promise<void>;
};
```

Key behaviors to rely on:

- **Only the modules you pass are loaded** — no identity, no sibling subdomains unless listed. Pass several `create` fns to `modules: []` for cross-module flows.
- **Auth = Mode C `DEV_ADMIN_USER` bypass.** Every request resolves to `testUser` (defaults to `DEFAULT_TEST_USER`, an admin with `permissions: ['*']`). Override per-call with `x-auth-user-id` / `x-auth-account-id` headers when a flow needs a different identity.
- **Tolerant outbox** (`E2ELocalOutbox`): policies referencing modules you didn't load fail as warnings, not test failures.
- **Mocked external ports**: `mailer.sendMail` is a `jest.fn()`; `paymentGateway` auto-approves charges and refunds (mocked gateway); `vectorDatabase` / `platformAnalytics` are no-ops. The DB is `MemoryDb` — each harness instance is a fresh, isolated eventstore.
- **`createIntegrationHarness` never calls `eventstore.start()`** — only `database.start()` / `databaseSessionMode.start()` / `outbox.start()` / `realtimeSession.start()`. A policy's `ports.eventstore.onStarted(async () => { ... })` hook (the idiom cron-registering policies use to register a subscription at boot) therefore **never fires** under this harness, even though the harness boots the owning module's `create(ports)` normally. Don't chase "why isn't my subscription registering" in a harness-based test — it's a harness gap, not a bug in the policy. Verify boot-time `onStarted` registration by running the real server against local dev infra and reading the eventstore/readmodel directly, not via this harness.

## Harness fidelity — where it silently diverges from production

This skill's whole value proposition is *fidelity*: "the real command → aggregate → eventstore → outbox → readmodel pipeline," not mocks. But **the harness is not production**, and on at least one correctness-relevant adapter it diverges *silently* — so a suite written with it can produce both false negatives **and false positives** about transactional, ordering, and delivery semantics, and the person writing the test has no reason to suspect it.

**The known divergence — the eventstore:**

- **Production** wires `PostgresEventstore` — multi-stream reads run on the *transaction* connection, so a command reads its own and a prior command's writes within one transaction (read-your-writes).
- **The harness** wires `DatabaseEventstore` — it *accepts* the `_transaction` and **discards it**. And it does so **unconditionally, even in the harness's "Postgres mode,"** which swaps only the *database*, never the *eventstore*.

Consequence (a real incident): an integration test observed a genuine stale read — a spurious event carrying `previousStock: 0` where a prior command *in the same transaction* had written `8` — that **does not exist in production**. A production-code filter was written and shipped to satisfy the test. The test "proved" a bug in code production never runs, and it arrived with a testcontainer reproduction that *defeated* scrutiny ("observed, not inferred" — but observed in the wrong environment).

**Rule.** An assertion about **in-transaction / ordering / delivery** semantics — read-your-writes across commands, transactional side-writes, rollback — is valid **only if the adapter under test is production's.** Before writing one, **diff the harness's port wiring against the composition root** (`setupPorts.ts` / `setup*Ports.ts`) and state plainly which adapters match. If the eventstore (or whatever adapter the assertion depends on) differs, this harness *cannot* decide the question — verify it against the real server on local dev infra instead.

**The MemoryDb trap.** `MemoryDb`'s noop pool makes pooled and transactional reads **indistinguishable** — so a MemoryDb-backed test cannot reproduce an in-transaction defect *in either direction*. Never use it for a test whose subject *is* transactional behavior.

> Best of all, make this drift **checkable**: a host-repo check that fails when the harness's wiring diverges from the composition root *undeclared* turns a silent trap into a build error — a defect whose signature is *absence* needs a gate, not a reader who remembers to look. Recommend it where the harness lives.

**A boot hook fires under the other order here.** The harness calls `eventstore.start()` **before** modules load, so `onStarted` callbacks run *immediately and interleaved* with the declarations after them — the reverse of the real server. That makes this harness the **only** in-process gate covering that order (MemoryDb never calls `start()` at all, so hooks never fire there). See `ddd-patterns` → *`onStarted` is not a queue* for the guard it breaks and the drop it produces.

## Driving a cron poll policy: use a real tick, not `fn( ports )`

A `.standalone()` cron poll policy costs several harness runs to two traps, both of which read as "the test is broken" rather than "the test is wrong":

1. **A bare main-thread `pollFn( ports )` call dispatches its command and the command never reaches the pipeline** — it returns a count, then a multi-minute gap, and nothing is processed. Drive it through a **real cron tick** instead: add the generic cronjobs module, seed an overdue subscription row, and `executeCommand( TickCronjob )` → `CronjobTriggered` → policy → the poll fn, so the work runs *inside* the pipeline execution context. The rule is about commands that must **flow through the pipeline**; a primitive that dispatches synchronously in-context can be driven directly.
2. **Assert the observable the projector actually writes.** Where a projector writes only the compare *result* (a sync-status field, a `lastSyncedAt`), the raw external mirror lives on **aggregate state**, not the readmodel row — so `readmodelRow…providerData.stock === N` never matches, no matter how long you wait. Observe the poll via the status flip and the timestamp advance.

Both burn expensive Postgres-harness cycles, and neither is discoverable from the poll's production code.

## Parallelism & isolation

These suites parallelize safely **across files** — that's why the parallel integration script runs `--maxWorkers=4`.

- **No TCP ports are bound.** The harness runs "in-memory ports and `endpoints.fetch` (no network)" — there's no HTTP server and websockets are not started. The client library calls `ports.endpoints.fetch` as an in-process function, so there is no listening socket to collide on.
- **PV3 ports are per-instance.** `database` (`MemoryDb`), `cache` (`MemoryCache`), `messageBroker` (`MemoryPubSub`), and the eventstore are all constructed fresh inside each `createIntegrationHarness()` call — two harnesses share zero state.
- **Jest workers are separate processes.** Each test file gets its own OS process (so isolated `process.env`), its own module registry, and its own in-memory DB/cache/pubsub. Files cannot bleed into each other.
- **Within a file there's no concurrency anyway.** Jest runs `describe` blocks sequentially; each builds its harness in `beforeAll` and tears it down in `afterAll`, so harness lifecycles never overlap.

**The one footgun — `DEV_ADMIN_USER` is a process global.** `createIntegrationHarness` sets `process.env.DEV_ADMIN_USER = JSON.stringify( testUser )` and every request in that process reads it. This is safe across workers (separate processes) and within a file (sequential blocks, same user). It collides **only** if you create two harnesses concurrently in one process with different `testUser`s — e.g. `Promise.all([ setupA(), setupB() ])` where A and B have different users; the second `setup` overwrites the env var the first relies on. Rule: **one harness at a time per process.** If you need to act as a different identity, use a per-call `x-auth-*` header override (see Core patterns), not a second harness.

> This assumes no loaded module keeps mutable module-level state outside the ports. Jest's per-file module registry isolates that across files; if you ever see cross-test bleed, that's the place to look.

## Step 1 — Setup file

Create `<domain>/setup<Domain>IntegrationTest.ts` in the integration-tests package. This is a thin wrapper; the relative import paths are identical for every domain (all domain dirs sit at the same depth under the package's `src/`):

```typescript
import { create as <domain>Module } from '../../../services/server/src/modules/<domain>';
import {
  createIntegrationHarness,
  DEFAULT_TEST_USER,
  IntegrationHarness,
  TestUser
} from '../e2e/createIntegrationHarness';

export type { IntegrationHarness as <Domain>IntegrationHarness };

export const <DOMAIN>_TEST_USER: TestUser = {
  ...DEFAULT_TEST_USER,
  id: '<domain>-test-user',
  accountId: '<domain>-test-account'
};

export const setup<Domain>Integration = () =>
  createIntegrationHarness({ modules: [<domain>Module], loggerName: '<domain>', testUser: <DOMAIN>_TEST_USER });
```

- Every server module exports `create` from its `index.ts` — import it `as <domain>Module`.
- For **cross-module** suites, import each module and list them: `modules: [moduleA, moduleB]`.
- Keep a single shared `setup` per domain; per-scenario overrides go through fixtures and per-call headers, not new harness factories.

## Step 2 — Test file

Create `<domain>/<domain>.integration.test.ts` in the integration-tests package. Open with a header comment carrying the exact run command (see Running), then build fixtures and scenario blocks.

```typescript
/**
 * <Domain> integration tests — full command → aggregate → eventstore → outbox → readmodel
 * pipeline via endpoints.fetch and the typed client library. Only the <domain> module is loaded.
 *
 * Run with:
 *   node "$(yarn bin jest)" --testMatch='**\/*.integration.test.ts' \
 *     --testPathIgnorePatterns='<rootDir>/dockerEnv' \
 *     --testTimeout=30000 --no-coverage --runInBand --testPathPattern="<domain>"
 */
import {
  <Domain>IntegrationHarness,
  <DOMAIN>_TEST_USER,
  setup<Domain>Integration
} from './setup<Domain>IntegrationTest';

// ─── Shared fixtures ────────────────────────────────────────────────────────
// Builder functions with an `overrides` param keep scenarios terse and intention-revealing.

const entityBody = ( id: string, overrides: Record<string, any> = {} ) => ({
  entityId: id,
  name: `Entity ${id}`,
  ...overrides
});

// ─── Scenario ───────────────────────────────────────────────────────────────

describe( '<Domain> — <scenario name>', () => {
  let h: <Domain>IntegrationHarness;

  beforeAll( async () => {
    h = await setup<Domain>Integration();
    // ...arrange: send the commands that set up preconditions, awaiting each.
  });

  afterAll( async () => {
    await h.cleanup();
  });

  it( 'when <command> then <readmodel reflects the outcome>', async () => {
    // WHEN — dispatch a command through the typed client
    await h.backend.commands.CreateEntity({ id: 'entity-1', body: entityBody( 'entity-1' ) });

    // THEN — poll the readmodel until the outbox-driven projection catches up
    const entity = await h.waitFor(
      () => h.backend.queries.<Domain>EntityById( 'entity-1' ),
      ( result: any ) => result?.status === 'active'
    );

    expect( entity ).toMatchObject({ id: 'entity-1', status: 'active' });
  });
});
```

## Core patterns

**Commands** — always `{ id, body }`, always awaited:
```typescript
await h.backend.commands.CreateEntity({ id: entId, body: entityBody( entId, accountId ) });
```

**Queries** — list or by-id; readmodels lag the command, so wrap reads of async results in `waitFor`:
```typescript
const entities = await h.backend.queries.Entities();          // list
const detail   = await h.backend.queries.EntityById( id );    // by id
```

**`waitFor` over fixed sleeps** — anything driven by the outbox (a policy firing, choreography creating a sibling aggregate, a gateway callback chain) is eventually-consistent. Poll until the predicate holds:
```typescript
await h.waitFor(
  () => h.backend.queries.Entities(),
  ( r ) => r?.some(( a: any ) => a.id === entityId )            // default timeout 3000ms, interval 25ms
);
```
Never `await new Promise( r => setTimeout( r, n ))` to wait for a projection — it's flaky and slow. Reserve fixed timeouts only for asserting that something does *not* happen.

**Per-call identity override** — the harness defaults every request to `testUser`. To act as a different account/user in one call, pass auth headers (the client library forwards a third headers arg):
```typescript
await h.backend.commands.CreateEntity({ id, body }, { 'x-auth-account-id': 'other-account' });
```

**One harness per `describe`** — each scenario gets a fresh isolated eventstore via `beforeAll`, torn down in `afterAll`. Don't share a harness across scenarios that mutate overlapping ids.

**Arrange in `beforeAll`, assert in `it`** — push the precondition commands (and their `waitFor`s) into `beforeAll` so each `it` reads as a single When/Then.

## Modules with engine/singleton-backed infrastructure

Some modules consume infrastructure that is **not a port** — an engine, a specialized client — owned as a **lazy process-singleton** inside the owning library (per the MDU/lift contract: artifacts take only `( ports )`, so single-consumer infra can't be injected and isn't on the global `Ports`). Such an engine is reached via `getX( ports )`, built on first use from the slice it needs (e.g. `{ configuration, logger, cache, endpoints, database, eventstore }`) — exactly the slice the harness already provides. **No harness change is needed**; the engine builds itself bound to the harness's in-memory eventstore + in-process `endpoints.fetch`.

What such a suite must do:

- **Reset the singleton around each harness.** The singleton is a process global; a stale instance keeps querying a closed DB. Call `resetX()` in `beforeAll` (before the first command that builds it) and `afterAll`. The library exposes the seam: `getX( ports )` (build-and-cache), `setX( instance )` (inject a mock/deterministic engine before the first access), `resetX()` (clear between harnesses).
  - **`createIntegrationHarness` resets these process-singletons for you** before loading modules — so a suite that loads a module backed by such a singleton needs no manual reset. You only inject a specific instance (`setX( createX([...]) )`) in a **unit** test (`createTestPorts`, not the harness); pair it with `resetX()` in `afterEach` so it doesn't leak across files in a shared jest worker.
- **Choose real vs. mock at the seam.** Do nothing → the runner builds the REAL thing on first use (live external calls). Or `setX( mock )` before the first message for a deterministic run (the E2E path does this in its test-server bootstrap).

```typescript
import { resetX /*, setX */ } from '<engineLibraryPackageName>';
beforeAll( async () => { resetX(); h = await setup<Domain>Integration(); });
afterAll( async () => { await h.cleanup(); resetX(); });
```

## Capturing non-persisted side-effects (StreamUpdates, realtime pushes)

Some outcomes are emitted via `ports.realtimeSession.send( userId, { type, ref, data } )` and **never persisted** — e.g. a streaming runner pushes tool calls, plans, `interrupt`, `done`, `error` there. Polling a readmodel won't see them. Replace `send` with a recorder (the runner reads the property at call time, so mutating it after harness construction takes effect), then slice by `ref`:

```typescript
const captured: Array<{ ref: string; data: { type: string; [k: string]: unknown }}> = [];
( h.ports.realtimeSession as { send: unknown }).send =
  ( _userId: string, p: { ref: string; data: { type: string }}) => { captured.push({ ref: p.ref, data: p.data }); };
// then: captured.filter( u => u.ref === conversationId ).map( u => u.data )
```
`waitFor` until a terminal update (`done`/`interrupt`/`error`) appears for that conversation, then assert on tool/plan/interrupt. Cross-check the durable record (the aggregate's event stream) where one exists.

## Live external dependencies (LLMs, third-party APIs)

When the suite drives a **real external dependency** (a live LLM "as configured", a real gateway), keep it **opt-in** so the parallel integration sweep doesn't fire slow/costly/non-deterministic calls:

- Gate the live block: `const live = process.env.AI_LIVE === '1' ? describe : describe.skip;`. Keep a separate always-on `describe` for the deterministic parts (e.g. fast-paths that bypass the LLM).
- **Tolerant assertions** — assert tool/route *choice*, not prose: e.g. "navigates to `/accountSettings/users`" accepting either `navigate(...)` or `open_create_form({user})`. Generous `testTimeout` (120s+), `--runInBand`.
- **Provider keys** come from config/env the same way the dev server resolves them; document the run command in the header comment and the required key in the suite.

## Running

`*.integration.test.ts` is **deliberately excluded** from the default jest run — `jest.config.js` lists `\.integration\.test\.ts$` in `testPathIgnorePatterns`. Running `yarn test` will silently skip these files. Run them via:

```bash
# Whole integration suite (all domains)
yarn test:integration:channels

# Single domain, serial, with the header-comment command
node "$(yarn bin jest)" --testMatch='**/*.integration.test.ts' \
  --testPathIgnorePatterns='<rootDir>/dockerEnv' \
  --testTimeout=30000 --no-coverage --runInBand --testPathPattern="<domain>"
```

Prefer `--runInBand` while developing (clearer logs, no cross-worker DB surprises); the parallel integration script uses `--maxWorkers=4` for CI throughput. These suites need the `pv3` workspace packages built first (see project memory).

## Critical constraints

- **File suffix is `.integration.test.ts`, location is the integration-tests package's `<domain>/` dir** — NOT co-located in the module dir. The suffix is what routes it to the dedicated runner and out of the default suite.
- **Always `await h.cleanup()` in `afterAll`** — it stops the outbox, message broker, realtime session, cache, and both DBs. Skipping it leaks handles and hangs the runner.
- **Use `h.waitFor` for every outbox-driven assertion** — no fixed sleeps for projections/policies/callbacks.
- **Load only the modules the flow needs.** Adding unrelated modules pulls in their policies and slows setup; missing a needed sibling means its choreography silently no-ops (tolerant outbox).
- **No `any` leaking into assertions you control** — the client library is typed; the `( r: any )` in `waitFor` predicates is the established idiom for readmodel rows, acceptable there.
- **Don't reach into `h.ports`** unless asserting infrastructure (e.g. that `mailer.sendMail` was called); prefer driving everything through `h.backend`.

## Final checklist

- [ ] `setup<Domain>IntegrationTest.ts` created — imports module `create`, defines `<DOMAIN>_TEST_USER`, exports `setup<Domain>Integration`
- [ ] `<domain>.integration.test.ts` created in the integration-tests package's `<domain>/` dir with run command in the header comment
- [ ] Shared fixture builders with `overrides` params
- [ ] One harness per `describe`, set up in `beforeAll`, `await h.cleanup()` in `afterAll`
- [ ] Commands sent as `{ id, body }`; outbox-driven outcomes asserted via `h.waitFor`
- [ ] Happy path + at least one cross-component flow (policy/choreography/callback) covered
- [ ] **No in-transaction / ordering / delivery assertion unless the adapter under test matches production** — harness wiring diffed against the composition root; note in particular that the eventstore is `DatabaseEventstore` here vs. `PostgresEventstore` in production (see *Harness fidelity*)
- [ ] Passes: `node "$(yarn bin jest)" --testMatch='**/*.integration.test.ts' --testTimeout=30000 --no-coverage --runInBand --testPathPattern="<domain>"`
