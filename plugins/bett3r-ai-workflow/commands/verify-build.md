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

Diff the full branch against its base (`git diff <base>...HEAD`). Read `${CLAUDE_PROJECT_DIR}/.claude/rules` for the repo's architectural checklist. Review the **assembled** change — the things no single-slice verifier could see:

- **Cross-slice invariants** — does the feature hold as a whole; do the slices compose correctly; any contract that two slices had to agree on?
- **Coherence** — consistent patterns across slices, no duplication introduced between them, no slice undone by a later one.
- **Design fidelity** — does the assembled result deliver what `.work/design.md` resolved? Note any deliberate deviation.
- **Quality** — real bugs, unsafe casts, security, dead code introduced across the diff. Look for accidental complexity, technical debt or anti-patterns relentlessly and be critical.

Surface findings by severity (Critical / Medium / Low). Fix Critical/Medium before opening the PR (small fixes inline or a follow-up slice). Offer you recommendation for open issues. This review is **not** committed to a file — its conclusions go into the PR body.

## Step 3 — Dev verification checklist

Produce a single **developer verification checklist**: the things a human should manually confirm that the automated slice tests do **not** cover — UI/UX, a browser smoke for a user journey, anything environment-specific. One lean list. (No separate QA plan.) This goes in the PR body, not a committed file.

## Step 4 — Finalize the durable record

- **ADR(s):** ensure the decisions from `.work/design.md` that aren't recoverable from code are captured as committed ADR(s) in the repo's ADR location. Commit them if not already.
- **Promote the design:** the design narrative + conclusions from `.work/design.md` become the **PR description** — they are *not* committed as a standalone doc.

## Step 5 — Open the PR (the system of record)

Push the branch and open the PR (compose the repo's `create-pr` flow if it has one; otherwise `gh pr create`). The PR **body is the record**:

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
- Follow the host repo's critique conventions for tone: substance over compliments, specific and actionable findings.

