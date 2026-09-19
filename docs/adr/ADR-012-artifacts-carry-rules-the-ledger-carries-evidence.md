# Artifacts carry rules, the ledger carries evidence — and tests pin mechanisms, not wording

By September 2026 the plugin's commands, agents and skills had grown to roughly 98,000 words of
prompt text. `build.md` alone was 9,300 words (about 20,000 tokens), re-read on every one of the
40 to 700 turns a `/build` step-lane takes. A three-day fleet window measured 3.8 billion input
tokens; the plugin's own artifacts were 28 to 39 percent of the long-lived roles' bills, and the
54 agents whose context passed 150k tokens were 56 percent of all spend at 65 times the cost of an
agent that stayed under it.

The words were not idle. Every hard-won fact had been absorbed into the artifact it protected,
usually with the incident that taught it: *"a lane once issued `sleep 550` 530 times"*, *"one
green suite pinned a credit note onto the invoice's stream"*, *"41% of 966 fix rounds were
oracle-wrong"*. And three of the repo's own gates pinned that wording: `check-needles.py` asserted
145 literal sentences somewhere in the corpus, `test-flow-seams.sh` asserted about 150 exact
sentences in named files, and `test-merge-multi-concerns.sh` pinned every sentence of
`merge-multi.md` as a closed set. A fact, once written, could not be shortened without a red gate.
That ratchet is what turned the prompts into sediment.

**We separated the two things the prose was doing.** An artifact carries the *rule*: what the
agent does, in order, each step ending on a criterion it can check, plus the reference every run
needs. The *evidence* for a rule — the incident, the measurement, the date, the command that
produced the figure — lives in `plugins/bett3r-ai-workflow/LEDGER.md`, which no agent loads. Each
ledger entry names the rule it supports, its original location, the evidence verbatim, when it was
recorded, and the condition that retires it.

## Why a ledger and not a shorter sentence

The justification for a rule earns its place in a human's document and nowhere else. Matt
Pocock's `writing-for-agents` names the failure: material the model already obeys by default, or
material that explains rather than instructs, spends context on every turn to change nothing. His
own skills keep rules in `SKILL.md`, the reason for each change in a changelog, and the field
reports in docs the agent never reads. That is the split we adopted, with one addition his repo
does not need: because `check-needles.py` asserts presence anywhere under `plugins/**/*.md`, the
ledger carries the original sentence for every needle whose wording the rewrite changed. The gate
still proves a fact survived; it no longer dictates where or how the fact is spoken.

## Tests pin mechanisms

A wording pin is a mutation guard against rewording, and rewording is exactly what thinning is.
The oracles now assert what a rewrite must not break and nothing else:

* every fenced block a test parses or executes stays a fenced block with the same first line, in
  the file the design assigns (the `LANE-STEP:v1` spec block in `unit-lane.md`, the `mode.yaml`
  block in `start.md`, the lane-brief key set in `provisioner.md`, the `BOARD-GATE:v1` and preflight
  blocks, the D-entry and `build-summary` grammar now in `reference/build-record.md`, the concern
  block, the `verifyBuild:` block, the PR template, `merge-multi`'s executed 1b block);
* every verdict-line grammar, file shape and host literal in the dependency survey's must-keep list,
  including the esas literals that moved into prose with the rewrite (`capabilities.verbFamilies`,
  `boardKinds`, `LINKED_WORKTREE` in `design-map/FLEET.md`);
* every *absence* guard (the retired second lane-brief filename, `.work/design.md`, a hardcoded `docs/prs`, a
  flow-selected `--full`, an experience-layer name in the base plugin, a rogue writer of `map.json`,
  whose scan now covers `reference/` as well as the entrypoints);
* one short literal per rule, in the rule's single home, chosen to survive rewording of everything
  around it — instead of the same sentence in five files. Where the home is another file, the
  test pins the **pointer** rather than a restatement: `grill`'s map subsection is pinned on
  `Call the Skill tool with "design-map"`, `design-map`'s wake on `` `esas-design`'s two
  invariants ``, the fleet companion on `[FLEET.md](./FLEET.md)`. A second copy of the tokens
  would be a second place for them to drift;
* the frontmatter descriptions, which the listing pays for on every turn: each carries its trigger
  words and the test asserts the whole value stays inside 200 characters, so a trigger cannot be
  bought with an exemption from the cap;
* the **Step protocol** section byte-identical across `design.md`, `plan.md`, `build.md` and
  `verify-build.md`, which is how a meaning stated once is kept in step where it must be inlined.

A wording pin is dropped only when the rule it protected has a mechanism pin (the `render` verb
refusing an ungrounded map is executed against a fixture, so no sentence about "posting before
grounding" is asserted) or when its content was a measurement that belongs to the ledger ("This
is not measured"). A rule with neither is not silently retired: it is listed in the rewrite's
harness report for its owner to home or to retire on purpose.

`test-merge-multi-concerns.sh` keeps its closed-set detector and was re-baselined; that gate's
job is to make every future change to that file deliberate, and it still does.

## Structural rules that came with it

Two findings from the measurement were not about words. The 53 unit-lanes that ran command bodies
inline peaked at a median of 203k tokens; the 14 that dispatched a fresh step-lane per step peaked
at 70k with the same agent prompt. So `unit-lane` lost the `Skill` and `SlashCommand` tools: it can
only dispatch. And 19 percent of the window's tokens were turns that waited — foreground `date`
loops, `echo tick` spins, background `sleep` timers each firing a wake-up at full context, and 131
turns after a lane had already printed its verdict. So waiting is one blocking call, stated once
per waiting artifact, and printing the verdict line ends the run.

Mechanical rules moved out of prose where a hook can hold them: `hooks/lane-git-guard.sh` blocks
`git stash` (except `create` and `list`), `reset --hard`, `checkout --`, `checkout .`, `restore`
and `clean -f` when `.work/lane.yaml` marks the session unattended. It replaces a prohibition that
five files repeated at `c75ba88` (`executor`, `provisioner`, `scope-check`, `/commit`,
`inline-fix`); each now carries one sentence naming the sanctioned alternative, `git stash create`
followed by `git diff <object>`.

Two more moves followed the first fleet-cost review. The skill listing (about 10.5k tokens in
every context that holds the Skill tool, most of it the host's other plugins) is paid by a
step-lane on every turn only so that it can load its one command. `/start` and `/build` call no
skill, so they now run in `step-lane-file`, a variant with no `Skill` or `SlashCommand` tool that
reads `commands/<step>.md` through the `bin/` directory on `PATH` and follows it; `/design`, `/plan`
and `/verify-build`, whose bodies call skills, stay in `step-lane`. And `/verify-build` states its
two-axis review inline rather than calling Pocock's `code-review`: that skill stops to ask for a
tracker document and a setup command that do not exist in a fleet host, and a prose override of
a stop is the variance shape this whole decision removes. His `code-review`, `tdd` and
`codebase-design` were adopted and then dropped again the same day: nothing in the flow calls
them (the executor cannot follow a pointer, so it carries its own RED→GREEN rules), the owner runs
no attended TDD sessions, and an unreferenced skill is pure listing cost. `grilling`
keeps his body but carries this plugin's description, so a user's "grill me" reaches `grill`,
the layer with the flow's fork shape, rather than the primitive under it.

## Companions

Reference that only some runs reach leaves the command or skill body and becomes a companion file,
reached by a pointer that names the condition under which to open it: `reference/build-pool.md`
(a worktree pool is in use), `reference/build-record.md` (writing the committed record),
`reference/start-multi-serial.md` (`--serial`), `skills/design-map/FLEET.md` (a `/design-multi`
sitting, a `design-lane`, or a live board), beside the existing `esas-design/BOARD-SETUP.md` and
`PREFLIGHT.md`. Command companions live under `reference/`, not `commands/`: `validate-plugins.py`
treats every `commands/*.md` as a loadable command and refuses one without frontmatter, and
`check-eval-coverage.py` counts each as an entrypoint, so a companion placed there would be a
command the model could run as a step. A companion is a split, so `check-eval-coverage.py` refuses
it until a `guards_split` scenario opens it; and the single-writer scan over `map.json` covers
`reference/`, so a companion cannot become the rogue writer the entrypoints are forbidden to be.

## Budgets

The budgets derive from the measured per-role room under a 150k peak: a step-lane's plugin-owned
prefix (agent prompt plus command body plus any skill it loads) stays under about 23,000 tokens,
which at 2.15 tokens per word of this plugin's markdown makes `build.md` at most 4,600 words and
every other command body smaller. A file over its ceiling is a defect; a file over its target
carries a one-line reason in the PR that moved it. Counted with `wc -w`, frontmatter included.

| Artifact | Target | Ceiling |
|---|---:|---:|
| `commands/start.md` | 600 | 900 |
| `commands/design.md` | 2,000 | 3,700 |
| `commands/plan.md` | 1,500 | 2,300 |
| `commands/build.md` | 3,000 | 4,600 |
| `reference/build-pool.md` / `build-record.md` | 800 / 900 | 800 / 900 |
| `commands/verify-build.md` | 2,500 | 3,800 (raised from 3,700 when the whole-PR review moved inline; it replaces a 1,064-word skill load) |
| `commands/start-multi.md` (+ `reference/start-multi-serial.md` ≤ 600) | 2,500 | 3,300 |
| `commands/design-multi.md` | 2,500 | 3,700 |
| `commands/merge-multi.md` | 1,800 | 2,300 |
| `commands/capture-learnings.md`, `evolve.md` | 800, 900 | 1,200 |
| `commands/commit.md`, `run-report.md` | 350, 700 | 500, 900 |
| `agents/unit-lane.md` | 1,500 | 2,800 |
| `agents/step-lane.md`, `step-lane-file.md` | 450, 550 | 900 each |
| `agents/provisioner.md`, `pool-provisioner.md` | 1,200, 400 | 1,900, 900 |
| `agents/executor.md` | 1,500 | 2,300 |
| `agents/verifier.md` | 1,800 | 2,300 |
| `agents/scope-check.md`, `test-runner.md` | 400 | 900 |
| `agents/design-lane.md`, `tracker-writer.md` | 1,200, 700 | 2,300, 900 |
| `skills/grill` (delta over `grilling`) | 600 | 900 |
| `skills/domain-modeling/SKILL.md` | 700 | 900 |
| `skills/vertical-slicing` | 1,200 | 1,900 |
| `skills/full-gate` | 900 | 1,900 |
| `skills/design-map/SKILL.md` (+ `FLEET.md` ≤ 1,200) | 2,000 | 2,500 |
| `skills/esas-design/SKILL.md` (+ `BOARD-SETUP.md` ≤ 900) | 1,500 | 1,900 |
| every other skill | 200 to 600 | 900 |
| `EVIDENCE.md`, `CONTEXT-PROVIDERS.md`, `README.md` | 1,200, 600, 1,200 | 1,500, 800, 1,500 |
| every frontmatter `description` | | 200 characters |

Pocock's adopted files carry no budget of ours; they are his as shipped.

## Third-party skills

`grilling`, `writing-for-agents` and `domain-modeling` are Matt Pocock's
files (github.com/mattpocock/skills, MIT), copied verbatim with the notice in
`THIRD-PARTY-LICENSES.md` and a `CREDITS.md` beside each. In-house material that layers on them
is a separate skill (`grill`) or a trailing section (`domain-modeling` § In this flow), never an
edit to his text, so a future upstream refresh is a copy.

## What this does not decide

Whether the needles gate should eventually assert each ledger entry's `rule:` has a live home in an
artifact (a `check-ledger-homes` that replaces wording needles with a fact-to-home map) is left
open; today the ledger records the home in prose and the reviewer checks it. The remote-ai-agents
driven venue's stale `.work/design.md` handoff, ADR-010 and ADR-011 are unchanged by this decision.
