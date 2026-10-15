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
