---
work_item: ESAS-161
plugin: bett3r-ai-workflow@0.81.0+c377653
base: 464e4c6
slices:
  - id: 1
    name: "A render with a mismatched fork count stops the step (tracer bullet)"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 71a5284
    passed: true
    attempts: 3
    fixRounds:
      - { cause: oracle-wrong, executor: continued }
      - { cause: oracle-wrong, executor: continued }
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D1, D2, D3, D4, D5, D6]
  - id: 2
    name: "Saved answers become fork statuses"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: c076c23
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D7, D8, D9, D10]
  - id: 3
    name: "The design-map skill v0 and its artifact-comment wake disarm"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 86c8791
    passed: true
    attempts: 2
    fixRounds:
      - { cause: design-silent, executor: fresh }
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D11, D12, D13, D14]
  - id: 4
    name: "Measure the artifact comment wake"
    origin: plan
    mode: null
    modeReason: null
    commit: null
    passed: false
    attempts: 0
    fixRounds: []
    verifier: null
    redBeforeGreen: null
    postDesignDecisions: []
---
## What shipped

Slices 1–3 landed sequentially in the main tree (pool width 1, no brief, no `designs:` so no scaffold).
`design-map render --expect` refuses a fork-count mismatch on both the payload and the drawn page,
`apply-answers [--final]` folds the answers store into fork statuses, and the `design-map` skill
documents the loop with the rule that an artifact-comment wake never runs `--final` (D11).
Oracle: `scripts/test-design-map.sh`, 143/143 under sh, dash and bash; all validate-plugins.yml steps
were run locally on slice 1's final tree (CI is disabled) and the touched ones on slices 2–3.

Fix rounds: 3 — oracle-wrong 2 (slice 1: the page-count refusal and the page marker were unpinned by
the oracle), design-silent 1 (slice 3: a page comment could be read as consent to --final); 2 continued,
1 fresh (sonnet → opus). Slice 1 also fixed a data-loss path found by the verifier: a refusal deleted
whatever sat at --out, including the map (D3).

Slice 4 did not run: it is a manual measurement that needs the owner to comment on a published page so
a real session's wake and banner text can be observed. ESCALATED to a human. No out-of-default suites
are affected (no TypeScript, no integration tests). Open follow-ups: D9 (moot-fork invalid pick
refuses; map mode narrowed to 0600), D14 (no fork dependency field in the schema).
