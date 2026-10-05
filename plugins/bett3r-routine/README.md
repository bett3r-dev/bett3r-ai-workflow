# bett3r-routine

The unattended implementation lane a **Blueprint routine** runs when a ticket enters a board's
implementation column. It sits beside `bett3r-ai-workflow` and calls into it; it replaces none of it.
The hand-run flow (`/start` → `/design` → `/plan` → `/build` → `/verify-build`) is untouched.

## Why a separate lane

By the time Blueprint fires the routine, the design is already agreed: the board session wrote
`<docsRoot>/<KEY>/blueprint.md` (problem, solution, resolved decision tree, ready scenarios,
implementation and testing decisions), grounded against the code. Running `/design` on top of it
re-does that work and, worse, cannot write: the folder already holds Blueprint's files and no
`design.md` with an ownership header, so `work-docs-path --owner-branch` reads it `unowned` and
`/design` correctly refuses (TV2-10, 2026-10-05). So the routine skips design entirely.

## Commands

| Command | Does | Replaces, for the routine |
|---|---|---|
| `/implement <dispatch text>` | The entry point. Cuts or resumes `claude/<ticket branch>`, writes the brief, runs the three steps below, and ends with the commit trailer Blueprint reads (`done` or `needs-human`). | `/start`, and the routine prompt's branch and trailer rules |
| `/routine-plan` | Slices `blueprint.md` unattended into `.work/slices.yaml`, every ready scenario copied into one slice. | `/design` + `/plan` |
| *(core)* `/build` | Unchanged. Reads `slices.yaml` and Blueprint's `scaffold.json`. | — |
| `/routine-verify` | Scoped gate, scaffold census, standards + spec review, ripple sweeps; commits `verification.md` beside the design. No PR. | `/verify-build` |

Requires `bett3r-ai-workflow` installed alongside it: its `/build`, agents (`executor`, `verifier`,
`test-runner`, `scope-check`), skills (`vertical-slicing`, `full-gate`) and `bin/` scripts
(`work-docs-path`, `design-map`, `scaffold-commit`, `concerns-check`, `lane-step-record`).

## Install in a routine environment

The routine's cloud-environment setup script copies plugins flat into `~/.claude/` (no
marketplace). Copy `bett3r-ai-workflow` first, then this plugin's `commands/` on top; the command
names are chosen not to collide with core's. See `remote-ai-agents/deploy/blueprint-routine/`.
