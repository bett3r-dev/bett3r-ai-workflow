# Context providers: the `/design` Step 1 extension point

A **context provider** is an optional, repo-local source that contributes grounding items to `/design`. The base plugin ships none and knows nothing about what a provider carries, and zero providers is the normal case: `/design` with none declared behaves exactly as it did before this file existed and says nothing about an extension point.

## Declaration

A provider is declared only by the host repo, as a `contextProviders` key in `.claude/bett3r-ai-workflow.json`, beside `workDocsRoot`:

```json
{ "contextProviders": [ { "server": "<mcp server>", "tool": "<tool>" } ] }
```

Nothing else declares one: a provider's MCP tool being present in the session is ambient state no repo owner opted into, and a capture marker says a repo captures, not that it wants its designs grounded.

## What a contribution is

Each item carries a short claim and, where it can, the **verbatim source span** it came from and where that span lives. The span is what lets Step 3 present the item as a fork with something to check rather than an assertion to take on trust; an item with no span is a rumour and is presented as one.

Contributions are evidence, not spec, held to the rule the ticket is held to: a claim to verify against the code, and where the two disagree the code wins and the design doc says so. Items that survive grounding become ordinary Step 3 forks, presented like every other fork with a recommended answer and no ceremony of their own; an item not worth a fork is dropped in Step 1.

## Recording, optionally

The same declaration may name a call for **recording** a decision. Where it does, `/design` Step 3, the `design-lane` agent and the `/design-multi` sitting offer each fork's answer back at the moment it is answered, and nowhere else. An id the call hands back has one home, the sidecar `design-map record` names in its verdict, never `map.json`. A declaration naming no such call, a call that refuses, times out or is unreachable, and a repo declaring nothing behave as one: the verdict is unchanged and one notice names the fork that went unrecorded.

## Failure is tolerated, always

A provider that errors, times out, returns nothing, or returns something unparseable **does not fail `/design`**. Note the degrade in the design doc in the voice already used for `"grounding degraded: no CONTEXT.md"` and continue. Never retry in a loop, and never block on one: grounding without the provider is the baseline this command always had.

## Scope: `/design` only

The seam is about contribution, and a contribution lands at a fork in an interview. `/build` is rejected because a fleet lane runs unattended (no human to answer a fork); `/plan` because its review step already self-skips when unattended; `/start` because nothing is grounded yet for a contribution to attach to. The rejection bounds contribution, not retrieval: a step that calls a tool for its own use and asks nobody anything is outside this seam.

## Why a seam and not a hook

This repo already ships a hook that injects context, `hooks/esas-pending.sh`, and the standing rule in `skills/esas-pending/SKILL.md` calls the line it prints "telemetry, never a trigger": a surface built, found to be an interruption, and suppressed. Beyond that, a hook cannot enter Step 3's reasoning, since it fires around a tool call and the place a contribution must land is a fork in an interview. One known consumer exists, so the seam gains no ordering, priorities or merge policy until a second one shows what those should say.
