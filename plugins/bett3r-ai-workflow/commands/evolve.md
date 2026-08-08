---
description: Turn a plugin repo's accumulated ai-learning issues into reviewed PRs. Run inside the plugin repo whose issues you want to process.
---

# /evolve — issues → reviewed PRs

Process the `ai-learning` issues that `/capture-learnings` routed to **this** repo: cluster them, propose concrete changes, and open PRs for review. This is the per-repo consumer end of the propagation machine.

## Step 1 — Collect
`gh issue list --label ai-learning --state open` for this repo. Read each fully (body + comments).

## Step 2 — Cluster & dedupe
Group issues touching the same skill/command/agent or proposing the same change. Close exact duplicates (referencing the survivor). Drop or flag stale ones (already addressed, or no longer true). Converge the backlog — don't let it sprawl.

## Step 3 — Propose
For each cluster, decide the concrete change to the artifact. Where a change is contentious or a genuine trade-off, surface it for the user rather than guessing.

## Step 4 — Open PRs
For each agreed change: branch, make the edit, **bump the touched plugin's `.claude-plugin/plugin.json` `version`**, and open a PR that **links the issues it closes**, repeating the keyword on every one: `Closes #56, closes #62, closes #63`. **One PR per coherent change** (never one giant PR) so review stays tractable. Let the normal review pipeline (human and/or `/code-review`) gate the merge.

**A closing keyword binds to exactly one reference.** `Closes #56 #62 #63` closes `#56` and turns the rest into ordinary mentions — they get a cross-reference link and stay open. A comma does not help (`Closes #56, #62` closes one); only the repeated keyword does — `Closes #56, closes #62, closes #63`. This is the failure shape that costs the most here because nothing goes red: the commit is well-formed, the PR shows MERGED, CI is green, and the only tell is a backlog count. Seven such lines in one round turned **80 referenced issues into 7 closures and left 73 open**, found days later by counting. `scripts/check-closes-syntax.py` now refuses the malformed line at PR time — in the branch's commit messages *and* in the artifacts' own examples, because a wrong example is how the next round writes the wrong line again.

The bump is not bookkeeping and not optional: a plugin is copied into its version-keyed cache only when that string changes, so an unbumped edit merges cleanly and reaches nobody — which is exactly how two behaviour-changing commits once shipped to no one with every gate green (`docs/adr/ADR-001`). `scripts/check-plugin-version-bump.sh` now refuses the omission at PR time, and `plugins/<name>/README.md` counts as a touch, because it ships inside the payload.

## Step 5 — Audit the artifacts you touched
**The backlog is not the whole to-do list.** Issues only contain what someone *noticed* — and the defects that rot a shared plugin fastest are the ones that produce no signal at all. `/evolve` is the process that *writes* these artifacts round after round, and the only one that looks at them regularly, so it is where drift gets caught.

For every artifact this run touched, **and its immediate siblings**:

1. **Does it still load?** Frontmatter parses; the artifact actually appears in the commands/skills list. A malformed command doesn't error or warn — it silently never registers, and vanishes from every consuming repo. (Real miss: `/verify-build`, `/start`, and `create-readmodel` were all dead this way; `create-readmodel` had never once loaded, while `/create-module` referenced it as part of its scaffolding flow. Found only by hand-diffing the skills list against the file tree. Now gated by `scripts/validate-plugins.py` in the plugin repo — run it, don't eyeball it.)
2. **Is anything stale or local?** Guidance encoding a transient or machine-specific condition (a token scope, a tool version, a temporary workaround) is a liability in a shared artifact: it outlives the condition, and nothing prompts a re-check because the workaround *works*. Ask of each: *is this true everywhere, or only here and now?* (Real miss: a `gh api -X PATCH` detour that existed solely because one machine's token lacked `read:org`, distributed to every consuming repo as if it were a property of `gh`.)
3. **Has it accreted past coherence?** `/evolve` appends by nature — a list grows one bullet per round until it reads as N unrelated rules. Ask whether the accumulated items still share a frame, and give them one rather than letting the reader derive it. (Real miss: `/verify-build`'s ripple sweeps grew to six walls of prose before anyone named the single fact they all follow from.)

Findings here become their own PRs, exactly like backlog items.

## Step 6 — Report
The clusters, the PRs opened (with the issues each closes), what the audit surfaced, and anything left for the user to decide.

**For any PR of this round that has already merged, report the closure verdict — not the merge.** The issues are this command's entire deliverable, and `MERGED` is evidence about the branch, never about them. Re-read the state of the referenced set directly:

```sh
for n in 56 62 63 78 139; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

Expect **one line per reference, every one `CLOSED`**, and read the line count before the verdict — a short list or a blank state is `gh` failing, which is indistinguishable from calm if you only grep for the offenders. Close the stragglers by hand (`gh issue close <n> -c "landed in #<pr>"`) and say in the report that they did not close on their own, so the next round knows the syntax slipped.

## Principles
- **Convergent, not accumulative** — dedupe and close so the backlog stays a real to-do list.
- One coherent change per PR; **reviewed before merge** — these are shared artifacts many repos consume.
- Don't auto-merge. Evolve proposes; review disposes.
- **A failure mode whose signature is *absence* needs a gate, not a reviewer.** No one files a bug for a skill that was never there. Where a defect class produces no signal, add a mechanical check — a reviewer who has to *remember* to look is not a control.
