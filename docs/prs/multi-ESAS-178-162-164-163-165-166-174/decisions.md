# multi-ESAS-178-162-164-163-165-166-174 — merge decisions

## D1 — validate-plugins.yml diamond conflict: keep both step blocks
kind: silent-seam
step: merge-multi · slice: — · decidedBy: orchestrator
sources: [code:validate-plugins job (.github/workflows/validate-plugins.yml), human]
rejected: ours/theirs — each side drops one unit's test step (map-tree from ESAS-163 or plan-candidates from ESAS-165)
supersedes: —

ESAS-163 and ESAS-165 each appended a step after test-design-snapshot. Resolved by taking the
file as already resolved on ESAS-166-base@4fbf33f (keep both, map-tree then plan-candidates),
the exact resolution ESAS-166 and ESAS-174 were built and gated on. The assembled tree is
byte-identical to ESAS-174's tip bef68b0 before the version bump.

## D2 — one plugin version bump on integration (0.81.0 -> 0.82.0)
kind: deviation
step: merge-multi · slice: — · decidedBy: orchestrator
sources: [code:check-plugin-version-bump.sh (scripts/), adr:ADR-001, human]
rejected: a bump per unit — seven bumps collide at every merge; units deliberately deferred it
supersedes: —

marketplace.json's own version (0.35.0) tracks the marketplace, not the plugin, and is untouched.
