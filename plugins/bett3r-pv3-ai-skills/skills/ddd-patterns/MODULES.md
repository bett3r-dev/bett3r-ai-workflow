# PV3 module composition — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

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
