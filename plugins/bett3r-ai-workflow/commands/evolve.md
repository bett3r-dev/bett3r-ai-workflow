---
description: Turn a plugin repo's ai-learning issues into reviewed PRs, with a prune pass first and a net-change budget, so the artifacts converge instead of accreting.
disable-model-invocation: true
---

# /evolve — issues → reviewed PRs, with pruning pressure

`Call the Skill tool with "writing-for-agents"`. Every prune decision and every proposed edit below is judged by it. Run this inside a plugin repo: `/evolve` is the only process that reads these artifacts regularly, so it is the only place a rule can die.

## Step 1 — Prune before reading an issue

For every artifact this run will touch, and its immediate siblings, list what comes out, judged by writing-for-agents' pruning tests: a rule whose `Expiry` condition no longer holds or whose tool, model or repo shape has changed; a second occurrence of a meaning that has a home elsewhere (it becomes a pointer); a sentence the model obeys by default; and an incident, measurement or story sitting in instruction text (it moves to the ledger, Step 4). Not pruned without showing the condition is gone: a cross-repo literal (a route, an error code, a port, a spelled id, since a paraphrase breaks the gesture with both suites green), a fact about this system that competence does not supply, and a rule whose failure mode is silent. Report the result even when it is empty; a prune pass that always finds nothing is a finding about this step. Done when each touched artifact has a prune list with a reason per item.

## Step 2 — Collect, cluster, dedupe

`gh issue list --label ai-learning --state open`; read each fully, body and comments. Group issues touching the same artifact or proposing the same change; close exact duplicates naming the survivor; flag stale ones. Read each issue's `Filters` and `Expiry` as part of the proposal: an issue that cannot say why a competent model gets this wrong with no guidance closes unfiled. Done when every open issue is in a cluster, closed, or flagged.

## Step 3 — Propose under a net-change budget

Decide the concrete change per cluster and surface genuine trade-offs rather than guessing. Prefer, in order: amend an existing rule, merge two rules under one frame, add a gate in `scripts/`, add a new rule. Every PR that adds lines states in its body what it removed, or why nothing could be; record each touched artifact's line and word count before and after. A new rule names what it replaces or sits next to.

Splitting an artifact is a decision on its own. Split by trigger, never by topic: content leaves only when its loading is gated on a condition something already evaluates and acts on. Explanation may be referenced. Behavior may not: if the artifact still acts correctly with the pointer unfollowed, the split is safe. For behavior, dispatch a subagent instead, a split with loading probability 1. Splitting is not a token optimisation; split for attention, and prune to reduce the total. A split you can delete beats a split you have to verify forever. Done when every cluster has a change, its preference rank, and its budget line.

## Step 4 — Ledger the evidence

Where a rule's justification is an incident, a measurement or a war story, the artifact keeps the rule and the story moves to the plugin's ledger, the file `LEDGER.md` at the root of the plugin's payload beside its `README.md`, as one entry: the rule, the source it came from, the evidence verbatim, when it was recorded, and what retires it. Done when no touched artifact carries a date, a figure or a "once" story as instruction text.

## Step 5 — Open PRs

Branch, edit, and bump the touched plugin's `.claude-plugin/plugin.json` `version` (ADR-001: the install is a version-keyed cache that copies nothing while the string stands still, so an unbumped edit merges cleanly and reaches nobody; `scripts/check-plugin-version-bump.sh` refuses the omission, and `plugins/<name>/README.md` counts as a touch). Run `python3 scripts/validate-plugins.py`: a malformed artifact never errors, it silently stops loading. One PR per coherent change, reviewed before merge.

The body links the issues it closes with one keyword per issue, `Closes #12, closes #13` (the rule's home is `/verify-build` Step 6; `scripts/check-closes-syntax.py` refuses a bare list in commit messages and in these artifacts' own examples). A PR that splits an artifact writes the eval scenario in the same pass: a `guards_split` scenario in `scripts/eval/scenarios.json` asserting `must_open` on the companion, because every gate in `scripts/` asserts presence corpus-wide and only a session that opened the file is evidence the pointer works; `scripts/check-eval-coverage.py` refuses an unguarded split.

When a round opens several PRs, allocate the versions up front and state the merge order in each body. Cut from one base: two PRs bumping to the same string produce no textual conflict, and the version gate's green on the second is about a base the first has since replaced ([EVIDENCE.md](../EVIDENCE.md) §3), so re-run the gate locally against the current base before merging. Stacked: merge the parent keeping its branch, `gh pr edit <child> --base <default>`, re-run the diff-reading gates against the new base, merge, and delete the stack's branches only after the last one lands. Done when every PR is open with its version, its merge order, and its closes lines.

## Step 6 — Audit and measure

For every artifact touched and its siblings: does it still load (`validate-plugins.py`, not a glance); is anything stale or local; has a list grown one bullet per round past a shared frame. Then report the ratio, per artifact and for the round: lines and words added against removed, and rules added, amended and deleted. A round that only adds says so. Done when the ratio is stated.

## Step 7 — Report

The prune candidates accepted and rejected, the clusters, the PRs with what each closes, the audit findings, the ratio, and what is left for the user. For any PR already merged, report the closure verdict rather than the merge:

```sh
for n in <every issue this round references>; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

One line per reference, every one `CLOSED`; read the line count before the states, since a blank state is `gh` failing. Close stragglers by hand and say the syntax slipped.
