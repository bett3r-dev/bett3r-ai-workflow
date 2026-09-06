---
description: Turn a plugin repo's ai-learning issues into reviewed PRs — with a mandatory prune pass and a net-change budget, so the artifacts converge instead of accreting.
---

# /evolve — issues → reviewed PRs, with pruning pressure

Process the `ai-learning` issues routed to **this** repo: prune, cluster, propose, and open PRs for review.

A process that only ever adds is convergent about the *backlog* and monotonic about the *artifacts* — nothing is ever positioned to take anything out. `/evolve` is the only process that reads these files regularly, so **it is the only place a rule can die.** That is what steps 1 and 5 exist for.

## Step 1 — Prune, before you read a single issue

For **every artifact this run will touch**, and its immediate siblings, find what should come out. Do this first, deliberately, and report the result even when it is nothing — a prune pass that always finds nothing is itself a finding about this step.

Four tests. A rule failing any one is a **prune candidate**, and prune candidates are proposed to the user like any other change:

1. **Expired.** The issue that created it named an expiry (`/capture-learnings` requires one), or the rule visibly depends on a tool version, a model behaviour, a repo shape, or a workaround. **Check whether the condition still holds.** A rule defending against a mistake the current model no longer makes is pure attention cost.
2. **Redundant.** Another rule in the same artifact, or in an artifact loaded alongside it, already says this. Duplication is invisible while it is spread across files and obvious the moment you look for it — one real audit collapsed 3 files / 1,487 words into 1 file / 1,439 by inlining, and the duplication only surfaced during the move.
3. **Anecdote outweighing rule.** The behavioural instruction is one sentence and the story justifying it is a paragraph. Keep the rule, compress the story to the clause that makes it credible ("three lanes once picked the same `ADR-057`"). The story is what makes a rule *stick* on first read and what makes the artifact unreadable on the twentieth — one clause buys most of the first at little of the second.
4. **Restating a default.** The rule tells a competent model to do what it would do anyway. Delete it. If it is a real trap that caution alone cannot avoid, **replace it with a gate in `scripts/`** rather than a longer paragraph.

**What is never pruned**, however old: a **cross-repo literal** (a route, an error code, a port, a spelled id) — a paraphrase breaks the gesture with both suites green on both sides; a **fact about this system** that competence does not supply; and a rule whose failure mode is **silent**, unless you can show the condition is gone.

## Step 2 — Collect, cluster, dedupe

`gh issue list --label ai-learning --state open`. Read each fully (body + comments). Group issues touching the same artifact or proposing the same change. Close exact duplicates (referencing the survivor). Drop or flag stale ones. Converge the backlog — don't let it sprawl.

**Read each issue's `Filters` and `Expiry` sections as part of the proposal.** An issue that cannot say why a competent model gets this wrong with no guidance is a candidate for closing unfiled, not a candidate for a rule.

## Step 3 — Propose, under a net-change budget

For each cluster, decide the concrete change. Where it is contentious or a genuine trade-off, surface it rather than guessing.

**Every PR that adds lines to an artifact states, in its body, what it removed — or why nothing could be.** Not a hard cap: a genuinely new rule may cost net lines. It is a forcing function, and the honest answer is often that the addition should be an *amendment* to the rule three paragraphs up. Record each touched artifact's line and word count **before and after**.

**Prefer, in this order:** amend an existing rule → merge two rules under one frame → add a gate in `scripts/` → add a new rule.

### Whether to split an artifact — decide before deciding how

Sooner or later an artifact is "too big" and the reflex is to move a section to a reference file. That reflex is wrong about as often as it is right, and silent either way.

**The trade is attention against loading probability.** A long artifact dilutes: every rule competes with the whole file for finite attention and the ones in the middle lose. A split concentrates what remains, but the extracted content is now read only if the pointer is followed — probability < 1, with nothing observable saying which.

- **There is a floor, and below it inlining wins outright.** Measured case: a 468-word skill whose two references were 668 and 351 words — smaller than its own references combined. **A split you can delete beats a split you have to verify forever.**
- **Split by trigger, never by topic.** Content may leave only when its loading is gated on a condition something *already evaluates and acts on*. "Fleet mechanics" is a topic and makes an unsafe split; "this unit checks out 2+ repos" is a trigger and makes a safe one.
- **Explanation may be referenced. Behavior may not.** Ask what happens when the pointer is *not* followed. If the artifact still acts correctly and merely loses the *why*, the split is safe.
- **For behavior, use a subagent instead — a split with loading probability 1.** Fresh context, dispatched at the moment it applies, nothing competing. What must *not* go: anything the parent is required to verify for itself.
- **Splitting is not a token optimisation.** Measured on a real fleet run, cache reads were **97% of raw tokens**, and an artifact's own text is 1–4% of a typical agent's ~210k per-turn context. When the split content *is* needed it is loaded anyway, so the saving is zero exactly when it matters. Split for **attention**; if the stated reason is cost, the lever is elsewhere.

Plugin-wide totals barely move on a split — extraction relocates words. Per-artifact load is what changed. **Pruning is the only thing that reduces the total**, which is why Step 1 exists.

## Step 4 — Open PRs

Branch, edit, **bump the touched plugin's `.claude-plugin/plugin.json` `version`**, and open a PR that **links the issues it closes, repeating the keyword on every one**: `Closes #56, closes #62, closes #63`. **One PR per coherent change.**

**A closing keyword binds to exactly one reference.** `Closes #56 #62 #63` closes `#56` and leaves the rest open as mentions; a comma does not help — repeat the keyword: `Closes #56, closes #62, closes #63`. This is the failure shape that costs most, because nothing goes red: well-formed commit, PR `MERGED`, gates green, and the only tell is a backlog count. Seven such lines once turned **80 referenced issues into 7 closures**, found days later by counting. `scripts/check-closes-syntax.py` refuses the malformed line at PR time — in commit messages *and* in the artifacts' own examples, because a wrong example is how the next round writes the wrong line again.

**When a round opens N PRs from one base, allocate the versions across them up front and state the merge order in each body.** Two PRs cut from one commit that bump to the *same* string produce no textual conflict — both read `MERGEABLE`/`CLEAN`, and the version gate's green on the second is a claim about a base the first has since replaced ([EVIDENCE.md](../EVIDENCE.md) §3). Re-run the gate locally against the current base before merging.

**The version bump is not bookkeeping.** A plugin is copied into its version-keyed cache only when that string changes, so an unbumped edit merges cleanly and reaches nobody — exactly how two behaviour-changing commits shipped to no one with every gate green (`docs/adr/ADR-001`). `scripts/check-plugin-version-bump.sh` refuses the omission; `plugins/<name>/README.md` counts as a touch, because it ships inside the payload.

**A PR that splits an artifact writes the eval scenario in the same pass** — not a follow-up issue: this pass is the last moment anyone knows what the pointer was for. Every gate in `scripts/` asserts presence **corpus-wide** by design, so a split is green whether the pointer is ever opened or not. The only remaining evidence is a session that opened the file: a scenario in `scripts/eval/` asserting `must_open`, testing a rule that exists **only** behind the pointer (an answer the model could produce from priors proves nothing — the tool call is the evidence). `scripts/check-eval-coverage.py` refuses an unguarded split.

## Step 5 — Audit, and measure the ratio

**The backlog is not the whole to-do list** — issues contain only what someone *noticed*, and the defects that rot a shared plugin fastest produce no signal at all.

For every artifact touched, and its siblings:

1. **Does it still load?** Frontmatter parses; it appears in the commands/skills list. A malformed command does not error or warn — it silently never registers and vanishes from every consuming repo. (Real miss: `/verify-build`, `/start` and `create-readmodel` were all dead this way; one had never once loaded while another command referenced it.) Run `scripts/validate-plugins.py`; do not eyeball it.
2. **Is anything stale or local?** *Is this true everywhere, or only here and now?*
3. **Has it accreted past coherence?** A list that grew one bullet per round reads as N unrelated rules. Ask whether the accumulated items still share a frame, and give them one rather than letting the reader derive it.

Then **report the ratio, per artifact and for the round: lines and words added vs removed, and rules added vs amended vs deleted.** This is the number that tells you whether the plugin is converging or accreting, and it is the whole reason this step exists. If a round adds and never removes, say so plainly in the report rather than letting it pass as progress.

## Step 6 — Report

The prune candidates (accepted and rejected), the clusters, the PRs opened with what each closes, what the audit surfaced, the add/remove ratio, and anything left for the user to decide.

**For any PR of this round already merged, report the closure verdict — not the merge.** The issues are this command's deliverable, and `MERGED` is evidence about the branch:

```sh
for n in 56 62 63 78 139; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

Expect **one line per reference, every one `CLOSED`**, and read the line count before the verdict — a short list or a blank state is `gh` failing, indistinguishable from calm if you only grep for offenders. Close stragglers by hand and say the syntax slipped.

## Principles
- **Convergent in both directions.** Converge the backlog *and* the artifacts. A round that only adds is a round that made every future session slightly worse.
- **Amend > merge > gate > add.** In that order, every time.
- **Attention is the scarce resource**, not tokens. Split for attention, prune for attention, and never split as a cost optimisation.
- **A failure mode whose signature is *absence* needs a gate, not a reviewer.** No one files a bug for a skill that was never there.
- **Never prune a cross-repo literal, a system fact, or a silent-failure rule** without showing the condition is gone.
- One coherent change per PR; **reviewed before merge**. Evolve proposes; review disposes. Don't auto-merge.
