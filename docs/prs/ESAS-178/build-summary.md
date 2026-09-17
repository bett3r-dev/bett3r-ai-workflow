---
work_item: ESAS-178
plugin: bett3r-ai-workflow@0.81.0+6e36a07
base: 9c835c080093143c1c9a734f88f06dbd25bfc99e
slices:
  - id: 1
    name: "Epic oracle driver committed RED (P10)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 51df694
    passed: true
    attempts: 3
    fixRounds: [{cause: oracle-wrong, executor: fresh}, {cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D1, D2, D3, D4]
  - id: 2
    name: "TRACER BULLET — v2 map validates against the esas vocabulary copy (validate verb, grounding, render over v2)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: d0c515b
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D5, D6, D7, D8]
  - id: 3
    name: "Answers and authoring over v2 — apply-answers D5 and the write verb"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 02887bc
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D9]
  - id: 4
    name: "Plan readers — candidates and check-plan (ESAS-165 contract)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 4b69032
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D10, D11]
  - id: 5
    name: "Fleet readers — render --stack, project --ticket, decisions (ESAS-166 contract)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 71393cc
    passed: true
    attempts: 2
    fixRounds: [{cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D12, D13]
---
## What shipped
All 5 slices landed sequentially (pool=0: a strict chain over one script). design-map now speaks v2 only: the esas vocabulary is a byte copy, structure lives in map-structure.schema.json, and the verbs are validate, write, render [--stack], check-page, apply-answers [--final], candidates, check-plan, project, decisions. test-design-map.sh: 529 passed under sh/dash/bash with a loud SKIP for the staleness case, 531 with ESAS_CHECKOUT. The epic oracle driver was committed first and RED; at the tip, stages 1, 2, 3 and 5 are ok, 4 (map-tree, ESAS-163), 6 (esas vitest, no node_modules in the int checkout) and 7 (select/post + captures, ESAS-174) are error.

Fix rounds: 4, all fresh (this lane cannot continue a child): oracle-wrong ×3, design-silent ×1. Executors on sonnet for slices 1 and 4 each needed a round; both rounds were moved to opus.

Carried: esas writes structureVersion 1 and refuses others (D6, escalation E1). No plugin.json bump (orchestrator directive), so check-plugin-version-bump.sh fails by design. The executors saw no un-run suites outside test-design-map.sh; the driver is deliberately in no suite.
