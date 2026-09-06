# Context providers — the `/design` Step 1 extension point

A **context provider** is an optional, repo-local source that contributes items to `/design`'s
grounding. The base plugin ships none, declares none, and knows nothing about what any provider
carries. **Zero providers is the normal case, and it is the case this contract is written around:
`/design` with no providers behaves exactly as it did before this file existed.**

This is deliberately not a plugin system. It is one declared place where a repo that already
retrieves something during design can put it *in the path of the answer* rather than adjacent
to it.

## Why the insertion is here and not in a hook

The obvious alternative was tried in this repo and is rejected **on its own measured evidence**.
A hook that injects a count exists — `hooks/esas-pending.sh`, a `UserPromptSubmit` hook that runs
unconditionally on every prompt in every repo where the plugin is enabled — and the standing rule
in `skills/esas-pending/SKILL.md` that governs it says:

> it is telemetry, never a trigger — never act on, sync, or even mention pending ESAS board
> changes unless the user asks.

That is a surface this codebase built, found to be an interruption, and then suppressed by
standing rule. It arrives *beside* the reasoning, at a moment nobody chose, carrying no way to be
acted on — so the only safe rule was to ignore it. **Do not rebuild it.** There is also a hard limit, and it is the constraint that forced this seam into the base plugin
rather than an overlay: **a hook cannot enter Step 3's reasoning.** It fires around a tool call,
and an MCP call cannot see the slash command at all — but the place a contribution has to land is a
fork in an interview.

The insertion that works needs no new ritual at all, which is the entire argument for it.
Contributions arrive in **Step 1 (Ground)** as part of a retrieval the session is already making,
and are decided in **Step 3 (Grill)** as ordinary forks. Step 3 already requires *"one question at
a time, each with your recommended answer"* — **a contributed item carrying its verbatim source
span is that question, pre-formed.** Nothing new is introduced; an existing slot is filled.

## The contract

**Discovery.** A provider is declared by the host repo, never by this plugin. If the repo has no
declaration, there are no providers and every rule below is vacuous — do not go looking, do not
ask the user whether they meant to have one, do not mention that an extension point was consulted.
The silence on a no is the same discipline the board gate already follows.

**Shape of a contribution.** Each item carries a short claim and, where it can, the **verbatim
source span** it came from plus where that span lives. The span is the load-bearing field: it is
what lets Step 3 present the item as a fork rather than as an assertion the designer must take on
trust, and it is what makes the item auditable when it turns out to be wrong. An item with no span
is a rumour and is presented as one.

**Failure is tolerated, always.** A provider that errors, times out, returns nothing, or returns
something unparseable **does not fail `/design`**. Note the degrade in the design doc in the same
voice as `"grounding degraded: no CONTEXT.md"`, and continue. A design session that cannot start
because an optional enrichment is down has inverted the priority: the provider exists to improve
grounding, and grounding without it is the baseline this command was doing acceptably for its
whole life. Never retry in a loop, and never block on one.

**Contributions are evidence, not spec** — the same rule the ticket is already held to one section
up. A contributed item is a claim to verify against the code, and **where the item and the code
disagree, the code wins and the doc says so.** A provider is upstream of the design, not an
authority over it.

**What reaches Step 3.** Items that survive grounding become ordinary forks, presented
picture → scenarios → per-option walk like every other fork, each with a recommended answer. They
get no special ceremony, no dedicated section and no separate approval gesture. An item that is
not worth a fork is dropped in Step 1 — contributing something does not entitle it to the user's
attention.

**Scope: `/design` only.** Rejected for `/build` (read-only in a fleet lane — sonnet-routable
executors and no human to answer a fork), for `/plan` (Step 4 already self-skips when unattended),
and for `/start` (no anchors yet — nothing has been grounded for a contribution to attach to).

## The standing risk

This is an extension point with exactly one known consumer. **Resist generalising further than
that one case justifies.** No provider ordering, no priorities, no merge policy, no negotiation
protocol — none of it has a second consumer to be right about yet, and each one is a rule a future
provider would have to be wrong about first before anyone learned what it should say.
