# bett3r-ai-workflow

A Claude Code plugin that encodes a vertical-slice, dual-gated development flow. It ships the method and the roles, and reads each host repo's own conventions (`.claude/rules/`, installed framework plugins, `.esas.config.json`) at runtime, so one flow works in any repo. The defining constraint is that nothing lands on a single signal: a slice is done when its test passes **and** a verifier confirms the host's invariants, and a unit lands with its record committed beside the code.

## The flow

| Phase | Command | What it does |
|---|---|---|
| Start | `/bett3r-ai-workflow:start` | Cuts the branch and writes a fresh `.work/mode.yaml`. Records the base sha; runs no suite. |
| Design | `/bett3r-ai-workflow:design` | Grills the design to shared understanding while sharpening the domain model, then commits `design.md` (plus a clickable `map.json` / `map.html` where the design is fork-shaped) in the folder `work-docs-path` names, `docs/prs/<id>/` by default. |
| Plan | `/bett3r-ai-workflow:plan` | Cuts the design into vertical slices, tracer bullet first, and writes `.work/slices.yaml`. `--publish` also creates Jira sub-tasks. |
| Build | `/bett3r-ai-workflow:build` | Per slice: executor → test gate → scope-check and verifier → commit. Writes `decisions.md` and `build-summary.md`. |
| Verify | `/bett3r-ai-workflow:verify-build` | Runs the host gate, one whole-PR review, the dev checklist, ADRs, rules the concerns, measures the run, and opens the PR that links the record. |
| Capture | `/bett3r-ai-workflow:capture-learnings` | Routes each learning to the repo that owns the artifact, filed with its filters and expiry. |
| Evolve | `/bett3r-ai-workflow:evolve` | In a plugin repo, turns `ai-learning` issues into reviewed PRs, pruning first. |

Fleet:

| Phase | Command | What it does |
|---|---|---|
| Multi | `/bett3r-ai-workflow:start-multi` | Drives N units through the flow unattended, one worktree each, in parallel where safe. Every unit PR targets one integration branch, `int/<run-id>`; the run ends at N PRs, merging nothing. `/bett3r-ai-workflow:design-multi` does the same for N designs, batching the genuine forks into one human sitting. |
| Land | `/bett3r-ai-workflow:merge-multi` | After review: merges the unit PRs into the integration branch (conflicts resolved once), runs the gate once there, opens one integration PR. `--land` merges it. Run it in a fresh session. |

Utilities: `/bett3r-ai-workflow:commit` (logically grouped commits for ad-hoc work) and `/bett3r-ai-workflow:run-report` (where a unit's time and tokens went, read from the transcripts, so any past branch can be reported; `--aggregate` compares runs by plugin version).

## The gate is the host repo's

The plugin makes no guess about what "green" means. A host repo declares its own gate as `.claude/gate.mjs` (or `.claude/gate.sh`), taking `--fast`, no argument (scoped: whole-repo structural checks, then only the suites and guards the diff touches) or `--full`, and printing one `GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE <detail>` line per step. `/verify-build` runs the scoped mode for a unit landing alone, or `--fast` for one lane of a fleet (`gateDeferred: true` in its `.work/lane.yaml`), and `/merge-multi` runs the scoped mode once on the integration branch. The whole-repo run is CI's, or the user's on request; no flow step selects it. Every verdict is reported with the blind spot it leaves: a scoped pass certifies the diff and its importers, not the tree. The `full-gate` skill carries the contract and how to read a verdict.

## The record

Git is the system of record: one commit per slice, and one folder per work item under the work-docs root (`work-docs-path` resolves it) holding `design.md`, `decisions.md`, `concerns.md` and `build-summary.md`, one copy each. The PR body links that folder. ADRs own the decisions that outlive a work item. The gitignored `.work/` holds working state only (`slices.yaml`, `mode.yaml`, a lane brief, learnings, handoffs) and is disposable.

## The plugin/project seam

This plugin ships roles and method; the domain knowledge stays in the host repo and its framework plugins:

- the `verifier` reads `${CLAUDE_PROJECT_DIR}/.claude/rules/` for the host's invariants;
- the `executor` uses whatever framework skills the host provides (a PV3 repo installs `bett3r-pv3-ai-skills` beside this plugin);
- where a design graph fixes an artifact mechanically, `/build` runs the scaffolder the repo declares as `designTooling.scaffold` in `.esas.config.json` before the executor, and skips the step when nothing is declared.

## ESAS board mode

In a repo with a `.esas/` design layer, `/design` opens a second surface: decisions still go to the committed design, structure goes to a live board the user watches, through the `esas-mcp` tools. The `esas-design` skill carries the standing rules, the `esas-pending` skill the rule for the hook line below, and `skills/esas-design/BOARD-SETUP.md` everything downstream of a board being present, opened only when the command's gates say so.

## Hooks

Three, all in `hooks/hooks.json` and each one cheap check and gone in a repo where it does not apply:

| Hook | Fires | Does |
|---|---|---|
| `esas-pending.sh` | `UserPromptSubmit` | Puts `esas: N pending (seq A→B)` in front of the prompt while the user has unsynced board edits. Telemetry, never a trigger. |
| `esas-session-channel.sh` | `SessionStart` | Tells a session to open the board's summon channel when a board is serving this repo and nobody holds it. |
| `lane-git-guard.sh` | `PreToolUse` on `Bash` | When the checkout a command acts on holds `.work/lane.yaml` (an unattended lane), blocks the git commands that discard or shelve the working tree. |

## It's working if

- `/start` finishes in seconds and runs no tests; `.work/mode.yaml` names the work item.
- Every slice in `/build` goes red before it goes green, and lands as its own commit.
- `/verify-build` opens the PR ready for review with a `### Record` section linking four files, and a `flow/concerns` status on the head commit.
- A fleet run ends with N open PRs against `int/<run-id>` and nothing merged.
- A gate verdict in a PR body names its mode and what it did not run.

## Propagation

The flow improves itself: `capture-learnings` files an improvement to a shared skill as an issue in the plugin that owns it; `evolve`, run in that plugin's repo, turns the issues into reviewed PRs. A merge reaches installs only with a version bump, because the install is a version-keyed cache (`docs/adr/ADR-001`).

## Where the evidence lives

The artifacts carry rules. The evidence behind them lives in two files nothing loads by default: `EVIDENCE.md`, the four facts about what counts as evidence that every gate and sweep falls out of, and `LEDGER.md`, the incidents and measurements that justified each rule, each with its source and expiry. Read them when a rule's why is unclear; `/evolve` and `/capture-learnings` append to the ledger.

## Third-party skills

`grilling`, `tdd`, `code-review`, `writing-for-agents` and `domain-modeling` are adopted verbatim from Matt Pocock's skills repository under the MIT license; see `THIRD-PARTY-LICENSES.md` and the `CREDITS.md` beside each.

## Install

```bash
claude plugin marketplace add <this-repo-url>
claude plugin install bett3r-ai-workflow
# or for local dev, from your clone of this repo:
claude --plugin-dir ./plugins/bett3r-ai-workflow
```
