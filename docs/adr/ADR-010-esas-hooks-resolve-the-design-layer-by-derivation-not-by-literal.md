# ADR-010: ESAS hooks resolve the design layer by derivation, not by literal

**Status:** Proposed
**Date:** 2026-09-17
**Ticket:** ESAS-126
**Depends on:** ADR-001 (plugin version is a release contract: a consumer ships only after the release that serves it is installed)
**Constrains:** ESAS-158 (bett3r-pv3-ai-skills copies the `esas-root-base` sub-block), ESAS-202 (pv3's extractor and scaffold defaults use the key table below), ESAS-62 (esas's TypeScript resolver uses the key table below), ESAS-159 (removes the repo-local candidates), ESAS-171 (per-session `active` file edits the same block), ESAS-188 (the deferred writer of the client pairs)
**Grounding:** `plugins/bett3r-ai-workflow/hooks/esas-pending.sh`, `plugins/bett3r-ai-workflow/hooks/esas-session-channel.sh`, `plugins/bett3r-ai-workflow/skills/esas-design/PREFLIGHT.md`, `plugins/bett3r-ai-workflow/skills/esas-design/ESAS-ROOT.md` (new, created by ESAS-126), `plugins/bett3r-ai-workflow/hooks/hooks.json`, `plugins/bett3r-ai-workflow/hooks/README.md`, `plugins/bett3r-ai-workflow/agents/provisioner.md`, `scripts/test-hooks.sh`, `scripts/test-esas-design.sh`, `scripts/check-plugin-version-bump.sh`, `plugins/bett3r-ai-workflow/.claude-plugin/plugin.json` — all at plugin 9c835c0; cross-repo `pv3@423250d0819f516b5a8f185a79c4684b01bc8a00:packages/pv3-cli/src/commands/generate/esas.ts`

The source of truth for every decision below is the resolved design block on ESAS-126 (run `design-multi-ESAS-125-…-81`, base 9c835c0). This record restates those decisions and their evidence; it adds none.

## Context

Every ESAS reader in this plugin finds the design layer through a literal: `<repo>/.esas/`. The pending-count hook `esas-pending.sh` hard-codes it at line 2 and at lines 87-89. The session-channel hook `esas-session-channel.sh` gates on it at line 2. The `/design` probe in `PREFLIGHT.md` tests it at lines 58-64. The model-read prose repeats it in sixteen files.

The ESAS relocation chain moves that layer out of the repository into a per-user data directory, `<base>/projects/<key>/`. The chain releases in a fixed order: this ticket installed, then ESAS-158 installed, then ESAS-202, then ESAS-62, then ESAS-159. The plugin is first because its readers must already understand the new root before anything writes there. If a writer moved first, every session would read an empty repo-local root and fall silent.

This is the local track. The 2026-09-17 hosted-product reset keeps local sessions for developers who build, so the chain still ships, but nothing hosted waits on it.

That ordering means the plugin defines an algorithm that esas and pv3 have not built yet. The key and base derivation in Decision 4 is therefore the reference table: ESAS-62 and ESAS-202 copy it from this ADR.

## Decision 1 — Four feed/cursor pairs over two roots are the candidate set

There are two roots: the user-data root (UD), `<base>/projects/<key>/`, and the repo-local root (RL), `<repo>/.esas/`. Each root has two pairs. The client pair is `client/feed.jsonl` with `client/.claude-cursor`. The legacy pair is `ops.jsonl` with `.claude-cursor`.

The client pairs stay although their only writer is now the deferred ESAS-188. Removing them now would force another plugin release before ESAS-188 un-defers, and each release is a human install step (ADR-001).

*Rejected:* three locations. Depending on the order in which the chain lands, a three-location set misses one of the client pairs.

## Decision 2 — The first pair whose feed file exists wins, in the order UD-client, UD-legacy, RL-client, RL-legacy

Selection tests the feed file, not the directory.

The reason is a concrete window in the release order. Once ESAS-202 releases, `pv3 g esas` can create a UD root that holds only `graph.json`, while esas still appends its feed to RL. pv3's generator composes its output path and creates it with `fs.mkdir( outDir, { recursive: true })` (`cross-repo pv3@423250d0:packages/pv3-cli/src/commands/generate/esas.ts` lines 61 and 68). A resolver that chose the root by directory existence would pick that UD root, find no feed, and go silent while live ops accumulate in RL.

*Rejected:*
- Choosing a root by directory existence — silent in the window above.
- Newest feed wins — `test -nt` is not POSIX, and the hooks run under `sh` and `dash`.
- RL first — once ESAS-62 moves writes to UD, RL holds frozen residue and would be read forever.

*Accepted residue:* after ESAS-62's clean cut, a stable, stale RL count can show until the first UD op is written or ESAS-159 removes the RL candidates.

## Decision 3 — Inside a root the client pair wins, and a feed and its cursor always come from the same pair

The pending count compares byte offsets: `if [ "$size" -eq "$cursor_offset" ]` (`esas-pending.sh:231`). An offset means something only against the feed it was recorded for. So the resolver picks a pair, never a feed and a cursor independently. Everything in `esas-pending.sh` from `valid_int` (:95) down stays byte-identical.

A client feed that has only a legacy cursor beside it takes the no-cursor path and reports the full count.

*Rejected:* summing the pairs (double counts ops present in both); independent existence tests for feed and cursor (can combine a feed with another pair's cursor).

## Decision 4 — The key and base derivation (the reference table)

**Key.** Take `pwd -P` inside a `CDPATH= cd --` subshell, the idiom already used at `esas-session-channel.sh:82`. Then, with a parameter-expansion loop and no `sed` or `tr` exec, map every `-` to `--`, then every `/` to `-`.

| Physical path | Key |
|---|---|
| `/a/b-c` | `-a-b--c` |
| `/a-b/c` | `-a--b-c` |
| `/a b/c` | `-a b-c` |

**Base.** If `$ESAS_DATA_HOME` is non-empty, it is the base; it replaces the whole `.../esas` base, not a parent of it. Otherwise, with `HOME` set, the candidates are `$HOME/Library/Application Support/esas` and then `${XDG_DATA_HOME:-$HOME/.local/share}/esas`; the first whose `projects/` directory exists is the base. There is no `uname` call.

**Short-circuit.** If no base qualifies and `[ -d "$root/.esas" ]` fails, the hook exits before any fork. An empty `pwd -P` or an unset `HOME` composes no path.

A prototype was run on 2026-09-16 under `sh`, `dash` and `bash`: the three produced identical key tables, and 50 runs with no root took 0-1 s.

*Rejected:* hashing the path (no portable hash in POSIX sh); a pointer file in the repo (reintroduces the repository file the move exists to remove).

## Decision 5 — The resolver is fenced in two nested parts

The whole resolver sits between `# >>> esas-root` and `# <<< esas-root`. Inside it, the base and key derivation sits between `# >>> esas-root-base` and `# <<< esas-root-base`, and ends by setting `esas_base` and `esas_key` (empty when none).

After the inner fence, the four pair candidates are four contiguous lines, one per pair, in Decision 2's order. In `esas-session-channel.sh` the RL gate arm is on its own line. ESAS-159's removal of RL is then a pure line deletion.

All variables are `esas_`-prefixed, per PREFLIGHT's no-rename rule (`PREFLIGHT.md:24-26`).

The inner fence exists so a consumer that reads no feed can copy and byte-compare only the derivation. ESAS-158's skill is that consumer.

*Rejected:* one undivided block — ESAS-158 could not byte-compare a sub-part.

## Decision 6 — The resolver is inlined in each of the three files, never sourced, and a test proves the copies byte-identical

The block is copied into `esas-pending.sh`, `esas-session-channel.sh` and `PREFLIGHT.md`.

Three facts rule out sharing it:
- The manual install copies only `esas-pending.sh` to `.claude/esas-pending.sh` (`plugins/bett3r-ai-workflow/hooks/README.md` lines 142-146). A sourced helper would be missing there.
- `.` of a missing file ends a non-interactive `dash` with rc 2, breaking the hooks' exit-0 contract (Decision 9).
- The PREFLIGHT snippet runs in the model's Bash tool, where `CLAUDE_PLUGIN_ROOT` is unset (`PREFLIGHT.md:28`), so it cannot locate a plugin file.

Drift is caught by `scripts/test-hooks.sh`: it extracts each file's text with `sed -n '/# >>> esas-root$/,/# <<< esas-root$/p'` (and the `-base` variant) and compares with `cmp`.

*Rejected:* a `bin/esas-root` executable — a fork and exec on every prompt in every repo, and absent from manual installs.

## Decision 7 — The session-channel gate passes when `<repo>/.esas` or `<base>/projects/<key>` is a directory

The gate remains a pre-filter. The verdict is still the `repoPath` match against `/api/esas/status`. The `esas_physical` computation (:82) moves above the curl (:72) and feeds the key.

Here directory existence is right, unlike Decision 2: a board serves before any feed or `session.json` exists. The old premise that only anchor ops write the directory was false — `session.json` has three writers.

*Rejected:* gating on `session.json` or a feed (misses a serving board); gating on "any base exists" (a curl at every session start in every repo).

## Decision 8 — One release covers both hooks, PREFLIGHT and all model-read `.esas/` prose (scope C)

PREFLIGHT reports `esas_dir: present` with the resolved root path, the graph and design under it, and `ops` by the pair rule. `plugins/bett3r-ai-workflow/agents/provisioner.md` resolves the main checkout's root, since fleet worktrees use the main checkout's key.

The model-readable rule lives in a new `plugins/bett3r-ai-workflow/skills/esas-design/ESAS-ROOT.md` (new, created by ESAS-126). It defines an *ESAS root* as `<base>/projects/<key>/` or `<repo>/.esas/`, and a *feed pair* as a feed and its own cursor, never mixed. The sixteen prose files that mention `.esas/` link to it. The `plugins/bett3r-ai-workflow/hooks/hooks.json` description no longer says "without a .esas/ directory".

bett3r-pv3-ai-skills prose is out of scope; ESAS-158 owns it.

## Decision 9 — The hook contracts are preserved

Every path exits 0, writes nothing to stderr, and prints one line or none.

## Decision 10 — The release is a minor version bump taken from master at build time

At this base `plugin.json` is 0.81.0, so the bump is 0.82.0 unless another plugin PR lands first; `plugin.json` and `README.md` are shared with ESAS-200, and whichever lands second rebases and re-bumps. The gate is `sh scripts/check-plugin-version-bump.sh origin/master`.

After merge, the release is confirmed by a human install: the cache directory lists the new version, and `cmp` of the cached `plugins/bett3r-ai-workflow/hooks/esas-pending.sh`, `plugins/bett3r-ai-workflow/hooks/esas-session-channel.sh` and `plugins/bett3r-ai-workflow/skills/esas-design/PREFLIGHT.md` against source reports identical. ESAS-158 builds only after merge. ESAS-202, ESAS-62 and ESAS-188 merge only after that checkpoint (ADR-001).

## Decision 11 — ESAS-123 needs no action

It is already Done as a duplicate of this ticket.

## Consequences

- The plugin owns a derivation that two other repos must reproduce exactly. A deviation there in escaping, base semantics or the `projects/` segment silences the hook after the move. The mitigation is that ESAS-62 and ESAS-202 carry the identical table; agreement cannot be tested from this repo.
- On darwin, if an XDG `esas/projects` exists but an Application Support one does not, the hook reads XDG while esas's TypeScript picks Application Support. This is harmless while nothing on darwin writes XDG; ESAS-62 tests it.
- Sessions on older plugin versions, and hand-installed hook copies, go silent after ESAS-62. The README documents this.
- The RL candidates are a bridge. ESAS-159 removes them by deleting lines.
- No sibling reader exists today: `` git grep -nE '\.esas([/"` ]|$)' 9c835c0 -- plugins/bett3r-xp-layer `` returns 0 hits.

## Provenance

None of these decisions came from the owner's scope reset of 2026-09-17. That reset only placed the ticket on the local (v1, not blocking hosted) track and confirmed the chain still ships.

- Owner decisions from the 2026-09-13/14 sitting, carried: the four-pair candidate set (D1) and scope C (D8, Tomas, 2026-09-14).
- Carried, applied on recommendation: UD-over-RL precedence (D2); the pair rule (D3); the key and base derivation, refined by engineering (D4); the session-channel gate, with its premise corrected (D7); the hook contracts (D9); ESAS-123 (D11).
- Applied on recommendation from the seam ruling: the nested `esas-root-base` fence (D5).
- Settled by code or engineering: the feed-existence predicate (D2); inline plus drift test (D6); the version bump (D10).

## Open / owned elsewhere

- The esas TypeScript resolver and its darwin XDG case — ESAS-62.
- pv3's extractor and scaffold defaults using this key table — ESAS-202.
- bett3r-pv3-ai-skills prose and its copy of `esas-root-base` — ESAS-158.
- Removing the repo-local root and its candidate lines — ESAS-159.
- The writer of the client pairs (esas-mcp local sync client) — ESAS-188, deferred; may land any time after this ticket.
- A per-session `active` file in the same block — ESAS-171.
