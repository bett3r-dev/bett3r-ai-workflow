# The design ends in a scaffold commit, and the declared typecheck is its bar

Until ESAS-304, `/design` ended in documents only. The event-storming layer stayed in a gitignored
`.blueprint/design.json`, and the scaffolder ran per slice inside `/build`. Three things followed
from that. A scaffolder block, which is a design question, fired in an unattended lane after the
owner had left. Nothing proved that the agreed design compiles. And agreed scenarios and observations
had no committed path to tests and dashboards.

This record fixes where the scaffold happens, what it may contain, what makes it acceptable to
commit, what "agreed" means on the board it reads, and what happens to a scenario nobody tested. The
mechanics live in `plugins/bett3r-ai-workflow/scripts/scaffold-commit.py` (the launcher) and in
`commands/design.md` Step 4b; this file records why they are shaped the way they are.

## The design-end commit

**`/design` ends in one commit of everything derivable from the agreed design, made on top of its docs
commit.** Step 4b runs after `docs(<id>): design`. The launcher's `prepare` verb dry-runs the declared
scaffolder over the agreed design and the committed `map.json`, classifies its blocks, and writes the
mechanical half (create-only files plus guarded barrel lines). An agent then places the topology
fragments. The `finish` verb re-extracts, re-runs the scaffolder so units deferred on a placed fragment
get written, runs the declared typecheck and, when it is green, commits the files together with
`<path>/scaffold.json` as `chore(<id>): scaffold the agreed design`.

That report is what `/build` reads afterwards. With a report, `/build` runs no scaffolder; it hands
the executor the report's entries for the slice's `designs:`, and the executor's work is the
`TODO(scaffold)` markers and the registration fragments left STILL OWED. Without a report, the
per-slice scaffold step is the permanent fallback (`commands/build.md`, Step 3 item 0).

A block is classified when the owner is still present. A block whose code is `no-template` is
**still owed**: it is reported and the commit proceeds. Any other block is **asked**: it is a missing
decision, `prepare` ends `outcome=blocked reason=asked`, and the question goes back to the grill.

## Placement is topology only

**The placing agent writes topology fragments only (commands, events, their schemas and invariant
wiring), and never registration.** The launcher's worklist is every fragment whose artifact is
`command`, `event` or `invariant` (`TOPOLOGY`, `scaffold-commit.py:117`); every other fragment is
registration or a test and stays STILL OWED for `/build`. This is ESAS-289-F3 option B, "mechanical +
placement", chosen by the owner because it is the only option that delivers one commit of everything
agreed when a design adds events, which most designs do. Option A, mechanical only, is the floor B
builds on. Leaving the commit red was rejected because it breaks the owner's stated bar, that the
scaffold commit must build.

## The bar is the declared typecheck

**The bar is the typecheck the host declares as `designTooling.typecheck`, not its build.** A
scaffold commit is made only when that command exits green; a red typecheck restores the tracked edits,
removes the new paths, and ends `gate-red`, and the docs commit stands. This absorbs ESAS-289's ask,
"a scaffold commit's bar is the host's declared typecheck, not build". In teselly the build is swc and
compiles output a typecheck rejects, so "it builds" discriminates nothing there.

Both `designTooling.scaffold` and `designTooling.typecheck` are required, with no framework default.
Either one undeclared is `outcome=skipped reason=undeclared-designTooling.<key>`, and nothing runs
(`scaffold-commit.py:215-218`). A host opts in by declaring both: blueprint declares
`yarn typecheck` (ESAS-304) and teselly `yarn gate --fast` (ESAS-313). Kixie's is open: its
per-service typecheck excludes emitted specs.

**On a red base, green means no error outside the base's error set.** When the typecheck is red
after placement, `finish` runs it again over HEAD (the docs commit) with its edits set aside, and puts
them back. It is green only when HEAD is red too and every `error TS<n>` line now, its location aside,
is one HEAD already printed; each other one is printed as `new-error:` and the run ends
`gate-red reason=typecheck-red` (`scaffold-commit.py`, `judge_red`). It is fail-safe: a red run with no
such line to read, on either side, is judged by its exit code, so it stays red. A green on a red base
ends `outcome=ok typecheck=base-red`, and the report's `typecheck{}` records both exits and error
counts. This is the shape ESAS-300's kixie oracle needs: its service builds are red at base for an
environmental reason, so it compares error sets, never exit codes.

Census and ratchet guards that glob the tree are not part of a typecheck. They are the named blind spot
of this bar, and the next scoped gate is what runs them.

## Agreed means no open comment

**Agreed means proposed and coherent, minus any element with an unresolved comment anchored on it.**
A proposed node or edge is held when its comment thread has a remark that is neither resolved nor a
reaction; a reply rolls up to the element its root is anchored on, and every edge touching a held node
is held too (`scaffold-commit.py`, the `prepare` docstring and line 401). The scaffolder reads a copy of
the design without the held elements, and the report lists them under `held[]`.

This is ESAS-304-F1 option C. It expresses "not agreed yet" with state the design layer already has,
and needs no new blueprint work. Treating everything proposed as agreed (today's planner semantics) and
adding an explicit Accept op to the design layer were both rejected. Accept remains the long-term answer
to file if a team wants an explicit gesture: for a team that never comments, this rule holds nothing
back.

## A fleet makes one scaffold commit

**A fleet makes one scaffold commit, on `int/<run-id>`, in `/start-multi` step 0.** It runs in a clean
worktree on the integration branch, before the base gate, with one `--map` per unit projection, and
each lane brief then carries the report's path as `scaffoldReport:`. A fleet lane never scaffolds
(`commands/design.md`, Step 4b). `/design-multi` Step 3.5 dry-runs the same scaffolder once for the
whole fleet before the sitting, so its asked blocks become sitting forks while the owner is present.

This is ESAS-304-F3 option B: the only option where blocks surface while the owner is present and "one
commit of everything agreed" survives a fleet. Per-lane scaffolding from each lane's snapshot, and a
single-unit-only v1, were rejected.

## The landing rule

**An agreed scenario with no implemented test warns on a fleet unit's PR and blocks at the integrated
tree.** The integrated tree is `/merge-multi` for a fleet, or `/verify-build` for a unit landing alone.
`scaffold-commit census` reads the report by scenario id, and a pending `.todo(` test counts as none. An
ESAS-296 hold gets its own line and is never reported as missing a test. The escape is a human strike,
or writing the test.

This is ESAS-304-F4 option C. An agreed example is a commitment and should block somewhere; the
integrated tree is the first place every scenario's owner is present, and blocking one unit for a
sibling's scenario is the wrong place. The verifier's pending rule governs a slice that delivers the
test file; this landing rule governs a scenario with no test anywhere.

## This overrides the scaffold CLIs' stance

**This overrides the scaffold CLIs' "slice-scoped by design".** The PV3 scaffolder's header once read
"Slice-scoped by design" and called a whole-design run "useful for a dry-run overview and rarely what
you want to write". A whole-design run, with no `--nodes`, is now the end-of-design use, and `--nodes`
serves the per-slice fallback. ESAS-289 rewrote that header in PV3, and the shared
`@bett3r-dev/blueprint-scaffold-core` CLI header says the same: without `--nodes` "the run covers the
whole design delta, which is what the end of a design session asks for".

The old stance's worry was a large commit of unreachable stubs that stops the tracer bullet being a
tracer bullet. This record accepts that commit for what the owner agreed, on two conditions: it
typechecks, and it holds nothing still questioned on the board.

## What this does not decide

* **Test generation, placeholders, new aggregates and dashboards** belong to their own tickets
  (ESAS-298, 299, 302 and 303; ESAS-289 and 300; ESAS-292; ESAS-306).
* **Which kixie command typechecks emitted specs** is open; until one is declared, a kixie scaffold
  commit certifies nothing about specs.
* **Renames.** A placed event, once extracted, turns a later rename into a modify; that is reported,
  not planned for.

## Status

Accepted (ESAS-304). Extends
[ADR-004](./ADR-004-a-step-reports-a-line-not-an-exit-code.md): the launcher ends every run in one
`SCAFFOLD-COMMIT:v1` line, read instead of its exit code. Extends
[ADR-005](./ADR-005-a-work-items-record-is-committed-beside-the-code-not-only-in-the-pr-body.md):
`scaffold.json` is committed beside the design in the same work-docs folder.
