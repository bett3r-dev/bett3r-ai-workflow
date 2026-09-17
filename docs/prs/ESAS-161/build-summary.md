---
work_item: ESAS-161
plugin: bett3r-ai-workflow@0.81.0+011aa28
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
    usage:
      executor: { model: "claude-opus-5", effort: "low", tokens: 2104786, activeMs: 863336 }
      verifier: { model: "claude-opus-5", effort: "low", tokens: 708319, activeMs: 424569 }
      testRunner: { model: "claude-haiku-4-5-20251001", effort: null, tokens: 163945, activeMs: 58220 }
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
    usage:
      executor: { model: "claude-opus-5", effort: "low", tokens: 738380, activeMs: 183986 }
      verifier: { model: "claude-opus-5", effort: "low", tokens: 100912, activeMs: 49836 }
      testRunner: { model: "claude-haiku-4-5-20251001", effort: null, tokens: 101417, activeMs: 28158 }
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
    usage:
      executor: { model: "claude-sonnet-5", effort: "low", tokens: 1920971, activeMs: 380442 }
      verifier: { model: "claude-opus-5", effort: "low", tokens: 428519, activeMs: 229752 }
      testRunner: { model: "claude-haiku-4-5-20251001", effort: null, tokens: 176734, activeMs: 57178 }
  - id: 4
    name: "Measure the artifact comment wake"
    origin: plan
    mode: sequential
    modeReason: pool=0
    commit: 011aa28
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D15]
    usage:
      executor: { model: "claude-opus-5", effort: "low", tokens: 186866, activeMs: 103725 }
      verifier: { model: "claude-opus-5", effort: "low", tokens: 57798, activeMs: 29583 }
      testRunner: { model: "claude-haiku-4-5-20251001", effort: null, tokens: 97153, activeMs: 28592 }
verifyBuild:
  usage: { model: "claude-opus-5", effort: "low", tokens: 1250955, activeMs: 211680 }
  gate: { mode: full-fallback, verdict: PASS, skipped: [], inconclusive: [] }
  coherence: { critical: 0, medium: 1, low: 2, shippedUnresolved: 2 }
  fixSlicesAdded: 0
  adrs: []
  concerns: { hard: 2, soft: 0, unmet: [] }
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

Slice 4 (measurement, run with the owner, 2026-09-17 UTC): a page published with {db:{}} and a connected,
armed watch received every answer, but no notification reached the session and the artifact had no
comment threads — the page's comment box writes to the answers store, never to a thread. Readback on the
owner's terminal word worked: read_db with out_dir landed D10's layout directly, and apply-answers without
--final gave open=0 owner=10 recommendation=0 moot=1. The skill now asks for the hand-back in the terminal;
a comment-mode thread wake is recorded as UNMEASURED (D15). No out-of-default suites are affected.
Open follow-ups: D9 (moot-fork invalid pick refuses; map mode narrowed to 0600), D14 (no fork dependency
field in the schema), D15 (measure the comment-mode thread path; design F4's risk amended at /verify-build).
