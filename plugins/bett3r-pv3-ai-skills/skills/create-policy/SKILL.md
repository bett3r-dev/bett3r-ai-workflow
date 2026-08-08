---
description: Scaffold an event-driven policy that reacts to events and triggers commands. Use when adding event reactions or sagas.
---

# Skill: Create Policy

Scaffold a PV3 policy that reacts to domain events and triggers side effects or commands.

**Read [`ddd-patterns` → POLICIES.md](../ddd-patterns/POLICIES.md) before writing the file** — partial-progress redelivery, multi-command fan-out replay-safety, reconcile-by-natural-key, dependency declaration, policy placement, and the gateway ACL two-step. **If the handler dispatches more than one command, accumulates, or calls anything external, read [DELIVERY.md](../ddd-patterns/DELIVERY.md) too**: a policy is a consumer, the outbox is at-least-once, and the dedup rules (per-stream version watermark, never global position; `isRedelivery` is a replay hint, not a dedup gate) are stated there.

## Project configuration

Resolve these placeholders from your repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>` | `domainEventsPackageName` | `@bett3r-dev/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |
| `<clientLibraryPackageName>` | `clientLibraryPackageName` | `@bett3r-dev/teselly-client-library` |
| `<domainUtilsPackageName>` | `domainUtilsPackageName` *(optional; defaults to `<domainEventsPackageName>` + `-utils`)* | `@bett3r-dev/teselly-domain-utils` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Pattern

```typescript
import { extractIdFromEventStream } from '@bett3r-dev/pv3';
import { MyEvents } from '<domainEventsPackageName>';
import { Ports } from 'ports';

export const MyPolicy = ( ports: Ports ) => {
  const { SomethingHappened, SomethingElseOccurred } = MyEvents;
  const logger = ports.log;

  return ports.eventsourcing.PolicyBuilder({ SomethingHappened, SomethingElseOccurred })
    .withEventHandlers(() => ({
      SomethingHappened: async ( event ) => {
        const entityId = extractIdFromEventStream( event );
        const accountId = event.metadata?.accountId;
        const correlationId = event.metadata?.correlationId;
        const causationId = event.id;

        logger.info( `Processing SomethingHappened for entity ${entityId}` );

        // Execute side effect or trigger command
        await someAction( ports, {
          entityId,
          accountId,
          correlationId,
          causationId,
          data: event.data
        });
      },

      SomethingElseOccurred: async ( event ) => {
        // Handle another event
      }
    }));
};
```

## File Location

```
<serverPath>/src/modules/<module-name>/<entity-or-purpose>.policy.ts
```

## Policy Placement

A policy belongs in the **subdomain whose state it changes**, not in the subdomain that emits the trigger event.

**Rule:** If the policy's `createCommand`/`executeCommand` targets aggregate X, the policy file lives in X's module directory. Confirmed misplacement pattern: agent places the policy near existing policies that subscribe to the *same event*, even when the aggregate it mutates lives in a different module.

**Check before creating a policy file:** Does `createCommand` / `executeCommand` target an aggregate in the same module? If not, move the file to the aggregate's module. Import the trigger event's *schema* from the domain package (`<domainEventsPackageName>`) — always allowed across modules.

*Example:* A policy reacting to `Accounts/UserAccountAdded` to provision a `SalesChannelIntegration` → `src/modules/sales-channels-integrations/`, not `src/modules/identity/`.

## Registering a Cronjob Subscription

Use `backend.commands.RegisterCronjobSubscription(...)` — never `ports.eventsourcing.executeCommand` against `CronjobSubscriptionsAggregate` directly:

```typescript
await backend.commands.RegisterCronjobSubscription({
  id: MY_SUBSCRIPTION_NAME,
  body: {
    name: MY_SUBSCRIPTION_NAME,
    expression: '*/15 * * * *',
    description: 'Description of what this cron does'
  }
});
```

The client-library seam is the intended registration path; direct aggregate access bypasses it.

## Gateway ACL Systems

**`produces` must only list events the handler itself emits.** Never include downstream aggregate events in `produces`.

**Canonical two-step pattern:**

1. Gateway system emits a **raw event** (`GatewayXCallbackReceived`) with the external payload verbatim.
2. A **separate policy** reacts and dispatches the aggregate command that emits domain events.

A handler that calls `executeCommand` and returns `[]` should have an empty or omitted `produces` — the downstream aggregate's events are NOT this handler's output and belong to a different stream.

## Dependency Declaration (Required)

Every policy MUST declare its aggregate dependency. Build error during manifest generation if missing.

```typescript
// Option 1: Auto-detected — pass aggregate as 2nd PolicyBuilder param (createCommand pattern)
return ports.eventsourcing.PolicyBuilder({ SomethingHappened }, TargetAggregate( ports ))
  .withEventHandlers(({ createCommand }) => ({
    SomethingHappened: async ( event ) => {
      return createCommand( 'DoSomething', id, data );
    }
  }));

// Option 2: Manual — executeCommand policies targeting aggregates imperatively
return ports.eventsourcing.PolicyBuilder({ SomethingHappened })
  .linkedTo( 'AggregateA', 'AggregateB' )
  .withEventHandlers(() => ({
    SomethingHappened: async ( event ) => {
      await ports.eventsourcing.executeCommand( AggregateA( ports ), 'DoSomething' )({ ... });
    }
  }));

// Option 3: Standalone — side-effect-only policies (email, webhooks, external APIs, rules)
return ports.eventsourcing.PolicyBuilder({ SomethingHappened })
  .standalone()
  .withEventHandlers(() => ({
    SomethingHappened: async ( event ) => {
      await sendEmail( ... );  // No aggregate commands
    }
  }));
```

## Registration

In the module's `index.ts`:

```typescript
ports.eventsourcing.routeEventHandler( MyPolicy( ports ));
```

## Process Manager Pattern

For complex multi-step processes, use the process manager pattern with idempotency, progress tracking, and correct completion ordering:

```typescript
import { extractIdFromEventStream } from '@bett3r-dev/pv3';
import { InternalServerError } from '@bett3r-dev/pv3-types';
import { processManagerIdempotencyWatermark, createBatchProgressTracker, createRefillingQueue, AbortError } from '<domainUtilsPackageName>';
import { createBatchProcessReadmodelService } from '../<batch-processes-module>/batchProcessReadmodel.service';
import { Ports } from 'ports';

export const MyProcessManager = ( ports: Ports ) => {
  const { BatchProcessStarted } = MyEvents;
  const logger = ports.log;

  return ports.eventsourcing.PolicyBuilder({ BatchProcessStarted })
    .withEventHandlers(() => ({
      BatchProcessStarted: async ( event ) => {
        const batchProcessId = extractIdFromEventStream( event );
        const { process, complete } = processManagerIdempotencyWatermark(
          ports, 'MyProcess', batchProcessId
        );
        const readmodelService = createBatchProcessReadmodelService( ports );
        const tracker = createBatchProgressTracker( ports, batchProcessId, readmodelService );

        const refillingQueue = createRefillingQueue({
          concurrency: 20,
          minBuffer: 10,
          batchSize: 20,
          fetchNextBatch: async ( take ) => { /* fetch items from source */ },
          processItem: async ( item ) => {
            await process( item.id, async () => {
              await doSomething( ports, item );
              await tracker.advance( item.id );
            }).catch( async e => {
              if ( e instanceof AbortError ) return Promise.reject( e );
              await tracker.error( item.id, { message: e.message, name: e.name });
              return Promise.reject( e );
            });
          },
          onError: ( e, item ) => {
            if ( e instanceof AbortError ) return;
            logger.error( `Error processing item ${item.id}`, e );
          }
        });

        await refillingQueue.run();

        // CRITICAL ORDERING: check errors → throw → complete → cleanup
        // If errors exist, throw WITHOUT cleanup. This preserves watermarks
        // (so outbox retry only reprocesses errored items) and tracker state
        // (so progress counts survive across retries).
        const progress = await tracker.getProgress();

        if ( progress.errorCount > 0 ) {
          throw new InternalServerError(
            'Batch process failed', 'BATCH_PROCESS_FAILED', { failed: progress.errorCount }
          );
        }

        await completeBatchProcess({
          params: { id: batchProcessId },
          body: {
            successCount: progress.successCount,
            errorCount: progress.errorCount,
            erroredItemIds: progress.erroredItemIds
          }
        });

        await complete();        // Clear idempotency watermarks
        await tracker.cleanup(); // Clear Redis progress keys
      }
    }));
};
```

### Batch Completion Contract

The ordering of the completion section is **critical** for correct outbox retry behavior:

1. **Check errors first** — if any items failed, throw to trigger outbox retry. Do NOT call `complete()` or `tracker.cleanup()` so that state is preserved for the retry.
2. **Complete the batch** — only reached when all items succeeded. Emits the completion event.
3. **`complete()`** — clears idempotency watermarks (allows future re-runs if needed).
4. **`tracker.cleanup()`** — removes Redis progress keys.

On outbox retry after a throw:
- Watermarked items (successes) are skipped by `process()` — no double processing
- Non-watermarked items (errors) are retried
- Tracker preserves progress counts across retries (`hashSetIfNotExists` prevents reset)

## Execution Context (Automatic)

PV3 PolicyBuilder automatically wraps each event handler with `runWithExecutionContext`, extracting `accountId`, `userId`, and `correlationId` from `event.metadata` and setting `causationId` to `event.id`. This means:

- **No manual `context.user` assembly** — `executeCommand` reads it from AsyncLocalStorage automatically
- **No manual `query.causationId`** — defaults to `event.id` (the correct DDD pattern)
- **No manual `query.correlationId`** — read from ALS automatically
- **No manual auth headers on `createClientLibrary`** — the client library reads headers from ALS via the injected context provider

```typescript
// BEFORE (manual threading — no longer needed)
await ports.eventsourcing.executeCommand( Aggregate( ports ), 'Command' )({
  params: { id },
  query: { causationId: event.id, correlationId: event.metadata!.correlationId },
  body: { ... },
  context: { user: { id: event.metadata!.userId!, accountId: event.metadata!.accountId! } }
});

// AFTER (context auto-populated from ALS)
await ports.eventsourcing.executeCommand( Aggregate( ports ), 'Command' )({
  params: { id },
  body: { ... }
});
```

Explicit parameters still override ALS values when provided (backwards-compatible).

## Cross-Service Commands

When a policy needs to trigger commands in another service, use the client library:

```typescript
import { create as createClientLibrary } from '<clientLibraryPackageName>';

export const CrossServicePolicy = ( ports: Ports ) => {
  const { SomethingHappened } = MyEvents;

  return ports.eventsourcing.PolicyBuilder({ SomethingHappened })
    .withEventHandlers(() => ({
      SomethingHappened: async ( event ) => {
        const clientLibrary = createClientLibrary( { baseUrl: '' }, ports.endpoints.fetch );

        await clientLibrary.commands.DoSomethingElse({
          entityId: extractIdFromEventStream( event ),
          data: event.data
        });
      }
    }));
};
```

## Critical Constraints

- **Never cast `backend.commands.*` bodies as `any`** — generated client library types are the canonical contract. If a body does not type-check, align the field names/types to match the schema — do not use `as any`.
- **No NestJS module** — No `@Module`, no `PolicyModule.forFeature()`
- **No `depsFactory`** — Use ports closure instead
- **No `context` parameter in handlers** — Handlers receive only `( event )`
- **Extract IDs from stream** — Use `extractIdFromEventStream( event )`, not event data
- **Always pass correlation metadata** — `correlationId` and `causationId` for tracing
- **Idempotency** — Use `processManagerIdempotencyWatermark` for batch/multi-step processes
- **Error handling** — Log errors with context, re-throw to trigger retry mechanisms
- **Retry-eligible error type for transient/projection-lag failures** — When a policy reads a projection that may not have caught up yet (e.g. the upstream event's projection is still in flight), throw a **plain `Error`**, NOT `BadRequestError`. `BadRequestError` is a 4xx classification; the outbox can treat 4xx as poison / dead-letter rather than retry, dropping the event. Reserve `BadRequestError` for *caller-fault* paths (validated input the caller can fix); use plain `Error` for *transient-environment* paths (projection lag, dependency unavailable). Be consistent across sibling policies — a review caught a `BadRequestError` on a "referenced aggregate not projected yet" path in one policy while a sibling correctly used plain `Error` for the same lag condition.
- **Target commands must be replay-safe** — When a policy `executeCommand`s a target aggregate, that command MUST tolerate re-delivery (the outbox can re-fire any event). For "create-once" commands, prefer `withIdempotencyCheck( idempotency.check( ({ state }) => state, 'exists' ))` over `invariants.stateNotExists()` — the invariant throws on replay, the outbox marks the subscription errored, and retries the stream forever. Idempotency makes re-delivery a silent no-op (no events emitted, no transactional side-writes). Pattern: a `RegisterX` create-command guarded by `withIdempotencyCheck` rather than `stateNotExists()`.
- **Multi-command fan-out is redelivery-restartable** — A handler that dispatches **more than one command** (a fan-out loop, or sequential distinct commands) can throw between dispatches, after which the outbox redelivers the trigger event and restarts the handler from the top. Therefore EVERY dispatched command must be idempotent on replay (`withIdempotencyCheck` or a no-op handler), OR the policy must track progress in a watermark. Default to per-command idempotency; reach for a watermark only when progress can't be derived from aggregate/readmodel state. Required regression test: "redelivery after partial progress emits zero duplicate events."
- **Soft-delete defeats `stateExists`** — `invariants.stateExists()` does NOT guard a soft-deleted aggregate: a `mergeLeft({ isDeleted: true })` reducer leaves state non-null, so `stateExists` never throws and a non-idempotent terminal/delete command **re-emits its event** on redelivery (re-firing downstream consumers) instead of erroring. A terminal command on a soft-delete aggregate needs its own idempotency guard keyed on `state?.isDeleted`.
- **Symmetric branch redelivery guards** — When a policy handler has multiple branches (e.g. an "open"/"activate" branch and a "close"/"resolve" branch) that each dispatch a command, ALL branches that can receive re-delivered events must swallow the matching "already done" error codes. A common defect: only the "start" branch guards `ALREADY_ACTIVE` but the "resolve" branch leaves `NOT_ACTIVE` / `STATE_NOT_FOUND` unswallowed. Outbox redelivery of a "resolve" event after the process is gone will throw and poison the stream. Fix: wrap every branch's `executeCommand` in a `try/catch` that swallows its own idempotency codes — a review caught exactly this asymmetry: the activate branch correctly swallowed its `..._ALREADY_ACTIVE` code, but the resolve branch was missing the symmetric `..._NOT_ACTIVE` / `STATE_NOT_FOUND` guard.
- **Non-idempotent external side-effects → reconcile by natural key, not a blind ledger** — For a policy whose side-effect is a non-idempotent **external** create-call with no idempotency key (list a product, issue an invoice), redelivery safety comes from **reconciling against the external by a natural key** (ask it "does this SKU / client-reference / reserved-number already exist?"), NOT from a local processed-events ledger/bitmap. A ledger marks *after* the side-effect, re-creating the act-then-mark gap; reconcile is authoritative and survives loss of the local store. A best-effort ledger is justified **only** when the side-effect is non-idempotent **and** non-reconcilable. Prefer pushing dedup into the external via an idempotency key derived from `event.id` when it supports one. See [`ddd-patterns` → POLICIES.md](../ddd-patterns/POLICIES.md) → "Non-idempotent external side-effects: reconcile by natural key".

## A new policy emits an internal operation — register its capability before `generate-all`

Registering a **new** `PolicyBuilder` policy makes `generate-all`'s authorization-surface generator fail hard, blocking the whole build:

```
operation `<subdomain>:<kebab-of-policy-name>` has no capability coverage
```

Even with no endpoint and no command authored, a policy silently emits an **internal operation route** — the kebab-case of the policy factory name minus `Policy`, exactly like every rules-execution policy. Add that operation key to the `<subdomain>:internal` capability in `packages/shared/capabilities/src/registry.ts`, next to its siblings, **before** running `generate-all`:

```
automation:suspension-resume-channel-reconciliation  →  automation:internal
```

It is not obvious that a policy with no HTTP surface produces an authorization operation, so every new policy author rediscovers it — two independent lanes hit it in the same week. Where the composition of several slices adds several such policies, the drift only *exists* once they are assembled, which is why `/verify-build` also runs the repo's codegen gate as a whole-PR sweep. One trap on the catch side: if that gate reports an entry missing which you can see present in `registry.ts`, **suspect the gate's inputs before editing the source** — it resolves through the repo's own `paths` mapping and will happily read a stale compiled `.js` sitting beside the `.ts`. "Fixing" it by duplicating the entry creates real drift.

Boot-time registration in a policy has a second, unrelated hazard — see [`ddd-patterns` → MODULES.md](../ddd-patterns/MODULES.md) → *`onStarted` is not a queue*.

## Pre-State-Change Watermark on the Trigger Event

When a command both **(a) mutates state** and **(b) emits an event that triggers a downstream policy needing the pre-mutation value of that state field**, the handler MUST compute the pre-mutation value and emit it onto the event. The policy cannot recover it by reading the aggregate state — the same event that fired the policy already advanced state in the reducer, so by the time the policy reads, the old value is gone.

**Symptom:** the downstream policy reads "the value at the time of the trigger" from the projection / aggregate state and silently gets the post-mutation value, producing cumulatively wrong output (e.g. a run that re-counts all work since the entity was created instead of since the last run, because it read the post-advance "processed-through" marker).

**Fix:** the command handler computes the watermark **before** building the event payload, and embeds it on the emitted event. The reducer then advances state to the new value. The policy reads the watermark from `event.data.<watermarkField>`.

```typescript
// Handler (aggregate)
RequestRun: commandBuilder()
  .withSchema( RequestRunCommandSchema )
  .produces([ 'RunRequested' ])
  .withHandler( async( createEvent, state, data ) => {
    const segment = findSegment( state, data.parentId, data.segmentId );
    // Capture the PRE-advance watermark — once the reducer runs, this is gone.
    const watermark = segment?.runSegments?.at( -1 )?.processedThroughDate
      ?? segmentStart( state, data.parentId );
    return [createEvent( 'RunRequested', {
      ...data,
      periodStart: watermark,   // <-- the policy reads this as the freeze-window lower bound
      targetDate: data.targetDate
    }, { metadata: { accountId: state.ownerAccountId }})];
  });

// Reducer (aggregate) advances the watermark
RunRequested: ( state, event ) => advanceProcessedThroughDate( state, event.targetDate );

// Policy (downstream consumer)
RunGenerationPolicy: async event => {
  const period = { startDate: event.data.periodStart, endDate: event.data.targetDate };
  const frozen = await freezeWork( period );           // correct unprocessed window
  // ...
};
```

**Where this surfaces:** any pattern where a command advances a "processed-through" / "billed-through" / "last-X-at" watermark **and** emits an event consumed by a policy that runs over the `[previousWatermark, newWatermark]` window — e.g. a `periodStart` field on the request event read by the downstream run-generation policy.

**Test trap:** a policy-test fixture whose pre- and post-mutation values are equal (e.g. `segment.start === segment.processedThroughDate` for a brand-new entity) cannot surface this bug. The regression test must advance the watermark — make `processedThroughDate > start` — so the window is non-degenerate.

## Partial-Progress Redelivery: Derive Progress from Aggregate State

A policy handler that dispatches **N commands in a loop and then one wrap-up command** is subject to outbox redelivery mid-progress — any throw between commands leaves the handler restartable. Per-command idempotency on the loop commands is necessary but not sufficient: the policy's *local* `remaining` / "what's left to do" counter must agree with the aggregate's recorded progress byte-for-byte, or the wrap-up command commits the wrong residual amount.

**The bug class:** re-walking live downstream state (e.g. a target's current balance) recomputes the loop's effective work, but already-settled targets report `outstanding = 0` on redelivery; the loop skips them *without decrementing `remaining`*, and the wrap-up command fires for the full original amount — the residual inflates by Σ already-applied. Aggregate identity-only idempotency no-ops the per-target commands, but the wrap-up — keyed on the *event id*, not the per-target identity — commits fresh.

**Fix shape:** seed `remaining` from the **source aggregate's recorded progress** (e.g. an `applications[]` / `appliedTo[]` array the source aggregate persists), skip plan entries whose identity already appears in that progress, and read live downstream state only for the per-iteration cap. See [`ddd-patterns` → POLICIES.md](../ddd-patterns/POLICIES.md) → "Partial-progress redelivery" for the full pattern and the regression-test contract.

## Event Metadata

Access event metadata for tracing and multi-tenancy:

```typescript
event.metadata?.accountId     // Tenant ID
event.metadata?.correlationId // Trace ID
event.metadata?.userId        // Acting user
event.id                      // Use as causationId for downstream commands
```

## Rules Execution Policy Pattern

Policies that fan domain events out to user-defined custom rules (via the `automation` module's `findRulesToExecute` + `StartRuleExecution` command) share a recurring shape. Several instances typically exist — a single-event policy that uses `ports.eventstore.read({ correlationId, events: [...] })` to expand per-row events from a bulk-operation-completed trigger, plus one or more multi-event handlers (see below).

### Shape

```typescript
import { extractIdFromEventStream } from '@bett3r-dev/pv3';
import { CommittedEvent } from '@bett3r-dev/pv3-types';
import { create as createBackend } from '<clientLibraryPackageName>';
import { MyDomainEvents } from '<domainEventsPackageName>';
import { buildIntegrationId, processManagerIdempotencyWatermark } from '<domainUtilsPackageName>';
import { Ports } from 'ports';
import { uuidv7 } from 'uuidv7';
import { findRulesToExecute, getRuleExecutionLimiter } from '../../automation';

export const MyRulesExecutionPolicy = ( ports: Ports ) => {
  // Shared handler — used when multiple events trigger the same rule-dispatch logic.
  const processEvent = async ( event: CommittedEvent ) => {
    const logger = ports.log;
    const accountId = event.metadata?.accountId;
    if ( !accountId ) {
      logger.warn( `No accountId for ${event.name} event ${event.id}` );
      return;
    }

    const clientLibrary = createBackend({ baseUrl: '' }, ports.endpoints.fetch, {
      'x-auth-account-id': accountId
    });

    const entityId = extractIdFromEventStream( event );
    // Narrow event.data as `{ ...required domain fields }` (NOT `as any`) based on the event schema's guarantees.

    const { rules } = await findRulesToExecute( clientLibrary, {
      entityHierarchy: { entity: [{ entity: entityId, integrationUserId: buildIntegrationId( connectorId, integrationUserId ), account: accountId }] },
      triggeringEvent: event.name   // dynamic — same handler handles multiple trigger events
    });

    const allRulePairs = Object.entries( rules ).flatMap(([ entityHierarchy, entityMap ]) =>
      Object.entries( entityMap ).flatMap(([ ruleEntityId, customRules ]) =>
        customRules.map( customRule => ({ customRule, entityId: ruleEntityId, entityHierarchy }))));
    if ( !allRulePairs.length ) return;

    const { process, complete } = processManagerIdempotencyWatermark( ports, 'MyRulesExecutionPolicy', event.id );
    const limiter = getRuleExecutionLimiter();

    for ( const { customRule, entityId: ruleEntityId, entityHierarchy } of allRulePairs ) {
      await process( `${customRule.customRuleId}-${ruleEntityId}`, async () => {
        const emitCommand = () => clientLibrary.commands.StartRuleExecution({
          id: uuidv7(),
          body: {
            customRuleId: customRule.customRuleId,
            ruleDefinitionId: customRule.ruleDefinitionId,
            triggeringEventName: event.name,
            triggeringEventId: event.id,
            entityHierarchy,
            entity: customRule.entity,
            entityId: ruleEntityId,
            accountId,
            declaredInputsValues: customRule.declaredInputsValues,
            triggeringEventData: event.data
          }
        });
        await ( limiter ? limiter.schedule( accountId, emitCommand ) : emitCommand());
      });
    }
    await complete();
  };

  const { EventA, EventB, EventC } = MyDomainEvents;
  return ports.eventsourcing.PolicyBuilder({ EventA, EventB, EventC })
    .standalone()                               // always standalone — this policy emits commands via client library
    .withEventHandlers(() => ({
      EventA: processEvent,
      EventB: processEvent,
      EventC: processEvent
    }));
};
```

### Conventions

- **Always `.standalone()`** — the policy emits commands via the client library, never through an in-process aggregate.
- **Idempotency key = policy class name** — `processManagerIdempotencyWatermark(ports, 'MyRulesExecutionPolicy', event.id)`. The key string MUST match the exported factory name exactly so replays correlate.
- **Per-account throttling** — always call `getRuleExecutionLimiter()` and `limiter.schedule(accountId, emitCommand)` when the limiter is defined. This prevents one noisy tenant from saturating rule execution for all tenants.
- **Shared handler for multi-event policies** — when several events should trigger identical rule-dispatch logic, extract a single `processEvent(event)` function. Each `withEventHandlers` entry simply references it. `triggeringEvent: event.name` differentiates matches downstream.
- **No unit test** — by project convention. Rules-execution policies are tested indirectly via the automation module's tests + integration tests.
- **Don't cast to `any` to bypass `EntityHierarchy`** — rule out the cast by either (1) always supplying the required hierarchy fields or (2) relaxing the field in `automation/rules-utils.ts` if it's genuinely optional for new triggering domains.

## Reference Files

Look at an existing policy under `<serverPath>/src/modules/` in your repo for a working reference. Patterns worth finding among existing policies: a multi-step creation/import process manager; a per-event extraction policy; and a rules-execution policy with a shared multi-event handler (`.standalone()`, `processEvent` reused across several trigger events).

## Final Checklist

- [ ] File named `<purpose>.policy.ts`
- [ ] **Policy is in the module of the aggregate it mutates** — not in the trigger-event source module
- [ ] **Factory signature is EXACTLY `( ports: Ports )` — never a second constructor argument.** The MDU/lift loader instantiates every artifact as `factory( ports )`; an injected arg is `undefined` in any lifted deployment unit (passes monolith + unit + E2E, breaks only in distributed prod). Single-consumer infra (an engine, a specialized client) → a lazy library singleton reached via `getX( ports )`, never the global `Ports` type. See the `ddd-patterns` skill → "Artifact Constructor Signature — the MDU/Lift Contract".
- [ ] Uses `ports.eventsourcing.PolicyBuilder({...})`
- [ ] Events destructured from domain events
- [ ] `extractIdFromEventStream()` used for stream IDs
- [ ] Logger created with descriptive context name
- [ ] Correlation/causation IDs passed through
- [ ] Error handling with logger.error
- [ ] No NestJS decorators or module patterns
- [ ] Registered via `routeEventHandler()` in `index.ts`
