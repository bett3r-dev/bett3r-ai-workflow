---
description: Land the work — one whole-PR coherence review across all slices, a dev verification checklist, finalize ADRs, and open the PR as the system of record.
---

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

### Concrete ripple sweeps (run them; don't eyeball)

Every sweep below is one of two facts. Most are [EVIDENCE.md](../EVIDENCE.md) §1 — *a verdict is evidence only about what it executed*, and each row is a different way that path was narrower than it looked. The rest are the one class with **no per-slice gate at all: composition** — two slices individually correct, the defect in the seam between them. "Both slices were individually correct" is the *signature* of a real composition finding, never a reason to downgrade it.

A recurring trait makes several of them hard to see: **the broken code is code this PR never touched.** A diff-shaped review looks straight past it, because what changed is the *meaning* of something the old code still reads. When a diff redefines a value's semantics, review the **readers of that value**.

`/build` runs a first-pass ripple check per slice. **Do not assume it caught anything** — its carry-forward is a claim to verify against `HEAD` (§3), not evidence. These sweeps are the backstop.

| When the diff… | Prove | The tell (each cost a real miss) |
|---|---|---|
| **deletes** a symbol / route / config field / subsystem | zero live callers across **every** repo — a broken caller in a sibling package still compiles that package fine | a deleted bitmap subsystem left a live admin route → runtime 404, plus a debug tool and dead config, all green |
| changes an **exported signature** | every caller matches, **including** `*.integration.test.ts` / e2e / fixtures excluded from the default run — then run those suites or flag them un-run | a widened arg fixed the one prod site; 7 integration suites kept passing the old shape, invisible to `yarn test` |
| adds a **new reader** of an already-persisted table / index / collection | reason about *what the query can return*, not when it runs: enumerate **every other writer** and prove this key space cannot select their rows, or narrow it until it can't | the safety argument is phrased as control flow ("only runs when X failed", "byte-identical for existing callers"). Control flow is about your code; the rows belong to someone else |
| touches **event schemas**, **persisted field names**, or **idempotency/dedup records** | (1) a rename/removal ships an upcaster or version bump; (2) rows written *before* this diff still work, with a test that exercises one; (3) name the changed path that has no test | a "pure rename" rehydrated the aggregate to `accounts["undefined"]`; a reversal keyed off a field pre-enrichment rows lacked |
| has **migrate-on-read** for a persisted format | reads and writes agree per version: recognized-legacy **migrates on write** (never dead-ends the session), genuinely-newer **refuses, typed** — and both directions are tested | a file that rendered everywhere refused every write; the fold restamped a v99 file *down*, the exact loss its own comment claimed was closed |
| introduces an **adjustment to a total / count / threshold** | every *other* site comparing against the **unadjusted** value (`< total`, `>= totalItems`) is fixed — and if more than one site computes the adjusted value, **collapse them into one exported function** | a stale canary WARNed on every no-op batch. Fixing only the arithmetic left the duplication, and the next skip-bucket re-broke it at the same line two weeks later. **A sweep firing twice on one site means the earlier remedy was too shallow** |
| introduces a **mechanical guard** (conflict, tenancy, rate, permission) | name the field its dispatch condition reads, then enumerate **every surface that can set it** — tool schemas, HTTP bodies, message payloads, defaults. Stamp at each surface; never validate the claim | one frontend hard-stamped `author: 'human'` with a comment on why spoofing was impossible; the sibling MCP surface forwarded it as an optional parameter, disarming the guard entirely |
| ships an **on-demand "operate over my rows" endpoint** | the tenant is derived from the authenticated user and pushed into the query filter — never from an optional body field, never a system-wide scan for an authed caller (cron/system paths legitimately stay unscoped). Build the two-tenant repro | single-tenant harnesses cannot see it: build, `generate:check` and a green Postgres integration test all passed a cross-tenant reconcile |
| implements a **reversible operation** | the **inverse** on the real adapter too, with its write semantics stated. A forward-green gate — or an inherited "verified on Postgres" — says nothing about the other direction | the two directions took different write paths: a dot-path write forward, a whole-row merge back, which could not drop the keys the forward pass baked |
| adds endpoints / operations / policies / registry nodes | run the repo's **own** codegen/drift gate (`generate:check`, `generate-all` + `git status`) and read its real verdict. Composition drift exists only once the slices are assembled, so no per-slice gate sees it | if the gate asserts something you can verify is false in the source, **suspect its inputs before editing the source** — it resolved through `paths` and loaded a stale compiled `.js` sitting beside the `.ts` |
| **corrects a claim** or removes a duplication | sweep the **belief in synonyms**, not the literal string, and **re-sweep every file this PR itself edited** | a literal `git log -S` found 4 sites; synonyms found 2 more and the whole-PR pass found a seventh **72 lines below a line the PR had just fixed** — shipping a self-contradicting file is worse than fixing neither |
| merges another branch in | enumerate what the **other side added** (`git diff --diff-filter=A --name-only <base>...<theirs>`), intersect with what **this** side modified, and read the assertions of every added test/fixture on that intersection | new files conflict with nothing, so they appear in no conflict list — an added PCI oracle merged green against a prop API this branch had replaced, still committed, still collecting, testing nothing |
| a later slice **removes a protection** an earlier slice made unnecessary | state the two sets — what the earlier slice actually covers, what the removal is applied to — and the difference. Non-empty difference *is* the finding | one slice made *one* watched file degrade safely; the next stopped holding **all three**, and the third was still client-fatal |
| asserts **why** a guarantee holds by naming a framework mechanism | verify the claim against framework source-of-truth **before it reaches the PR body**; correct it in place | an oracle and comment credited a deep merge; the guarantee actually came from an outbox `concurrency:1` and was topology-dependent. Behaviour green, stated reason wrong |
| carries **skipped / `xfail` / tracer** blocks citing a blocker | re-validate each rationale against `HEAD` — a later slice may have fixed the cited blocker, leaving the path uncovered and the comment lying | a tracer bypassed a "P0" that a later commit on the same branch had already fixed |
| — (always) **cross-slice composition** | enumerate the invariants / cursors / floors more than one slice touches; reason about each **pairwise** interaction, especially where one slice *advances* what another *reads* or *trims* against. Run the full suite over the whole diff | a by-position refill and a stream trim were each correct and composed into a silent-drop window |
| — (always) **`Bin` in the diff-stat** on a hand-authored source path | treat as a hard finding, not noise. `git diff --numstat` emits `-\t-\t<path>`; locate with `grep -aPn '[\x00-\x08\x0e-\x1f]'` | a NUL sentinel in a `.ts` string literal compiled, passed 8/8 integration tests, and made the whole file's diff unreviewable on a diff-is-the-deliverable ticket. Earlier tell: **`grep` returning nothing on a file you just edited** is a binary-classification symptom, not an answer — run `file` |

### The full-suite verdict is a baseline diff, not an exit code

The sweeps assume you can trust the word "green." Four ways the read is wrong, in ascending subtlety:

- **A pass/fail read from a *piped* exit code is a lie.** `yarn test | tail -30` reports `tail`'s status; a 33-suite-red run surfaces as exit `0`. Read jest's own summary (`| grep -E '^(Tests|Test Suites):|^FAIL'`) or preserve the status (`set -o pipefail`, `${PIPESTATUS[0]}`). Same for a **background job**: capture the tool's exit into the log — a trailing `echo` makes the completion notification report the wrapper's exit, not the gate's.
- **A run that executed nothing reports green.** `Tests: 0 total`, an all-skipped env-gated tier, or a suite that died at collection all exit 0 — and an env-gated tier prints `PASS` while never running. **Inconclusive, never green and never a baseline** (§1). Where the plan names a tier excluded from the default run, either **run it** or state in the PR body that it was not run and why; a slice's `passes:` flag records the default run, which skipped it.
- **A green *partial* inventory reads as full coverage.** Harder to notice than zero, because the run looks substantial. `find` the repo's test files by its naming convention and compare against the runner's reported file count; a material gap means the `include` config is wrong or tiers are opt-in — resolve which files were skipped and run them explicitly. (A root glob that predated a monorepo move silently excluded 33 of 57 suites; every prior "green" on that branch was vacuous for them.)
- **"All green" is the wrong bar when the base is already red.** The sound verdict is a **baseline diff**: against the true base resolved above, capture the failing-suite *set* on base and on `HEAD` and diff the **names**. `PASS→FAIL` is a regression; already-red-on-base is pre-existing — name it and move on; test-*count* jitter inside an already-red suite is noise. Compare **by file, not by total** — totals hide an equal-and-opposite swap. If the base run reports 0 tests the baseline is unusable and must be repaired before the PR body says anything about flips. When HEAD is *fully* green with a parsed summary, the base-side run is unnecessary — zero flips are possible — so skip the worktree+install; only a red HEAD needs the base set.

Apply the `critique` skill's tone throughout: substance over compliments, no hedging, every finding specific and actionable with a concrete fix. For an assembled feature that crosses a non-trivial architectural seam, run a focused `critique --lens arch,ops` pass over the diff and fold its verdict into the findings below.

**The sweeps parallelize well** as independent read-only subagents — they are grep-shaped and disjoint, and the wall-clock is the slowest one. Your job then is **adjudication, not re-running them**: when two reports disagree about a checkable fact, *neither* is evidence — read the primary source and record which report was wrong. A **clean verdict is a claim too** (§3), and it is the seductive one, because it asks for no work and reads as resolution. (A "this is already fixed, lines 35-60 type-prefix every import" verdict had read the first half of the import block; the blocker was live, and trusting it would have dropped the fix and the gate wiring built on it.)

**Disprove every Critical/High before propagating it.** A plausible-sounding Critical that's actually a false positive is *more* expensive than a missed nit — "fixing" it introduces a regression. Before reporting or acting on any Critical/High finding, attempt to **disprove** it: (a) read the actual call site — not the diff hunk in isolation; (b) run a `git blame` / base-branch check — "is this pre-existing on the base, not introduced by this PR? Y/N"; (c) construct a concrete failing input that reproduces it. Drop or downgrade any Critical that can't survive all three. (Real miss: 3 of 4 reported Criticals on TV1-1950 were false positives — a truthy `'0'` misread as falsy, a verbatim-from-`master` pre-existing line, and a "double increment" that was load-bearing for restart determinism — each would have introduced a bug if "fixed"; the git-blame check alone kills two of them.)

Surface findings by severity (Critical / Medium / Low). Fix Critical/Medium before opening the PR (small fixes inline or a follow-up slice). For anything left open, state your recommendation and why it can ship unresolved. This review is **not** committed to a file — its conclusions go into the PR body (Step 5).

## Step 3 — Dev verification checklist

Produce a single **developer verification checklist**: the things a human should manually confirm that the automated slice tests do **not** cover — UI/UX, a browser smoke for a user journey, anything environment-specific. One lean list. (No separate QA plan.) This goes in the PR body, not a committed file.

## Step 4 — Finalize the durable record

- **ADR(s):** ensure the decisions from `.work/design.md` that aren't recoverable from code are captured as committed ADR(s) in the repo's ADR location. Commit them if not already.
  - **Never take the next number from a directory listing** — it shows only numbers that reached *your* branch, and numbers on unmerged siblings, open PRs and other stacks are already claimed. Scan every ref: `git log --all --name-only --pretty=format: | grep -oE 'ADR-[0-9]+' | sort -u | tail -5`, then go above it. This is the last point where a collision is still cheap: a rename after merge breaks every inbound `ADR-0NN` citation permanently.
  - **Check uniqueness against the merge target, not the branch.** The failure shape is a *filename* difference with a *number* collision, which no git mechanism surfaces — different names never conflict, so both land.
  - **Re-resolve every path and symbol the ADR cites** before committing it. A wrong `file:line` in an ADR outlives the PR and misleads whoever reads it next (§3) — one shipped citing a path that did not exist as written, an abbreviation having dropped a directory.
  - If a composition finding traces to text the design or an existing ADR *also* asserts, **amending that text is part of the fix**, not a follow-up — otherwise the next reader re-derives the bug from the record.
- **Promote the design:** the design narrative + conclusions from `.work/design.md` become the **PR description** — they are *not* committed as a standalone doc.
- **If the PR adds an enforcement mechanism** (a CI gate, lint rule, schema check, hook), state **which commit is its first live proof** — or, if none is, say why. A gate that never fired is indistinguishable from a gate that cannot fire.

## Step 5 — Open the PR (the system of record)

Push the branch and open the PR **ready for review, not a draft** (compose the repo's `create-pr` flow if it has one, overriding any draft default it carries; otherwise `gh pr create --base <resolved-base>`, which opens a review-ready PR — do **not** pass `--draft`, and pass the base resolved in Step 2, not a hardcoded `master`). **Verify the created PR's base after the fact:** `gh pr create` succeeds silently even when it targets the wrong ref, so confirm the PR's `changed_files`/`commits` roughly match the local `git log <base>..HEAD` count/diffstat. If they don't, retarget with `gh pr edit --base <true-base>`.

**"PR opened" is not "done" — report its mergeability.** Re-fetch and compare `origin/<default>` against the base you branched from: a merge by anyone outside this work invalidates the pin, and the cost lands at the worst moment, with gates green and the PR declared ready. Read `gh pr view --json mergeable,mergeStateStatus` after a short settle (GitHub returns `UNKNOWN` for a few seconds after a push) and say so. The remedy for a conflict is rebasing **this branch, in its own worktree** — safe, and not to be confused with the real prohibitions (never modify the default branch or another unit's branch; never rewrite history something is stacked on).

**For a stacked child:** GitHub auto-retargets a child only when the parent's branch is **deleted**. Where `delete_branch_on_merge` is false (`gh api repos/{owner}/{repo} --jq .delete_branch_on_merge`), the child keeps pointing at a merged branch — merging it there returns exit 0, shows MERGED, and delivers nothing to the default branch. Retarget explicitly (`gh pr edit <n> --base <default>`), and verify **after every merge** with `git merge-base --is-ancestor origin/<head> origin/<default>`; that is the only check that catches a wrong-target merge, because the wrong-target merge itself reports success.

The PR **body is the record**:

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
- This pass is cross-slice; trust the per-slice gates for within-slice correctness — but not for anything that ripples *outside* a slice's oracle. That is this pass's job.
- **"Tests pass" is not evidence for a path that has no test.** A green gate covers the path it ran, nothing more. Every sweep above is a way that path is narrower than it looks; name the untested path rather than inferring coverage from green. The four facts this pass rests on are in [EVIDENCE.md](../EVIDENCE.md) — read it if a sweep's *why* is unclear.
- **Disprove in both directions** — disprove a *finding* before you report it (a false Critical is costlier than a missed nit), and disprove the *claims the code makes about itself* before they propagate into the PR body. A **clean** verdict is the third kind of claim, and the easiest to accept.
- **Where the work carries a safety-direction invariant** ("may only ever widen", "must never lose X"), brief the sweeps with *invariant-shaped* questions — "does any clause default to DROP?" — not a generic "review this diff". Both defects in one such change looked locally correct and were invisible from the output by construction; a generic review would have missed them, and its own zero-delta measurement did.
- Tone follows the `critique` skill: substance over compliments, specific and actionable findings.

