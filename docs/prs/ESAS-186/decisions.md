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
