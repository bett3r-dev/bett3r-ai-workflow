# bett3r-ai-workflow

A Claude Code plugin that encodes a **vertical-slice, dual-gated development flow**. It is the *methodology* — project-agnostic. It reads each host repo's own conventions (`.claude/rules/`, installed framework plugins, `.esas.config.json`) at runtime, so the same flow works in any repo, PV3 or not.

## The flow

| Phase | Command | What it does |
|-------|---------|--------------|
| Start | `/bett3r-ai-workflow:start` | Thin: branch + ephemeral `.work/` scaffold. **No test run** — the baseline records the base sha and is captured on demand, only if a `HEAD` comes up red. |
| Design | `/bett3r-ai-workflow:design` | Grill the design while sharpening the domain model → reviewable `.work/design.md` (md + mermaid). |
| Plan | `/bett3r-ai-workflow:plan` | Cut the design into **vertical slices** (tracer bullet first, prefactor first), review, → `.work/slices.yaml`. `--publish` also creates Jira sub-tasks. |
| Build | `/bett3r-ai-workflow:build` | Per slice: **executor → test gate → verifier gate → commit**. |
| Verify | `/bett3r-ai-workflow:verify-build` | Whole-PR coherence review + dev checklist + open the PR (the record). |
| Capture | `/bett3r-ai-workflow:capture-learnings` | Route each learning to the repo that owns it — origin-aware → GitHub issue in the owning plugin, or local. |
| Evolve | `/bett3r-ai-workflow:evolve` | In a plugin repo: turn its `ai-learning` issues into reviewed PRs. |

Utility: **`/bett3r-ai-workflow:commit`** — smart, logically-grouped commits for ad-hoc work outside the slice loop (`/build` commits each slice itself).

Measurement: **`/bett3r-ai-workflow:run-report`** — where a unit of work's time and tokens actually went, per pipeline command, per role, per slice. It reads Claude Code's own transcripts (`scripts/run-metrics.mjs`), so nothing is instrumented and **any past branch can be reported retroactively**. `/verify-build` runs it with `--emit` as its last step, recording each finished unit to `~/.claude/bett3r-metrics/`; `--aggregate` then compares runs **by plugin version**, which is what makes "did that change to the flow help?" an answerable question. Time is classified (tool / reason / child / stalled) rather than inferred from first→last timestamps, and records are sliced by git branch — the two mistakes that make transcript-derived numbers confidently wrong.
Fleet:

| Phase | Command | What it does |
|-------|---------|--------------|
| Multi | `/bett3r-ai-workflow:start-multi` | Fleet orchestrator: drive N work units through the flow **unattended**, one git worktree each — in parallel where safe, serially where not. Cuts one integration branch `int/<run-id>` for the run; every unit PR targets it. Resumable; ends at N PRs opened ready for review, merging nothing. |
| Land | `/bett3r-ai-workflow:merge-multi` | After you have reviewed those PRs: merge them into the integration branch (conflicts resolved **once**, never by rebasing a reviewed branch), run the full gate **once** there, open one index-style integration PR. `--land` merges it to the default branch. Run it in a **fresh session** — the fleet conversation is the run's largest context and none of it is needed to land. |

Hook: **`UserPromptSubmit` → `esas: N pending (seq A→B)`** (`hooks/esas-pending.sh`). While the user has unsynced edits on the ESAS design board, the count goes in front of the next prompt so Claude knows its picture is stale — telemetry, never a trigger. Silent and free in every repo without a `.esas/` directory, and it always exits 0, because a `UserPromptSubmit` hook that doesn't would erase the user's prompt. The standing rule for reacting to it (never unsolicited) is the **`esas-pending`** skill. See `hooks/README.md`.

ESAS board mode: in a repo with a `.esas/`, **`/design`** opens a second surface — decisions go to `.work/design.md` as always, structure goes to a live board the user watches while you talk, through the `esas-mcp` tools. Step 0 of the command is the two gates, the preflight (extracted and run against fixture host repos by `scripts/test-esas-design.sh`) and the table that turns each verdict into a response — the trigger stays inline, the response does not: everything downstream of a double yes (registering the server, seeding the design layer, the launch offer, what changes in Steps 2–3) is `skills/esas-design/BOARD-SETUP.md`, opened only when a verdict calls for it, so the most-used command in the flow does not carry board prose into every repo that has no board. The gestures on top of all of it — the sync point, the summon that lets the board wake an idle session (one frame on a session channel, `/api/esas/ws`, held open with `Monitor` — plus a `SessionStart` hook that says to open it when a board is up and nobody is), the withdrawal and correction gestures, the two restarts, the main-checkout-only fleet rule — are the **`esas-design`** skill. Registering the MCP server takes effect only on session restart, so that is its own explicit step and the command stops there.

## The gate is the host repo's, not the plugin's

`yarn test` is a guess, and the plugin no longer makes it. A host repo declares its own validation gate as **`.claude/gate.mjs`** (Node, so a Windows contributor needs no bash to run their own repo's gate; an existing `.claude/gate.sh` is still accepted), taking `--fast` (build + typecheck — the inner loop) or `--full` (everything that must be true before code lands: tests, integration tests, codegen drift, lint), and printing one `GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE <detail>` line per step so a caller can read *which* step failed and with what counts. The **`full-gate`** skill carries the contract, an example script, the discovery fallback, and the four ways a "green" read is wrong.

A repo may also declare a **scoped** middle mode as its no-argument default — whole-repo structural checks, then only the suites and guards its diff touches — for the human inner loop. The flow never selects it: a scoped verdict certifies a diff and its importers, not the tree.

Where it runs: `/verify-build` runs `--full` for a single unit of work, or `--fast` when the unit is one lane of a fleet (the `provisioner` stamps `.work/fleet-lane.yaml` to say so). The full gate is then hoisted to `/merge-multi`, which runs it once on the assembled integration branch — the only tree where cross-unit breakage exists at all, and N−1 fewer full runs than gating every lane.

Plus skills: **`grill`** (the relentless design interview), **`critique`** (the divergent counterpart — a one-shot adversarial multi-lens stress-test of a resolved design; wired into `/design` and `/verify-build`), **`domain-modeling`** (sharpen the ubiquitous language + ADRs; glossaries live in the host repo's domain package), **`seed-context`** (bootstrap a whole bounded context's glossary from existing code — code-first, grill the gaps; refers to `domain-modeling`), **`vertical-slicing`** (the slicing methodology), **`full-gate`** (the host repo's `.claude/gate.mjs` convention and how to read its verdict), and **`record`** (instant frictionless capture of a thought/learning to `.work/learnings.md`, drained by `capture-learnings`). And the generic agent roles: **`executor`**, **`verifier`**, **`test-runner`**, **`scope-check`**, **`provisioner`**.

## Propagation (capture → evolve)

The flow improves itself. `capture-learnings` routes each learning to **where its source-of-truth lives** — an improvement to a shared skill becomes a GitHub issue in that plugin's repo; a repo-specific fact stays local. `evolve`, run inside a plugin repo, turns its accumulated issues into reviewed PRs. On merge **and a version bump**, every repo that installs the plugin gets the improvement on its next refresh — the bump is not bookkeeping, it is the release itself, because the install is a version-keyed cache that copies nothing when the string has not moved (see `docs/adr/ADR-001`, and the CI gate that now refuses the omission). (Requires each plugin's `repository` set in `plugin.json`, or a git remote, for issue routing.)

## Core principles

- **A slice is the smallest independently-*verifiable* behavior**, cut top-to-bottom through all layers — never a horizontal layer. Only a vertical slice has its own green signal, which is what lets the loop verify and commit it on its own.
- **Tracer bullet first.** The first slice is the thinnest end-to-end path through the riskiest, gate-less seam — proving the architecture before fleshing it out.
- **Dual gate.** A slice is done only when its automated test passes **and** a verifier confirms the host repo's architectural invariants (the judgment tests can't catch). Tests alone ship defects that pass tests.
- **Git is the system of record.** One commit per slice. The PR description carries the design narrative + per-slice summary. ADRs capture decisions. Nothing else is kept.
- **Minimal, ephemeral residue.** Working state (`design.md`, `slices.yaml`) lives in a gitignored `.work/` and evaporates — promoted into the PR + ADRs on landing. No committed `sdd.md` / `build-progress.md` / test-plan scaffolding.

## The plugin/project seam

This plugin ships the **roles and methodology**. The **domain knowledge** stays in the host repo and its framework plugins:

- The `verifier` reads `${CLAUDE_PROJECT_DIR}/.claude/rules/` for the host repo's invariants.
- The `executor` uses whatever framework skills the host repo provides (e.g. the `bett3r-pv3-ai-skills` plugin's `create-aggregate`).
- **Where a design graph fixes an artifact mechanically, `/build` generates it before the executor runs** (step 0), scoped to the slice's `designs:` node ids. The flow stays framework-agnostic: it looks for a design scaffolder and skips the step when the repo has none. What the generator refuses to guess — a location, a payload, an invariant — is surfaced as a design question rather than filled in, because a scaffold block is a finding about the design, not an obstacle in the build.

A PV3 repo installs this **plus** `bett3r-pv3-ai-skills`; a non-PV3 repo installs just this.

## Install

```bash
claude plugin marketplace add <this-repo-url>
claude plugin install bett3r-ai-workflow
# or for local dev, from your clone of this repo:
claude --plugin-dir ./plugins/bett3r-ai-workflow
```
