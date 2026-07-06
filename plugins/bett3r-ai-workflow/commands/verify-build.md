---

## description: Land the work — one whole-PR coherence review across all slices, a dev verification checklist, finalize ADRs, and open the PR as the system of record.

# /verify-build — land the work

The per-slice `verifier` already checked each slice in isolation during `/build`. This is the **cross-slice** pass: does the *assembled* feature hold together, and then turn the ephemeral working state into the durable record (ADRs + a PR).

## Argument: $ARGUMENTS

Optional ticket id. Default: the active work in `.work/slices.yaml`.

---

## Step 1 — Preconditions

Read `.work/slices.yaml` and `.work/design.md`. All slices should be `passes: true` and committed (`git log` shows one commit per slice). If slices remain unpassed, stop: "Slices N… not yet green — run `/build` first."

## Step 2 — Whole-PR coherence review

**Resolve the true base first — don't trust `master`/`origin/master` by default.** Under `/start-multi`'s worktree fleet, a per-ticket branch is cut from an *integration* branch that hasn't merged to `master` yet, so the branch's true fork point is that integration branch, not `master`. Diffing against a stale `master` silently inflates the scope (a real case: 509 files / +68k/−46k instead of ~67 files) and the coherence review runs against the wrong diff — a *silent* scope error, no command errors. Before reviewing:

1. Compute the diff against the assumed base, then **sanity-check its file count against `.work/slices.yaml`'s union of `touches:` paths.** If the diff is wildly larger (e.g. >3–5×), treat `master`/`origin/master` as **suspect**, not authoritative.
2. When suspect, resolve the real base: `git branch -r --contains <first-branch-commit>` to find the nearest integration/parent branch, and prefer `git merge-base <candidate> HEAD` over the assumed default.

Then diff the full branch against that resolved base (`git diff <base>...HEAD`). Read `${CLAUDE_PROJECT_DIR}/.claude/rules` for the repo's architectural checklist. Review the **assembled** change — the things no single-slice verifier could see:

- **Cross-slice invariants** — does the feature hold as a whole; do the slices compose correctly; any contract that two slices had to agree on?
- **Coherence** — consistent patterns across slices, no duplication introduced between them, no slice undone by a later one.
- **Design fidelity** — does the assembled result deliver what `.work/design.md` resolved? Note any deliberate deviation.
- **Quality** — real bugs, unsafe casts, security, dead code introduced across the diff. Look for accidental complexity, technical debt or anti-patterns relentlessly and be critical.

### Concrete ripple sweeps (run these, don't rely on eyeballing)

Per-slice gates only see a slice's own oracle. A change that ripples *outside* that oracle has no gate but this one — and the misses below were each a few greps away. Run all of them explicitly:

- **Cross-slice composition sweep.** Per-slice gates structurally cannot catch a defect whose *cause spans two slices*: each slice is individually correct, but they compose into a bad state in the seam. Enumerate the invariants/cursors/floors that more than one slice touches, and reason explicitly about each **pairwise** interaction — especially where one slice *advances* a value another slice *reads* or *trims* against. Run the full suite across the whole diff (not just per-slice oracles). (Real miss: a cold-start by-position *refill* (one slice) and a WAL Reader stream *trim* (another) were each correct, but composed into a silent-drop window — the trim floor advanced past an event that committed mid-refill because no heartbeat was held; neither slice's oracle could see the seam.)
- **Removal-grep sweep (deletion slices).** When a slice **deletes** a symbol, route, config field, or subsystem, build-passing ≠ caller-free: broken callers living in *sibling packages or the other repo* still compile that package fine. `grep` the whole repo(s) for every deleted symbol/route/field and assert **zero live callers remain**. (Real miss: a slice that deleted the bitmap/position subsystem left a `set-data-split-position` admin route → 404 at runtime in a separate package, a hand-written debug-mcp tool, and dead config fields — all green because the broken callers lived elsewhere.)
- **Mechanism-claim sweep.** Per-slice oracles test *behavior* (the outcome is correct), never the *causal model* (**why** it's correct) — so a green oracle can be green for the wrong reason. When a comment, ADR, oracle name, or the design narrative asserts *why* a guarantee holds by naming a framework mechanism ("X is additive/merged", "Y serializes this", "delivered in order", "this is atomic"), **verify that claim against framework source-of-truth before it propagates into the PR body** (the durable record). Flag unsubstantiated claims and correct them in-place rather than shipping them. (Real miss: a comment + oracle asserted "`receivedSeqs` is persisted via `jsonb_recursive_merge` (additive)"; the deep merge actually runs only on the first-insert race — the guarantee really held via the outbox's per-split `concurrency:1` serialization, and is therefore topology-dependent. The behavior was green; the stated reason was wrong and was headed into the PR body, masking a real multi-split hazard.) This is the mirror image of the disprove-Criticals rule below: there you disprove a *reported finding*; here you disprove *the claims the code makes about itself*.
- **Signature-ripple sweep.** For each exported symbol whose *signature* changed in the branch diff (an added/removed/retyped parameter, a changed return shape), grep **every** caller across the whole repo — explicitly including `*.integration.test.ts` / e2e / fixture files that are **excluded from the default `yarn test` run** and so never go red locally. Flag, and spot-run, any call site that doesn't match the new shape. (Real miss: a widened `getRulesWorkQueue`/`processRulesJob` arg fixed the one prod call site but left 7 integration suites passing the old signature — invisible because integration tests aren't in `yarn test`.)
- **Stale skip-rationale check.** Scan test files — especially skipped / `xfail` blocks and tracer tests that short-circuit a path — for comments that justify the skip/short-circuit by citing a blocker: a commit, a P0, a TODO, "broken on this branch". Re-validate each rationale against `HEAD`: a *later* slice or follow-up on the same branch may have already fixed the cited blocker, leaving the path uncovered and the comment lying. (Real miss: a slice-1 tracer drove the command directly "because `getRulesWorkQueue` is a P0"; a later commit fixed that P0 but the tracer and its rationale were never revisited, so the rule→command wire stayed untested.)

Apply the `critique` skill's tone throughout: substance over compliments, no hedging, every finding specific and actionable with a concrete fix. For an assembled feature that crosses a non-trivial architectural seam, run a focused `critique --lens arch,ops` pass over the diff and fold its verdict into the findings below.

**Disprove every Critical/High before propagating it.** A plausible-sounding Critical that's actually a false positive is *more* expensive than a missed nit — "fixing" it introduces a regression. Before reporting or acting on any Critical/High finding, attempt to **disprove** it: (a) read the actual call site — not the diff hunk in isolation; (b) run a `git blame` / base-branch check — "is this pre-existing on the base, not introduced by this PR? Y/N"; (c) construct a concrete failing input that reproduces it. Drop or downgrade any Critical that can't survive all three. (Real miss: 3 of 4 reported Criticals on TV1-1950 were false positives — a truthy `'0'` misread as falsy, a verbatim-from-`master` pre-existing line, and a "double increment" that was load-bearing for restart determinism — each would have introduced a bug if "fixed"; the git-blame check alone kills two of them.)

Surface findings by severity (Critical / Medium / Low). Fix Critical/Medium before opening the PR (small fixes inline or a follow-up slice). Offer you recommendation for open issues. This review is **not** committed to a file — its conclusions go into the PR body.

## Step 3 — Dev verification checklist

Produce a single **developer verification checklist**: the things a human should manually confirm that the automated slice tests do **not** cover — UI/UX, a browser smoke for a user journey, anything environment-specific. One lean list. (No separate QA plan.) This goes in the PR body, not a committed file.

## Step 4 — Finalize the durable record

- **ADR(s):** ensure the decisions from `.work/design.md` that aren't recoverable from code are captured as committed ADR(s) in the repo's ADR location. Commit them if not already.
- **Promote the design:** the design narrative + conclusions from `.work/design.md` become the **PR description** — they are *not* committed as a standalone doc.

## Step 5 — Open the PR (the system of record)

Push the branch and open the PR (compose the repo's `create-pr` flow if it has one; otherwise `gh pr create --base <resolved-base>` — pass the base resolved in Step 2, not a hardcoded `master`). **Verify the created PR's base after the fact:** `gh pr create` succeeds silently even when it targets the wrong ref, so confirm the PR's `changed_files`/`commits` roughly match the local `git log <base>..HEAD` count/diffstat. If they don't, retarget with `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<true-base>` — **not** `gh pr edit --base`, which can fail with an unrelated GraphQL token-scope error and leave the base silently unchanged. The PR **body is the record**:

```
## <TICKET-ID> — <title>

<design narrative + key decisions, promoted from .work/design.md>

### Slices
- slice 1 — <name> (<commit>)
- slice 2 — <name> (<commit>)
- ...

### Verification
<the dev checklist from Step 3>

### Decisions
- ADR-NNN — <title>

### Coherence review
<Critical/Medium findings and how resolved; or "clean">
```

## Step 6 — Cleanup

The ephemeral `.work/` (design.md, slices.yaml) has now been fully promoted (ADRs + PR body + per-slice commits). It is gitignored and may be discarded. Report the PR URL.

> If this work surfaced an improvement to the *flow or a shared skill/plugin* (not this feature), run `/capture-learnings` to route it to the repo that owns it.

## Principles

- The PR is the system of record — invest in its body, not in committed scratch docs.
- This pass is cross-slice; trust the per-slice gates for within-slice correctness.
- Tone follows the `critique` skill: substance over compliments, specific and actionable findings.

