# ESAS-186 — post-design decisions

## D1 — Only a missing bump is deferred; an unreadable manifest still refuses in a lane
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [code:status/unreadable (scripts/check-plugin-version-bump.sh), design:D2]
rejected: defer any non-zero status — a broken plugin.json is not fixed by /merge-multi's bump, so "deferred" would be a false claim
supersedes: —
The script used one `status` flag for both a missing bump and a versionless manifest. D2 names only the missing bump; the deferral now requires no unreadable manifest in the run, pinned by oracle case (e) and a mutation.

## D2 — The deferral lives in the version script, not only in the host gate
kind: deviation
step: build · slice: 1 · decidedBy: orchestrator
sources: [design:A1, code:scripts/test-version-gate.sh]
rejected: lane-awareness only inside .claude/gate.sh — untestable by the existing throwaway-repo oracle
supersedes: —
CI is unaffected because `.work/` is gitignored and never exists in a checkout. On deferral the SKIP line replaces the "bump and push again" paragraph; the ✗ lines still name each unbumped plugin.

## D3 — The dual gate ran without a separate scope-check agent
kind: waiver
step: build · slice: — · decidedBy: orchestrator
sources: [human]
rejected: —
supersedes: —
Unattended run; scope was checked by the orchestrator with git status and by the verifier's scope guard, since every slice touches 2–4 files.

## D4 — The drift test fails closed on a `run:` form it cannot parse
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [code:unparsed (scripts/test-gate-drift.sh), design:D1]
rejected: accept the textual extractor as-is — a new `run: |-` or `run: >` step would be silently unchecked, the exact failure the test exists to stop
supersedes: —
Pinned by a specimen case and a mutation (guard disabled → red).

## D5 — INCONCLUSIVE steps do not fail the host gate
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [code:.claude/gate.sh, plugins/bett3r-ai-workflow/skills/full-gate/SKILL.md]
rejected: fail on a missing `dash` — would make the gate unrunnable where dash is absent; the contract reserves non-zero for FAIL and requires INCONCLUSIVE be named
supersedes: —
Also: the CI-only PyYAML installer line is not run locally and is excluded from the drift test by name; `${{ github.base_ref || 'master' }}` maps to `${GATE_BASE}` (default origin/master).

## D6 — Slice 3 (prose + manifest) verified by the orchestrator, not a verifier agent
kind: waiver
step: build · slice: 3 · decidedBy: orchestrator
sources: [code:commands/verify-build.md, code:commands/merge-multi.md]
rejected: opus verifier for two paragraphs and a version string — cost without a judgment surface; /verify-build's whole-PR review covers it
supersedes: —
Evidence: version script FAIL (0.81.0 = 0.81.0) on a synthetic prose-only commit, PASS 0.81.0 → 0.82.0 after the bump; needles/links/validate green. marketplace.json metadata 0.35.0 → 0.36.0 per the last three releases.

## D7 — The slice-3 verifier waiver let a pinned-prose ripple reach the gate; fixed on the branch
kind: overruled
step: verify-build · slice: 3 · decidedBy: orchestrator
sources: [code:scripts/test-merge-multi-concerns.sh (closed-set pin), gate:merge-multi-concerns FAIL]
rejected: revert the merge-multi paragraph — D4 requires it
supersedes: D6
The first `--full` run failed `merge-multi-concerns` (1 failed, 86 passed): that oracle pins merge-multi.md as a closed set of sentences, and slice 3's paragraph was EXTRA. The two sentences are now pinned deliberately (87 passed under sh/dash/bash). D6's claim that the whole-PR review would cover slice 3 held only because the gate ran; a prose slice in a pinned file is not verifier-free.

## D8 — ADR-001 amended rather than a new ADR
kind: deviation
step: verify-build · slice: — · decidedBy: orchestrator
sources: [adr:ADR-001]
rejected: new ADR — the deferral is a scoped exception to ADR-001's release contract, not a separate decision
supersedes: —
