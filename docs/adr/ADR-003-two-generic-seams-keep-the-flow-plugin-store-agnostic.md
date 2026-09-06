# Two generic seams keep the flow plugin store-agnostic

`/design` and `/build` needed to become reachable by an external consumer: one that wants to know
what mode a session is in, and one that wants candidate items to reach a designer while they are
designing. Both requests arrived from the same place, and the tempting shape was to satisfy them
where they were asked — teach the commands about the consumer.

We did the opposite. Two seams were added to the base flow plugin, **neither of which names any
consumer**, and both of which are useful to this plugin on their own terms:

* **Seam A — `.work/mode.yaml`.** `/start`, `/design`, `/plan` and `/build` each record the current
  mode and work item. Overwritten in full, never appended. `/start` clears it.
* **Seam B — a context-provider extension point in `/design` Step 1.** An optional, repo-local
  source may contribute grounding items, which surface in Step 3 as ordinary forks. No provider
  ships in the base plugin and zero providers is the normal case.

The invariant this protects: **the base flow plugin stays store-agnostic, and a consumer adapts to
the flow, never the reverse.** A seam that mentions its first consumer has already broken it, so
`scripts/test-flow-seams.sh` asserts mechanically that no seam file mentions one.

## Seam A is a defect fix, not an accommodation

The request assumed a session's mode was inferable. It is not, and establishing that was the
finding:

* **No command wrote any mode, phase or current-command marker.** `/start` wrote exactly one file,
  `.work/known-baseline-failures.md`.
* Every other `.work/` observable — `design.md`, `slices.yaml`, `passes:`, `design-snapshot/`,
  `fleet-lane.yaml`, the branch name — is **accumulating residue that is never erased.** So a
  `/design` re-run mid-build was indistinguishable from `/build`.
* `commands/start.md` documents stale `.work/` from the prior branch as a normal state it proceeds
  through **by default**.
* Observed live: a checkout sitting on one branch while `.work/handoff/` held four files from an
  unrelated ticket.
* **MCP tool calls carry no slash-command context at all** — no server can see `/build`, whatever
  it does.

So the flow could not say what it was doing. That is a defect independent of anyone asking, which
is why the fix belongs in the base plugin and why it is worth its own file rather than a field
someone else maintains.

**The clearing is the load-bearing half, not the writing.** A marker is one more `.work/` file that
can go stale, and a stale marker is strictly worse than none: absent, you know you do not know;
stale, you are confidently wrong about which work item you are on. Append-only was rejected outright
for reproducing the exact residue bug the marker exists to end.

## Seam B: the hook alternative was rejected on this repo's own measured evidence

This is the part worth recording, because the rejected option is the one a reasonable person
proposes first, and the argument against it is **not** taste.

**A hook that injects a count already exists here.** `hooks/esas-pending.sh` is a `UserPromptSubmit`
hook that runs unconditionally, on every prompt, in every repo where the plugin is enabled. It was
built, shipped, and then **suppressed by a standing rule** — `skills/esas-pending/SKILL.md` says of
its output:

> it is telemetry, never a trigger — never act on, sync, or even mention pending ESAS board changes
> unless the user asks.

That is a complete experiment with a recorded result. This codebase built the injection surface,
found it an interruption, and wrote a rule whose entire content is *ignore it*. Rebuilding the same
shape for a second consumer would re-run an experiment we already paid for. The failure is
structural, not a tuning problem: a hook fires at a moment nobody chose, lands *beside* the
reasoning rather than in it, and offers no way to act on what it carried — so the only safe rule
was the one that got written.

There is also a hard limit. **A hook cannot enter Step 3's reasoning.** It wraps a tool call; the
place a contribution has to land is a fork in an interview. No amount of hook engineering reaches
it, which is why this could not be solved in an overlay plugin at all — and why these seams had to
be added to the base plugin rather than adapted around it.

**The insertion that works introduces no new ritual, and that is the whole argument for it.** Step 3
already requires *"one question at a time, each with your recommended answer."* A contributed item
carrying its verbatim source span **is** that question, pre-formed. Nothing new is invented; an
existing slot is filled.

## Consequences

**Zero providers is the normal case, and it must be silent.** Not merely harmless — silent. A seam
that announces itself in every repo not using it has become the interruption it was designed to
avoid, which is precisely how `esas-pending.sh` failed. `/design` with no providers behaves exactly
as it did before, and does not mention that an extension point was consulted.

**Failure tolerance is a correctness property, not politeness.** A provider that errors, times out
or hangs must never fail `/design`. The seam is optional enrichment on top of grounding the command
did acceptably for its whole life; a design session that cannot start because an enrichment is down
has inverted the priority.

**Contributions are evidence, not spec** — the same rule the ticket is already held to. Where a
contributed item and the code disagree, the code wins.

**Resist generalising Seam B.** It is an extension point with exactly one known consumer. No
ordering, no priorities, no merge policy, no negotiation protocol: none has a second consumer to be
right about, and each is a rule a future provider must first be wrong about before anyone learns
what it should say.

**The version bump is part of the change, not follow-up.** Per ADR-001, a plugin payload change that
does not move `plugins/bett3r-ai-workflow/.claude-plugin/plugin.json` reaches no session at all.
Both seams are payload.

## Considered options

- **Put consumer logic directly in `/design` and `/build`.** Simplest, and it breaks the coupling
  invariant permanently — the base plugin would carry knowledge of a consumer that most repos using
  it will never install.
- **Do it all in an overlay plugin, leaving the base untouched.** Preferred on principle and
  **impossible in fact**: an MCP call cannot see the slash command, and a hook cannot enter Step 3's
  reasoning. This is the constraint that forced base-plugin seams.
- **A hook-injected count.** Rejected on measured evidence above: that surface exists here, was
  found an interruption, and is suppressed by standing rule.
- **Append-only mode history instead of an overwritten marker.** Rejected — it reproduces the
  accumulating-residue bug Seam A exists to fix.
- **A required provider registry.** Rejected. It makes every repo declare something to say "none",
  and turns an optional enrichment into a startup dependency.
- **Seam B in `/build`, `/plan` or `/start` as well.** Rejected each for its own reason: `/build` is
  read-only in a fleet lane with no human to answer a fork, `/plan` Step 4 already self-skips when
  unattended, and `/start` has no anchors for a contribution to attach to.
