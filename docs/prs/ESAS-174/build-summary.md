---
work_item: ESAS-174
plugin: bett3r-ai-workflow@0.81.0+6e45ef6
base: fd52c0fb17ff1b2eb3a470edffeb87844f66d2d8
slices:
  - id: S1
    name: "select: the map target is chosen by a first-match table, probes before start"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: ddec45c
    passed: true
    attempts: 2
    fixRounds: [{cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D2, D3]
  - id: S2
    name: "post parity and D5 readback: the board's store readback matches map.json"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: 65819df
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D4]
  - id: S3
    name: "epic oracle goes green: real esas captures for stage 7, stage 4 reads the shipped map-tree markers"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 4c01a68
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D5, D6]
  - id: S4
    name: "the design-map skill tells an agent how to select, stay silent, survive board death and pin the target; ADR-009"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 31be0be
    passed: true
    attempts: 2
    fixRounds: [{cause: mis-routed, executor: fresh}]
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D7]
---
## What shipped

4/4 slices landed. `design-map select` (first-match table over a captures dir, probes before start) and `design-map post` (store-readback parity, `statuses=`) are in design-map.py with 931-check suite green (1 SKIP no-esas-checkout, pre-existing). The epic oracle `ESAS_CHECKOUT=<esas int156 oracle twin @de920db> sh scripts/oracles/epic-esas-156.sh` exits 0 with all 7 stages ok on the landed tree (sh and dash), after correcting stage 4 to map-tree's shipped contract and generating real esas captures for stage 7. E1 (structureVersion 1 vs 2) did not fire. plugin.json deliberately not bumped (D1).

Fix rounds: 2 (oracle-wrong 1, mis-routed 1), both fresh dispatches. Follow-ups: the no-pwd.txt fallback tests do not bite on logical vs physical separately (D3); S3's `commit-not-three-files` can no longer fire (D5).
