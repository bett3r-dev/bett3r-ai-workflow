# PV3 policies — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

**Read [DELIVERY.md](./DELIVERY.md) first.** A policy is a consumer: the outbox can hand it the same event twice, and the redelivery rules below (partial progress, fan-out replay, reconcile-by-natural-key) are all *responses* to the delivery contract stated there — including why `isRedelivery` is the wrong gate.

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
- **One `PolicyBuilder` per `*.policy.ts` file.** PV3 derives the registration name from the **filename**, so a second builder in the same file is refused at boot and never registers — with `build`, `typecheck` and its own unit suite all green, because the tests call the handler directly. **`generate-all` is the only gate that proves a policy, route or capability is REGISTERED**: verify by the generated `route-config.json` entry, never by a passing suite.

### Dispatch has an authorization axis, not only a module-boundary one

The escape hatches from "a policy dispatches one command" are usually chosen by module boundary — in-process `executeCommand` same-module, client library cross-module. They also differ on **who the caller is**: `executeCommand` carries no principal of its own, so a command with an auth invariant (`GenerateInvoice` throws when `!user`) is **unreachable from a system-triggered policy** through it, whatever the module. `CronjobTriggered` and its kin carry **no tenant and no user by construction**, so a cron policy fanning out through `executeCommand` fails every dispatch at first real run — not at build, not in a unit test with a hand-made context. Dispatch through the client library with explicit per-call auth headers, and **take the tenant from the aggregate's own record, never from ambient context**: for a cross-tenant system principal a selection bug invoices the wrong tenant, and an externally authorised artifact cannot be taken back.

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

**Do NOT gate the reconcile on `isRedelivery`.** It looks like a free optimization, but `isRedelivery` is `false` on the crash/retry redeliveries (causes (a)/(b) — the *dominant* duplicate paths; see [DELIVERY.md](./DELIVERY.md)), so a "create directly when false" fast-path double-creates exactly there. The reconcile read (or external idempotency key) must run **unconditionally**. There is no `deliveryAttempt` in PV3.

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
