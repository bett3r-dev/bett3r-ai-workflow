# bett3r-ai-workflow

A Claude Code plugin that encodes a **vertical-slice, dual-gated development flow**. It is the *methodology* — project-agnostic. It reads each host repo's own conventions (`.claude/rules/`, installed framework plugins, `.esas.config.json`) at runtime, so the same flow works in any repo, PV3 or not.

## The flow

| Phase | Command | What it does |
|-------|---------|--------------|
| Start | `/bett3r-ai-workflow:start` | Thin: branch + ephemeral `.work/` scaffold. |
| Design | `/bett3r-ai-workflow:design` | Grill the design while sharpening the domain model → reviewable `.work/design.md` (md + mermaid). |
| Plan | `/bett3r-ai-workflow:plan` | Cut the design into **vertical slices** (tracer bullet first, prefactor first), review, → `.work/slices.yaml`. `--publish` also creates Jira sub-tasks. |
| Build | `/bett3r-ai-workflow:build` | Per slice: **executor → test gate → verifier gate → commit**. |
| Verify | `/bett3r-ai-workflow:verify-build` | Whole-PR coherence review + dev checklist + open the PR (the record). |
| Capture | `/bett3r-ai-workflow:capture-learnings` | Route each learning to the repo that owns it — origin-aware → GitHub issue in the owning plugin, or local. |
| Evolve | `/bett3r-ai-workflow:evolve` | In a plugin repo: turn its `ai-learning` issues into reviewed PRs. |

Utility: **`/bett3r-ai-workflow:commit`** — smart, logically-grouped commits for ad-hoc work outside the slice loop (`/build` commits each slice itself).
| Multi | `/bett3r-ai-workflow:start-multi` | Fleet orchestrator: drive N work units through the flow in parallel, one git worktree each. Resumable; PRs opened ready for review. |

Hook: **`UserPromptSubmit` → `esas: N pending (seq A→B)`** (`hooks/esas-pending.sh`). While the user has unsynced edits on the ESAS design board, the count goes in front of the next prompt so Claude knows its picture is stale — telemetry, never a trigger. Silent and free in every repo without a `.esas/` directory, and it always exits 0, because a `UserPromptSubmit` hook that doesn't would erase the user's prompt. The standing rule for reacting to it (never unsolicited) is the **`esas-pending`** skill. See `hooks/README.md`.

ESAS board mode: in a repo with a `.esas/`, **`/design`** opens a second surface — decisions go to `.work/design.md` as always, structure goes to a live board the user watches while you talk, through the `esas-mcp` tools. Step 0 of the command is the preflight (extracted and run against fixture host repos by `scripts/test-esas-design.sh`); the gestures on top of it — the sync point, corrections, the two restarts, the main-checkout-only fleet rule — are the **`esas-design`** skill. Registering the MCP server takes effect only on session restart, so the command makes that its own explicit step and stops there.

Plus skills: **`grill`** (the relentless design interview), **`critique`** (the divergent counterpart — a one-shot adversarial multi-lens stress-test of a resolved design; wired into `/design` and `/verify-build`), **`domain-modeling`** (sharpen the ubiquitous language + ADRs; glossaries live in the host repo's domain package), **`seed-context`** (bootstrap a whole bounded context's glossary from existing code — code-first, grill the gaps; refers to `domain-modeling`), **`vertical-slicing`** (the slicing methodology), and **`record`** (instant frictionless capture of a thought/learning to `.work/learnings.md`, drained by `capture-learnings`). And the generic agent roles: **`executor`**, **`verifier`**, **`test-runner`**.

## Propagation (capture → evolve)

The flow improves itself. `capture-learnings` routes each learning to **where its source-of-truth lives** — an improvement to a shared skill becomes a GitHub issue in that plugin's repo; a repo-specific fact stays local. `evolve`, run inside a plugin repo, turns its accumulated issues into reviewed PRs. On merge, every repo that installs the plugin gets the improvement. (Requires each plugin's `repository` set in `plugin.json`, or a git remote, for issue routing.)

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

A PV3 repo installs this **plus** `bett3r-pv3-ai-skills`; a non-PV3 repo installs just this.

## Install

```bash
claude plugin marketplace add <this-repo-url>
claude plugin install bett3r-ai-workflow
# or for local dev, from your clone of this repo:
claude --plugin-dir ./plugins/bett3r-ai-workflow
```
