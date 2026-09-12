---
work_item: XL-27
plugin: bett3r-ai-workflow@0.67.0+242c321
base: 242c321
slices:
  - id: 1
    name: "TRACER BULLET — independent slices build in parallel in a reusable worktree pool and land on the task branch in dependency order"
    origin: plan
    mode: sequential
    commit: 14d9083
    passed: true
    attempts: 3
    retries: [design-silent, design-silent]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D2, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15, D16]
  - id: 2
    name: "The design is committed beside the code, at the work-docs root"
    origin: plan
    mode: sequential
    commit: 57c5ba6
    passed: true
    attempts: 6
    retries: [design-silent, oracle-wrong, "human-authorised: ownership header (D29)", "human-authorised: dated work item (D36)", ripple]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D3, D17, D18, D19, D20, D21, D22, D23, D24, D25, D26, D27, D28, D29, D30, D31, D32, D33, D34, D35, D36, D37, D38, D39, D40, D41]
  - id: 3
    name: "/build leaves a committed record — decisions.md and the slices block of build-summary.md"
    origin: plan
    mode: sequential
    commit: 6f16140
    passed: true
    attempts: 5
    retries: [design-silent, invariant, "human-authorised: stale verbatim entry (D53)", "human-authorised: foreign-sha lookup (D54)"]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D42, D43, D44, D45, D46, D47, D48, D49, D50, D51, D52, D53, D54, D55, D56, D57, D58, D59, D60]
  - id: 4
    name: "The run is measured before the PR opens, and the numbers land in build-summary.md"
    origin: plan
    mode: sequential
    commit: 2442e38
    passed: true
    attempts: 2
    retries: [design-silent]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D71, D72, D73, D74, D75, D76, D77, D78]
  - id: 5
    name: "An owner's bar is captured as a concern and checked, failing closed"
    origin: plan
    mode: sequential
    commit: dd5031c
    passed: true
    attempts: 3
    retries: [invariant, invariant]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D61, D62, D63, D64, D65, D66, D67, D68, D69, D70]
  - id: 6
    name: "/verify-build rules every concern, opens the PR either way, and posts flow/concerns"
    origin: plan
    mode: sequential
    commit: d3aa21c
    passed: true
    attempts: 2
    retries: [design-silent]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D79, D80, D81, D82, D83, D84, D85, D86, D87]
  - id: 7
    name: "/merge-multi refuses a unit whose concerns fail, and writes the run-level decisions.md"
    origin: plan
    mode: sequential
    commit: f69025c
    passed: true
    attempts: 6
    retries: [oracle-wrong, oracle-wrong, "human-authorised: Step 1b closed set (D94)", "human-authorised: whole-file pin (D94)", "human-authorised: section-keyed pin (D94)"]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D88, D89, D90, D91, D92, D93, D94, D95, D96, D97]
  - id: 8
    name: "The reversed rule is recorded — ADR-005 and the rewritten principles"
    origin: plan
    mode: sequential
    commit: 67e8a5d
    passed: true
    attempts: 1
    retries: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D98, D99]
---
## What shipped

All eight planned slices landed on `xl-27/committed-work-record`, each as one slice commit followed
by a `docs(record)` commit. Every slice passed the dual gate (test run, scope check, Opus verifier);
only slice 8 was green on its first pass. Plan-level decisions D1 and D4 belong to no slice.

The build ran on the cached 0.67.0 commands, which predate this unit, while building 0.68.0. That
old `/build` says to write no build-summary.md; this file follows the format slice 3 shipped, and
its slices were run sequentially in the main tree — the worktree pool slice 1 added was not used.
The `usage` and `verifyBuild` blocks are left for `/verify-build` to generate.

Retries clustered on seams the design left unspecified (`design-silent`, 6) and on tests that pinned
wording instead of behaviour (`oracle-wrong`, 3). Slices 2, 3 and 7 also needed human decisions
after retries were exhausted — ownership of a design folder, stale and foreign build-summary entries,
fleet run ids, and how far to pin `merge-multi.md`. Slice 5's first pass ran on sonnet and was
re-dispatched on opus after its first retry; slice 7's first pass also ran on sonnet.

Known limits carried to the record: R7 is only partly verified — pool workers stamped `gitBranch:
HEAD` are counted, not attributed (D71). `decisions.md` and `build-summary.md` have no reader in this
plugin yet (ADR-005). The owner's concerns C1–C3 are recorded unruled; `/verify-build` rules them as
`concerns-check`'s first live run.
