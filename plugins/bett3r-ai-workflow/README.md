# bett3r-ai-workflow

A Claude Code plugin that encodes a vertical-slice, dual-gated development flow. It ships the method and the roles, reading each host repo's own conventions (`.claude/rules/`, installed framework plugins, `.blueprint.config.json`) at runtime, so one flow fits any repo. Nothing lands on a single signal: a slice is done when its test passes **and** a verifier confirms the host's invariants, and a unit lands with its record committed beside the code.

## The flow

| Phase | Command | What it does |
|---|---|---|
| Start | `/bett3r-ai-workflow:start` | Cuts the branch, writes a fresh `.work/mode.yaml` with the base sha; runs no suite. |
| Design | `/bett3r-ai-workflow:design` | Grills the design to shared understanding, sharpening the domain model, then commits `design.md` (plus a clickable `map.json`/`map.html` for a fork-shaped design) in the folder `work-docs-path` names, `docs/prs/<id>/` by default. |
| Plan | `/bett3r-ai-workflow:plan` | Cuts the design into vertical slices, tracer bullet first, into `.work/slices.yaml`; `--publish` also creates Jira sub-tasks. |
| Build | `/bett3r-ai-workflow:build` | Per slice: executor → test gate → scope-check and verifier → commit; writes `decisions.md` and `build-summary.md`. |
| Verify | `/bett3r-ai-workflow:verify-build` | Runs the host gate, one whole-PR review, the dev checklist, ADRs, the concerns and the run measure, then opens the PR that links the record. |
| Capture | `/bett3r-ai-workflow:capture-learnings` | Routes each learning to the repo owning the artifact, filed with its filters and expiry. |
| Evolve | `/bett3r-ai-workflow:evolve` | In a plugin repo, turns `ai-learning` issues into reviewed PRs, pruning first. |

Fleet:

| Phase | Command | What it does |
|---|---|---|
| Multi | `/bett3r-ai-workflow:start-multi` | Drives N units through the flow unattended, one worktree each, parallel where safe. Every unit PR targets one integration branch, `int/<run-id>`; the run ends at N PRs, merging nothing. `/bett3r-ai-workflow:design-multi` does the same for N designs, batching the genuine forks into one sitting. |
| Land | `/bett3r-ai-workflow:merge-multi` | After review, in a fresh session: merges the unit PRs into the integration branch (conflicts resolved once), runs the gate once there, opens one integration PR. `--land` merges it. |

Utilities: `/bett3r-ai-workflow:commit` (logically grouped commits for ad-hoc work), `/bett3r-ai-workflow:run-report` (where a unit's time and tokens went, from the transcripts; `--aggregate` compares runs by plugin version), `/bett3r-ai-workflow:cpu-pool` (lift the compiler token pool before a compile-heavy fleet) and `/bett3r-ai-workflow:blueprint` (`connect` this checkout to its hosted Blueprint session and run the local listener your Asks ring; `disconnect`; `status`; `docs/adr/ADR-018`).

## The gate is the host repo's

The plugin never guesses what "green" means. A host repo declares its own gate as `.claude/gate.mjs` (or `.claude/gate.sh`), taking `--fast`, no argument (scoped: whole-repo structural checks, then only the suites and guards the diff touches) or `--full`, and printing one `GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE <detail>` line per step. `/verify-build` runs the scoped mode for a unit landing alone, or `--fast` for a fleet lane (`gateDeferred: true` in its `.work/lane.yaml`); `/merge-multi` runs the scoped mode once on the integration branch. The whole-repo run is CI's, or the user's on request; no flow step selects it. Every verdict names its blind spot: a scoped pass certifies the diff and its importers, not the tree. The `full-gate` skill holds the contract.

Opt-in lane speeds, `.work/lane.yaml` keys the provisioner writes from `/start-multi` flags, all off by default: `sliceCap: N` (`--slice-cap`; `/plan` cuts at most N slices, over N only for independent seams it names in `sliceCapException:`), `executorGate: fast` (`--executor-gate`; the executor runs its oracle, its slice's guards and the host's `--fast`; `/verify-build` still runs the scoped gate once on the final head, even under `gateDeferred: true`), `followUps: in-lane` (`--follow-ups`; `/verify-build` fixes the follow-ups inside a lane's own files before the PR, each recorded as a fork for the owner's review, and defers the rest to a `/merge-multi` sweep) and `--wave-prefactor` (one commit of shared scaffolding on the integration branch before a wave's lanes are cut, so sibling lanes fill shared points in rather than reshaping them; `/merge-multi` counts conflicts per wave merge). The per-slice verifier stays: a per-ticket cadence was measured and dropped (`LEDGER.md`).

## The record

Git is the system of record: one commit per slice, and one folder per work item under the work-docs root (`work-docs-path` resolves it) holding `design.md`, `decisions.md`, `concerns.md` and `build-summary.md`; the PR body links it. ADRs own the decisions that outlive a work item. The gitignored `.work/` holds disposable working state (`slices.yaml`, `mode.yaml`, a lane brief, learnings, handoffs).

## The plugin/project seam

Roles and method ship here; domain knowledge stays in the host repo and its framework plugins:

- the `verifier` reads `${CLAUDE_PROJECT_DIR}/.claude/rules/` for the host's invariants;
- the `executor` uses the framework skills the host provides (a PV3 repo installs `bett3r-pv3-ai-skills` beside this plugin);
- where a design graph fixes an artifact mechanically, `/design` ends in a scaffold commit made by the scaffolder the repo declares as `designTooling.scaffold` in `.blueprint.config.json`, gated by its `designTooling.typecheck`, skipped when either is undeclared; without a scaffold report, `/build` runs that scaffolder per slice.

## BLUEPRINT board mode

In a repo with a `.blueprint/` design layer, `/design` opens a second surface: decisions still go to the committed design, structure goes to a live board the user watches, through the `blueprint-mcp` tools. The `blueprint-design` skill carries the standing rules, `blueprint-pending` the rule for the hook line below, and `skills/blueprint-design/BOARD-SETUP.md` everything downstream of a board being present, opened only when the command's gates say so.

## Glossary

The design-end scaffold's terms; the why is `docs/adr/ADR-015` at the repo root.

- **Scaffold commit**: the one commit `/design` Step 4b makes on top of the docs commit, `chore(<id>): scaffold the agreed design`, holding everything derivable from the agreed design. It is made only when the repo's declared `designTooling.typecheck` is green; a fleet makes one, on `int/<run-id>`, in `/start-multi` step 0.
- **Scaffold report**: `scaffold.json`, committed beside `design.md` in the work-docs folder. It records what the scaffold commit wrote and what it left: `manifest[]`, `placed[]`, `held[]`, `stillOwed[]`, `asked[]`, `stale[]`, `edited[]`, the scenario tests, the input digests and the base sha. `/build` hands an executor the entries for its slice instead of running a scaffolder.
- **Untouched stub**: a scaffolded file whose `git hash-object` still equals the blob its manifest entry recorded. A re-run deletes untouched stubs before it scaffolds again, so one the design no longer derives is gone (`stale[]`); a stub that differs is edited, and is reported and never touched.
- **Held element**: a proposed node or edge whose comment thread has a remark that is neither resolved nor a reaction, and every edge touching a held node. It is not agreed yet, so the scaffold leaves it out and lists it under `held[]`.
- **Asked vs still-owed block**: the two kinds of scaffolder block. An asked block is a missing decision: it stops the scaffold commit and goes back to the owner. A still-owed block has code `no-template`, nothing to decide: it is reported as STILL OWED and the commit proceeds.
- **Topology vs registration fragment**: a fragment is a piece of code the scaffolder hands back for an existing file instead of writing it. Topology fragments (commands, events, their schemas, invariant wiring, and any edge stub: a fragment carrying `edge`, BP-267) are placed by an agent in `/design`, before the scaffold commit; every other fragment is registration or a test, and stays STILL OWED for the slice that wires it in `/build`.

## Hooks

Three, all in `hooks/hooks.json`, each one cheap check and gone where it does not apply:

| Hook | Fires | Does |
|---|---|---|
| `blueprint-pending.sh` | `UserPromptSubmit` | Prefixes the prompt with `blueprint: N pending (seq A→B)` while the user has unsynced board edits. Telemetry, never a trigger. |
| `blueprint-session-channel.sh` | `SessionStart` | Tells a session to open the board's summon channel when a board serves this repo and nobody holds it; in a checkout connected to a hosted session (a record in its git dir, `GIT_DIR` honoured), to start `blueprint listen` when nothing listens, plus a reminder when the branch moved. |
| `lane-git-guard.sh` | `PreToolUse` on `Bash` | In a checkout holding `.work/lane.yaml` (an unattended lane), blocks the git commands that discard or shelve the working tree. |

## It's working if

- `/start` finishes in seconds and runs no tests; `.work/mode.yaml` names the work item.
- Every slice in `/build` goes red before green, and lands as its own commit.
- `/verify-build` opens the PR with a `### Record` section linking four files and a `flow/concerns` status on the head commit.
- A fleet run ends with N open PRs against `int/<run-id>`, nothing merged.
- A gate verdict in a PR body names its mode and what it did not run.

## Propagation

`capture-learnings` files an improvement to a shared skill as an issue in the plugin that owns it; `evolve`, run in that plugin's repo, turns the issues into reviewed PRs. A merge reaches installs only with a version bump: the install is a version-keyed cache (`docs/adr/ADR-001`).

## Where the evidence lives

The artifacts carry rules; the evidence lives in two files nothing loads by default: `EVIDENCE.md`, the four facts about what counts as evidence, and `LEDGER.md`, the incidents and measurements behind each rule, each with its source and expiry. Read them when a rule's why is unclear; `/evolve` and `/capture-learnings` append to the ledger.

## Third-party skills

`grilling`, `writing-for-agents`, `domain-modeling` and `prototype` are Matt Pocock's, verbatim, MIT; see `THIRD-PARTY-LICENSES.md` and the `CREDITS.md` beside each.

## Install

```bash
claude plugin marketplace add <this-repo-url>
claude plugin install bett3r-ai-workflow
# local dev, from a clone:
claude --plugin-dir ./plugins/bett3r-ai-workflow
```
