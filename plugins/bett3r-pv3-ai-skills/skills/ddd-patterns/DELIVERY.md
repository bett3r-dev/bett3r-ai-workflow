# PV3 event delivery — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

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
- **Policies — case-by-case.** Order within a stream is guaranteed; what a policy must survive is duplicate redelivery. *Idempotent reaction* (re-applying is a no-op): nothing needed. *Non-idempotent reaction* (accumulates, or fires a per-transition side effect): make each dispatched command idempotent (see [POLICIES.md](./POLICIES.md)) **or** hold a per-stream watermark/side-table — and never assume cross-stream order. (Redelivery-safety makes a handler idempotent under replay; the watermark makes a dedup-requiring handler correct under at-least-once.)

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

### A thrown error is classified by HTTP STATUS, not by error type

`pv3-library-outbox-manager/eventProcessing.ts` retries a rejected handler only when its status is in `defaultRetryableStatuses = [ 408, 429, 502, 503, 504 ]`. Everything else — resolved as `e.status || 500` — is **critical**: poison event, per-stream quarantine, recoverable only through the admin `retry-stream` endpoint. **A plain `Error` has no status, resolves to 500, and is therefore NOT retry-eligible**; throwing one "so the outbox retries" quarantines the stream, the opposite of what it looks like. To get a retry (projection lag, dependency down) throw an error carrying a retryable status, e.g. `ServiceUnavailableError` → 503. To fail terminally with a clear diagnostic, throw `BadRequestError`. There is no third option where a plain `Error` retries — and a critical status quarantines **that stream only**; other streams on the split keep flowing.

### TL;DR for a consumer author

1. **Assume at-least-once** — the same event can arrive again.
2. **Rely on per-stream order; never on cross-stream / global order.**
3. **Dedup with a per-stream version watermark, not global position — and 2xx duplicates.**
4. **Make external side effects idempotent** — commit the watermark *with* the effect, or use a dedup key.
5. **`isRedelivery` is a replay *hint*, not dedup** — true only on operator replay (c); false on (a)/(b).
6. **A retry is a status, not an error class** — throw a 503-class error for transient failure; a plain `Error` is a poison event.

### Redelivery-safe external effects: the A/B/C layer model

When a non-idempotent external effect must survive at-least-once redelivery, three distinct questions each get their own layer. They compose in a fixed order; use whichever layers the hazard requires.

| Layer | Answers | Mechanism |
|---|---|---|
| **A — aggregate invariant** | "already *recorded* this fact?" | `withIdempotencyCheck` on state — a bounded key-set (`array.slice(-N)`, keyed on an inbound-trigger id riding event **metadata**, never payload) for a many-times fact, or an O(1) boolean marker when at most one occurrence is possible |
| **B — policy checkpoint** | "already *performed* this external action?" | A shared `guardExternalEffect` helper (lives in `<domainUtilsPackageName>`) wrapping `transactionalIdempotencyCheckpoint(event.id)` — durable (Postgres), survives cache/snapshot loss, keyed on the trigger's committed `event.id` |
| **C — reconcile-by-natural-key** | "did the external system already accept it (crashed before we recorded)?" | Query the external system by its own natural key, run **unconditionally** on every delivery — see *reconcile by natural key* in [POLICIES.md](./POLICIES.md) |

**Guard order at the boundary:** `isRedelivery`-skip **FIRST** (ACK, zero I/O, zero checkpoint mutation — an operator force-replay reprojects read models via reconcile only), **THEN** the B/C dedup. Do **not** use `isRedelivery` as the dedup gate — it is `false` on exactly the crash-before-mark duplicate B/C exist to close (`isRedelivery` ⇔ `version ≤ watermark`; a crash-window duplicate is `version > watermark`), so it is a no-op precisely where duplication happens.

**The graceful-no-op / no-throw contract:** every dedup/skip path MUST resolve as command **success**. A throw on a null-version stream dead-letters and trips the outbox circuit breaker; on a versioned stream it halts the stream. A shared guard returns a value the caller branches on — e.g. `guardExternalEffect(...) → { performed: boolean, result?: T }` — rather than signalling "already done" by throw/catch. Even in a repo without that exact package, the composition (event-id-keyed checkpoint + optional reconcile, in the fixed order above) is the reusable part.
