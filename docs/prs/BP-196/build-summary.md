---
work_item: BP-196
plugin: bett3r-ai-workflow@0.110.0+8d356be
base: ce15b0923
slices:
  - id: 1
    name: TRACER BULLET - bin/skill-path resolves <plugin>:<skill> through installed_plugins.json, wired as a gate step
    origin: plan
    mode: sequential
    modeReason: pool-skipped (markdown/shell repo, no install; tracer first)
    commit: c55e6b65c319c861f45db771530239dae4b910dc
    passed: true
    attempts: 3
    fixRounds: [{cause: design-silent, executor: fresh}, {cause: ripple, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D1, D2, D3]
  - id: 2
    name: Relay - /build and /verify-build hand every executor and verifier the declared framework skill by file; workers route from the bridge
    origin: plan
    mode: sequential
    modeReason: pool-skipped (markdown/shell repo, no install)
    commit: f2cb111251fe9a39f12a75ec53dc5ffd65b4d837
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D4, D5]
  - id: 3
    name: Refuse before start - /build Step 1 and /start-multi step 0 stop when the declared framework skill is not installed; ADR-016 records it
    origin: plan
    mode: sequential
    modeReason: pool-skipped (markdown/shell repo, no install)
    commit: 8d356be7a930c9665646fd90fcf86726241840f7
    passed: true
    attempts: 2
    fixRounds: [{cause: design-silent, executor: fresh}]
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D6, D7]
  - id: 4
    name: PV3 create-* skills open with 'Starting from a scaffold' (keep the identity, work the markers)
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
Slices 1-3 landed. Slice 4 was not started: the slice budget (3) was reached, so the run yielded; re-dispatch /build to resume from passes: true. Slice 1 needed two fix rounds (worktree-aware project-scope root, local/managed scopes, malformed manifests, test leaking GIT_DIR). The pool was not used (sequential, tracer first; pure markdown/shell repo). Gate: scoped (sh .claude/gate.sh) PASS each slice; its blind spot is the rest of the repo, and flow-seams does not trigger on plugins/bett3r-pv3-ai-skills (slice 4 must run it explicitly). Owner items: D3 (project-over-user precedence vs Claude Code), D4 (four unrelayed dispatch sites), D7 (resume without BASE). No plugin.json bump (F19); intended bump past 0.110.0 belongs in the PR body.
