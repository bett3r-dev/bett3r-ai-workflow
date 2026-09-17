---
work_item: ESAS-166
plugin: bett3r-ai-workflow@0.81.0+73717f7
base: 4fbf33f666ce663e06f875fa0619c9cb8bffc700
slices:
  - id: 1
    name: "A provisioned map-only folder is this work item's to design (owner=none)"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: 183eb27
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D1, D2]
  - id: 2
    name: "Provenance decides map reuse: the provisioner carries the projection or reports it lost"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 9cd285a
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D3, D4, D5]
  - id: 3
    name: "Subjects: epic-link grouping with a replayable fingerprint"
    origin: plan
    mode: worktree
    modeReason: null
    commit: dd6e41e
    passed: true
    attempts: 2
    fixRounds: [{cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D6, D7, D8]
  - id: 4
    name: "Fleet maps fixtures: 10 fragments stack into 7 maps, one answer path closes"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 178e39b
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D9]
  - id: 5
    name: "/design-multi answers on subject maps; the lane emits a fragment"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 4a3cb60
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D10, D11, D12, D13]
  - id: 6
    name: "ADR-006 records subject maps, stacking, projection and D+ provenance"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: 6e89298
    passed: true
    attempts: 2
    fixRounds: [{cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D14]
---
## What shipped

All 6 slices landed. Slices 2, 3 and 4 ran together in a 3-worktree pool; slice 5 ran in a pool worktree after 2 and 3 landed; slices 1 and 6 ran alone in the main tree. There was no install or build step (the repo is sh/python), so pool resets ran with none, and no provisioner agent was dispatched.

There were 5 fix rounds: 3 design-silent (prose that contradicted adjacent rules, and a subject-map composition the block left unstated) and 2 oracle-wrong (a fingerprint input that was hashed but never tested, and an ADR rule stated backwards that presence rows cannot catch). Every fix round used a fresh executor, since the lane cannot continue its children.

Carry-forward for /verify-build: a new suite, scripts/test-design-multi-subjects.sh, is wired into .github/workflows/validate-plugins.yml, but the orchestrator's scratchpad gate mirror does not run it. Run it by hand. plugin.json is deliberately not bumped. The `design-map select` verb does not exist at this base (ESAS-174).
