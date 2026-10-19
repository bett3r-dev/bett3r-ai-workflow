---
work_item: BP-196
branch: BP-196-executor-skill-path
---
# BP-196 — /build executor cannot reach a framework plugin skill

Mode: unattended lane, verification second pass over a `design-multi:resolved:v2` block (base ce15b09, drift movement none / shape none). Grounding degraded: no CONTEXT.md in this plugin repo; module headers of the cited agents and commands were read instead.

## Problem
- The executor holds Read, Write, Edit, Glob, Grep, Bash (plugins/bett3r-ai-workflow/agents/executor.md:4-10), yet rule 3 (:21) says "follow the matching skill the host repo's framework plugin surfaces (create-aggregate and kin)". Nothing passes it a skill or a path: the dispatch is build.md Step 3 item 1 (plugins/bett3r-ai-workflow/commands/build.md:51), not "Step 1" as the ticket says; since ESAS-304 it carries the scaffold report, no skill guidance.
- Worse than stated: in a fleet, /build runs in step-lane-file, which has no Skill tool (plugins/bett3r-ai-workflow/agents/step-lane-file.md:17), so build.md:49's "which this session cannot load" always fires and even the orchestrator never reads the bridge.
- Missed by the ticket: the verifier (plugins/bett3r-ai-workflow/agents/verifier.md:4-8, :18) promises the framework's Final Checklist with no Skill tool; /verify-build's in-lane fix dispatches the executor too (plugins/bett3r-ai-workflow/commands/verify-build.md:87).
- All three hosts declare a bridge: blueprint .blueprint.config.json:15 and teselly (cross-repo teselly@55a55b175:.blueprint.config.json:19) bett3r-pv3-ai-skills:scaffold-from-design; kixie (cross-repo kixie-phoenix@947b2f0b9:.blueprint.config.json:12) ddd:scaffold-from-design.
- Empirical (non-repo read: ls ~/.claude/plugins/cache/bett3r-ai-workflow/bett3r-pv3-ai-skills/; python3 over ~/.claude/plugins/installed_plugins.json): the cache holds pv3-ai-skills 0.15.0/0.16.0/0.17.0 with differing scaffold-from-design; only the manifest names the live one. ddd is not installed here: a kixie build here reaches no framework skill, silently.

## Solution
/build resolves the host's declared designTooling.scaffoldSkill once, through installed_plugins.json, with a new bin/skill-path, and refuses before any work if it cannot. It relays the bridge file and its plugin root to every executor and verifier dispatch; workers read skills by file and never gain the Skill tool. /start-multi runs the same check before provisioning. The five PV3 create-* skills gain a "Starting from a scaffold" section matching kixie's.

## User Stories
1. As a fleet owner, I want executor-written framework code to follow the framework's create-* skill, in a lane too.
2. As a reviewer, I want the verifier to check the slice against that skill's Final Checklist.
3. As an operator, I want a run on a machine missing the declared framework plugin to refuse before provisioning, naming the plugin and the fix.
4. As a PV3 executor finishing a scaffolded artifact, I want the skill to say up front: keep the identity, work the markers.

## Resolved decision tree

<!-- map-tree:v1 ticket=BP-196 gen=2 src=sha256:9eb13010ee64aed1a08d3413bf64083be66ff43e51f6b0f1c99dc3a3cbe586c3 out=sha256:4d27b34a80ae527075f2fccf0db2608d9f13e3a073b126a1b29c67b08e70516b -->
`map-tree:v1 ticket=BP-196 gen=2 src=sha256:9eb13010ee64aed1a08d3413bf64083be66ff43e51f6b0f1c99dc3a3cbe586c3 out=sha256:4d27b34a80ae527075f2fccf0db2608d9f13e3a073b126a1b29c67b08e70516b`
### BP-196-F1 — When the framework skill a repo declares cannot be found on this machine, what should /build do?: Check once before anything runs: /build Step 1 and /start-multi before provisioning refuse with the missing plugin and install command

decided(owner)

Why: The failure is a fact about the machine, not about any slice, so it should be found once and before any compute is spent. Writing framework code blind is the quality loss this ticket exists to remove.

resolved_by: human

- Rejected — Carry on: each slice runs and records the missing skill as a deviation the reviewer weighs: no reason recorded
- Rejected — Stop each slice that touches framework code with BLOCKED: no reason recorded

### BP-196-F2 — Should this ticket also give the PV3 create-* skills a 'Starting from a scaffold' section, as the kixie ones have?: Add a short 'Starting from a scaffold' section to the five PV3 create-* skills (aggregate, policy, read model, schema, tests), matching kixie's

decided(owner)

Why: The skills are in the same repo and the edit is small. Without it, the PV3 half of this ticket hands the agent a guide written for a situation it is not in.

resolved_by: human

- Rejected — Ship the path relay alone and file the PV3 sections as a follow-up: no reason recorded
`/map-tree:v1`
<!-- /map-tree:v1 -->

## Implementation Decisions
- D1 Path relay, not the Skill tool. Rejected: Skill on the executor (pays ADR-012's ~10.5k-token listing, docs/adr/ADR-012-artifacts-carry-rules-the-ledger-carries-evidence.md:91-96, in the longest-lived worker, 292k tokens/turn per scripts/needles.json:794; reverses the pin at scripts/test-flow-seams.sh:2953; still unreachable from step-lane-file). Rejected: pasting skill text into the dispatch (grows the orchestrator per slice).
- D2 new (created by BP-196) plugins/bett3r-ai-workflow/bin/skill-path, python3, sharing the manifest read of plugins/bett3r-ai-workflow/bin/check-skill-shadows (:27-29, config_dir :95-96, manifest :110). Verdict: SKILL-PATH:v1 outcome=ok name= file=<abs SKILL.md> root= version=, or outcome=error reason=no-manifest|not-installed|no-such-skill|ambiguous|bad-name. <plugin>:<skill> via the manifest; a scope:project entry for this repo beats scope:user; two user entries from different marketplaces = ambiguous. Bare <skill>: <repo>/.claude/skills/, then $CLAUDE_CONFIG_DIR/skills/. Rejected: cache glob / newest dir (stale copies, empirical); each executor resolving (duplicated logic).
- D3 Entry point is the declared designTooling.scaffoldSkill. Rejected: discovery from the installed set (all user-scope; pv3 and ddd can coexist); a new frameworkSkills key (second copy of the bridge's routing, plugins/bett3r-pv3-ai-skills/README.md:107).
- D4 The executor routes from the bridge: relative link beside the bridge file; <same-plugin>:<skill> = <root>/skills/<skill>/SKILL.md; ${CLAUDE_PLUGIN_ROOT} = <root>; other qualified names via skill-path (bin/ is on PATH in a lane, step-lane-file.md:24). Rejected: /build parsing the bridge table (pv3 links vs kixie qualified names; executor.md:15 "no framework knowledge"); mapping stillOwed[].node to skills (no owed-kind in docs/prs/TV2-10/scaffold.json; one command owes schema and handler).
- D5 The verifier gets the same line (scope addition; scripts/needles.json:1177 "a standard is imposed by the REVIEW agent").
- D6 build.md Step 3 item 0 reads the bridge by file in both attended and lane runs.
- D7 verify-build.md:87's executor dispatch carries the same line.
- D8 BP-267/268/269 do not remove the need: they place and fill stubs; the judgment half (schemas, handler bodies, invariants, projections, scope; plugins/bett3r-pv3-ai-skills/skills/scaffold-from-design/SKILL.md:142-148) stays owed, and slices with no designs: still hit rule 3.
- D9 (F1 applied; replaces the draft's carry-on default) No scaffoldSkill declared: prompt says "framework skill: none declared"; executor records it under deviations; no cache search. Declared but unresolved: refuse (below).
- F1 = refuse-before-start (owner). build.md Step 1 gains item 5: if scaffoldSkill is declared, run skill-path once (output to a file, read the last line); outcome=error ends the run blocked-on before Step 2, naming the plugin, the reason, the install command, and "--plugin-dir / source checkout" as a possible not-installed cause. /start-multi (plugins/bett3r-ai-workflow/commands/start-multi.md) step 0 runs the same per distinct host repo before step 2 provisions any worktree. Rejected: carry-on (framework code committed blind, learnt from the PR); block-slice (fleet pays provisioning, then stops lane by lane).
- F2 = include (owner). A "## Starting from a scaffold" section in plugins/bett3r-pv3-ai-skills/skills/create-{aggregate,policy,readmodel,schema,tests}/SKILL.md, shaped as kixie's (cross-repo kixie-marketplace@21c427d:plugins/ddd/skills/create-aggregate/SKILL.md:41): skip generation for what the scaffold produced; keep export names, ids, subdomain, placement; work only TODO(scaffold) markers and STILL OWED; the rest of the skill still governs content and the Final Checklist. Aggregate/policy/readmodel/schema already open with "what the scaffolder does" prose: the section joins it, not duplicates it; create-tests has none. Rejected: defer (PV3 agents follow the skills from the top and may rename what the design fixed).
- Edits: build.md Step 1 item 5, Step 3 items 0, 1 and 3 add "framework skill: <file> (plugin root <root>)"; verify-build.md:87; executor.md rule 3 rewritten (read the bridge before touching a framework artifact, route by D4, follow it; none declared = deviation); verifier.md:18 (Final Checklist of the create-* file the bridge routes the slice's kind to); README.md:107 "named as the Skill tool loads it" becomes "plugin-qualified, resolved by /build to a file through skill-path".
- Versions: plugins/bett3r-ai-workflow/.claude-plugin/plugin.json > 0.110.0 and plugins/bett3r-pv3-ai-skills/.claude-plugin/plugin.json > 0.17.0, values assigned at landing (README counts, scripts/check-plugin-version-bump.sh:25).
- delta: specified, deferred to build: new (created by BP-196) docs/adr/ADR-016-a-worker-reads-a-framework-skill-by-its-resolved-file.md, plugin ADR-016 "A worker reads a framework skill by its resolved file; only the orchestrator resolves it": extends ADR-012's file-not-skill posture to executor and verifier; skill-path + manifest is the single resolution; rejected Skill-tool option with ADR-012's cost; refuse-before-start rule (F1). Waits for: build. Owner: BP-196.
- delta: specified, deferred to build: plugins/bett3r-pv3-ai-skills/README.md:107 term "framework skill" = the declared scaffoldSkill resolved to a file, from which workers reach create-* skills. Owner: BP-196.

## Testing Decisions
RED at ce15b09 unless marked pin.
1. new (created by BP-196) scripts/test-skill-path.sh with fixtures under new scripts/fixtures/skill-path/: manifest names B while stale A exists -> B; absent plugin -> not-installed; no SKILL.md -> no-such-skill; bare name -> repo skill; project beats user; two marketplaces -> ambiguous; no manifest -> no-manifest; CLAUDE_CONFIG_DIR honoured. Wired as a step in .claude/gate.sh beside skill-shadows (:275-277). RED: no bin/skill-path at ce15b09.
2. F1 seam, same script: a declared-but-not-installed fixture -> outcome=error reason=not-installed naming the plugin; plus an eval scenario in scripts/eval/scenarios.json: "/build, scaffoldSkill names an uninstalled plugin" must state the run ends blocked-on before any executor dispatch, and must not contain "cannot load".
3. Relay: eval scenario "/build, declared scaffoldSkill, slice with designs: state the executor's and verifier's prompts" must contain skill-path and a "framework skill:" line; scripts/check-eval-coverage.py counts both. RED: git grep 'framework skill:' ce15b09 -- plugins/bett3r-ai-workflow = 0.
4. executor.md rule 3 and verifier.md:18 name the framework skill file; neither contains "surfaces (`create-aggregate`" (test-flow-seams grep).
5. F2: test-flow-seams asserts "## Starting from a scaffold" in all five PV3 create-* files, each naming TODO(scaffold) and "STILL OWED". RED: 0 of 5 at ce15b09.
6. Pin (census, green at base too): executor and verifier hold no Skill or SlashCommand in tools:, beside test-flow-seams.sh:2953.
7. Versions above both exceed base.
- Governs: where criterion 2 (refuse) and rejected carry-on touch rule 3's unresolved case, criterion 2 governs; "none declared" is the only deviation path.

## Risks
- A source-run plugin (--plugin-dir) is absent from the manifest, so F1 refuses although the session loaded the skill (check-skill-shadows' known blind spot). The message names this cause; the remedy is installing the plugin.
- Executor context: bridge plus one or two create-* files is ~10-20k tokens re-sent each turn; rule 3 reads them only for a framework artifact.
- A manifest shape change fails loudly (no-manifest or exit 2), pinned by fixtures.
- Owner note: strict refusal also refuses `--plugin-dir` source-run plugins; the refusal message names that cause. An escape hatch would be a new owner decision and is not added here.

## Out of Scope
- The hosted /implement routine (bett3r-routine) and the hosted scaffold step: untouched; Unfiled candidate, nearest owner BP-196.
- kixie ddd README wording "The design flow loads it" (cross-repo kixie-marketplace@21c427d:plugins/ddd/README.md:81-84) goes stale: BP-221 (kixie judgment skills and a declared scaffoldSkill).

### File overlap with siblings
- plugin.json versions (both plugins): BP-173, BP-232, BP-277, BP-198 (pv3-ai-skills), BP-268, BP-267, BP-269. Merge point; one bump per landing window.
- build.md:49 (Step 3 item 0), executor.md rule 6: BP-268 (placer). executor.md and verifier.md: BP-269 (D9 ".skip" flip, verifier check 4). Merge only.
- verify-build.md: BP-230 (Step 6c), BP-269 (:43); BP-196 edits :87 only.
- plugins/bett3r-pv3-ai-skills/skills/create-tests/SKILL.md: BP-269. If BP-269 lands first, the new section describes it.skip bodies, not it.todo.
- scaffold-from-design/SKILL.md: BP-198, BP-267 edit it; BP-196 does not.

## Provenance
- Verification pass at ce15b09 (this lane): decisions F1 and F2 confirmed. Probes re-run: `git cat-file -e HEAD:plugins/bett3r-ai-workflow/bin/skill-path` (absent, RED holds); `git grep -c 'framework skill:' -- plugins/bett3r-ai-workflow` (0); `grep -c 'Starting from a scaffold' plugins/bett3r-pv3-ai-skills/skills/create-*/SKILL.md` (0 in all); executor.md rule 3 (:21), verifier.md :18, build.md Step 3 item 0/1, verify-build.md :87 and README.md :107 read at their cited places and match.
- `map-tree check --map docs/prs/BP-196/map.json --ticket BP-196 --dialect jira <block>`: fresh, forks=2, open=0.
- Original provenance: design-multi run design-multi-next-wave-20261014, Phase C 2026-10-15; F1 and F2 decided(owner).
- Unspecified seams: none beyond Out of Scope (hosted routine untouched).
- Scaffold: none; a fleet lane never scaffolds (Step 4b).
