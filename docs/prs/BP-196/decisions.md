## D1 — bin/skill-path is python3, not sh
kind: deviation
step: build · slice: 1 · decidedBy: verifier
sources: [design:D2, code:check-skill-shadows (plugins/bett3r-ai-workflow/bin/check-skill-shadows)]
rejected: POSIX sh — ticket D2 names python3 and the block wins over the brief
supersedes: —
The brief called for sh; the ticket block says python3 sharing check-skill-shadows' manifest read. config_dir() is restated, not imported (extensionless tool). The test runs under sh, dash and bash.

## D2 — Project-scope matching follows Claude Code's canonical git root; scopes map to three levels
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:_r (Claude Code 2.1.300 binary), design:D2]
rejected: exact-realpath compare — lane worktrees and subdirectories would read not-installed (fix round 1, F1); parent-of-git-common-dir — merged submodules and separate-git-dir repos (fix round 2, N1)
supersedes: —
Fix rounds: 1 = design-silent (worktree/subdir, local/managed scope, malformed entry, empty projectPath), 2 = ripple (submodule root, test leaking GIT_DIR). local over project over user/managed; same level is ambiguous; a malformed entry under any plugin key is reason=no-manifest. Both rounds executor=fresh.

## D3 — Precedence premise (project beats user) may not match the platform
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [design:D2, code:VUn (Claude Code 2.1.300 binary)]
rejected: flipping the precedence — ticket block D2 governs and an unattended lane cannot ask the owner
supersedes: —
Owner to confirm: a manifest with user version A and project version B for the repo, session started in the repo, which installPath loads. If A loads, D2 and skill-path's level order flip. Harm if wrong is version skew. Also L1: docstring "Mirrors Claude Code" overstates (git --show-toplevel vs a walk-up); and F5: paths with spaces break the one-token-per-field verdict.

## D4 — Four dispatch sites outside /build and /verify-build carry no framework skill line
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [design:D1, design:D9, code:start-multi.md:53, code:start-multi.md:82, code:merge-multi.md:107, code:design.md:153]
rejected: covering them in slice 2 — outside the design's edit list, and slice 3's gate forbids touching start-multi step 1b
supersedes: —
The structural scenario's second half is false: start-multi.md:53 (wave prefactor executor), start-multi.md:82 (backfill verifier), merge-multi.md:107 (follow-up sweep executor), design.md:153 (Step 4b executor) dispatch a worker without the line. The census names them as exemptions. Owner call: cover them, and decide what rule 3 / verifier item 2 say for a prompt carrying no line at all (D9 makes "none declared" the only deviation path). Also: nothing guards the presence of eval scenario build-declared-scaffold-skill-relay.

## D5 — Fix-round dispatches carry the line; refusal sits in Step 3 item 0 until slice 3
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [design:D6]
rejected: —
supersedes: —
build.md:77 and :80 (fresh fix-round executor / re-check verifier) carry the line by analogy. The unresolved-skill refusal is interim at item 0; slice 3 must move it to Step 1 item 5 and update its census pin.

## D6 — start-multi refusal: verdict word, anchor in step 0, and a resume gap
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:F1, code:start-multi.md step 0, code:fleet-loop.py]
rejected: leaving the check at the end of step 0 — the verifier showed the order of :32 ran the BASE push and scaffold agent first (fix round 1, design-silent)
supersedes: —
The refusal ends the tick `blocked-on=framework-skill` (word chosen by analogy with lane-tools); an anchor at start-multi.md:32 puts the check before pinning BASE, pinned by an offset census; the refusing tick still writes run.yaml with pluginVersion. Install command is `claude plugin install <plugin>` (marketplace cannot be derived).

## D7 — Refusing fresh run leaves run.yaml without BASE
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:start-multi.md:32, code:fleet-loop.py:284-291]
rejected: fixing it in slice 3 — not a named mitigation, and the same state already arises when a step-0 tick ends before BASE is pinned
supersedes: —
A later /start-multi without --fresh matches "Resume when run.yaml exists" with no BASE; it fails loudly at step 2 (origin/int/<run-id> missing). Follow-up: a run.yaml without createdBaseSha resumes as fresh and re-runs the check, or the refusal tells the operator to re-run with --fresh; pin in the census. Also optional: ADR-016's "once per /build run" parenthesis omits /verify-build's in-lane resolution.

## D8 — Scaffold section keeps names, label-derived name, subdomain and module folder; create-tests keeps the scenario-id title prefix
kind: false-premise
step: build · slice: 4 · decidedBy: verifier
sources: [code:subdomainFromPath.ts (pv3-library-blueprint-extractor), code:placement.ts (pv3-library-blueprint-scaffold), code:verifier.md:26, design:F2]
rejected: kixie's "keep the folder: not part of the node id, but couplings attach to it" — false for PV3, where the module folder is the subdomain and the subdomain is in the node id; create-tests keeping "export name, id, subdomain" — test files carry none of them, the identity is the `<scenarioId>: ` title prefix
supersedes: —
The design cites kixie's create-aggregate wording as the shape; copying its folder rationale into PV3 was wrong (the verifier's own first-pass recommendation, withdrawn on re-check). Three doc rounds' worth of findings (F1 oracle-wrong: create-schema STILL OWED satisfied by pre-existing prose, section moved below it; F2/F3/F4/G1 doc-wording). The final doc round was confirmed by diff inspection (four prose sentences, no re-check dispatched).

## D9 — create-tests describes it.todo, not it.skip
kind: deviation
step: build · slice: 4 · decidedBy: executor
sources: [design:F2, code:scaffold-from-design/SKILL.md:128, code:pv3 emit/tests.ts]
rejected: it.skip-with-body wording — BP-269 (ADR-041) has not landed in this tree and pv3's emitter on master still writes it.todo
supersedes: —
The PR body must say so; if BP-269 lands first, create-tests' scaffold section needs the it.skip-with-body wording. The kixie reference wording was unreachable to the executor; the verifier read it on this machine.
