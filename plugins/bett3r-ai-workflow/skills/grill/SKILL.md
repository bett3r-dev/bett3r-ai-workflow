---
name: grill
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when the user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time. Do not use `AskUserQuestion`, Present the options and your recommendation with numbers as an ordered list.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Standard high-leverage probes

These are not the whole interview — they are questions that collapse a large branch of the tree in one move. Fire the relevant one whenever the design touches its trigger, *early*, before walking the branch the long way.

- **Side-effect reconcilability** — whenever the design performs an **external or otherwise non-idempotent side-effect** that can be retried/redelivered, ask: *"Is this side-effect **reconcilable** against the external system by a natural key — can you ask it 'does this already exist?' (a SKU, a client-reference, a transactionally-reserved number you can read back)?"*
  - **Yes** → reconcile by that key; build **no** local dedup structure (ledger/bitmap/lease). Reconcile is authoritative — it survives total loss of any local dedup store.
  - **No** → is the side-effect idempotent (a PUT / absolute-value set), or does it target something that already dedups (e.g. an aggregate with optimistic concurrency)? If so, nothing more is needed.
  - **Only** a side-effect that is non-idempotent **and** non-reconcilable justifies a best-effort local ledger — and say so explicitly, because a blind ledger otherwise just re-creates the act-then-mark gap it appears to close.

  This single question short-circuits the entire "how do we dedup external side-effects" branch — without it the tree gets walked the long way (position-bitmaps, leases, generic ledgers) to solve a problem reconcile dissolves. Framework-level guidance for PV3 lives in `bett3r-pv3-ai-skills` (policy idempotency / reconcile-by-natural-key).
