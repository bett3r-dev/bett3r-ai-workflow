---
work_item: ESAS-163
plugin: bett3r-ai-workflow@0.81.0+f3a4a80
base: d3959137d69fc0190c793f2a8d4c63c2bb460b55
slices:
  - id: 1
    name: "Tracer: a design.md generated region is rendered, written and checked (md dialect, stale vs tampered, displace)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: b0575ce
    passed: true
    attempts: 2
    fixRounds: [{cause: invariant, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    usage: null
    postDesignDecisions: [D1, D2, D3]
  - id: 2
    name: "Jira dialect: a ticket-block region is pre-compressed, ADF-safe, per-ticket, and never displaced"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: c616ce2
    passed: true
    attempts: 3
    fixRounds: [{cause: design-silent, executor: fresh}, {cause: oracle-wrong, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    usage: null
    postDesignDecisions: [D4, D5]
  - id: 3
    name: "Wiring: the file's author regenerates the region; tracker-writer refuses a non-fresh source; ADR-007 and glossary"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: ac1951f
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    usage: null
    postDesignDecisions: [D6, D7, D8, D9, D10]
verifyBuild:
  usage: null
  gate: { mode: "fleet mirror (plugin-gate.sh, no --fast) + map-tree suite by hand", verdict: FAIL-expected, skipped: [], inconclusive: [], failed: [version-bump (deliberate, no plugin.json bump by directive), plan-candidates (suite exists only on sibling ESAS-165 branch; not on this base)] }
  coherence: { critical: 0, medium: 0, low: 2, shippedUnresolved: 2 }
  fixSlicesAdded: 0
  adrs: [ADR-007]
  concerns: { hard: 0, soft: 0, unmet: [] }
---
## What shipped
3/3 slices, all on opus, 4 fix rounds (invariant 1, design-silent 2, oracle-wrong 1), all fresh dispatches (a unit lane cannot continue a child). `map-tree` (render/write/check, md + jira dialects) with `scripts/test-map-tree.sh` (188 checks, sh/dash/bash), wired into /design Step 4, /verify-build refresh, /design-multi fold-back and tracker-writer; ADR-007. The verifier's falsification passes found every real defect (card-less moot, newline crash, backtick pairing, heading exact-match) — none was caught by the executor's own suite. This design.md now carries its own generated region (dogfooded). No design layer / scaffolder: step 0 skipped (no designs:). plugin.json not bumped by directive (AC8 fails deliberately). Epic oracle scripts/oracles/epic-esas-156.sh expects map-tree:begin/end markers — routed (D10).
Usage not measured: no-transcripts (run-metrics finds no transcripts for a /start-multi lane branch outside the orchestrator session).
