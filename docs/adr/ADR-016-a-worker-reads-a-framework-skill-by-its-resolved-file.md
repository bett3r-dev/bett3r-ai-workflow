# A worker reads a framework skill by its resolved file; only the orchestrator resolves it

Before BP-196, the executor's rule 3 told it to follow "the matching skill the host repo's framework
plugin surfaces". The executor holds no Skill tool, and neither does the verifier, whose checklist
step promised the framework's Final Checklist. In a fleet, `/build` itself runs in `step-lane-file`,
which holds no Skill tool either (`agents/step-lane-file.md`, its `description:` and `tools:`), so
even the orchestrator never read the framework's bridge. Framework code was written from generic
instinct, and nothing in the tree showed it.

This record fixes how a worker reaches the framework skill a host declares, who resolves it, and what
happens on a machine where it does not resolve. The mechanics live in `bin/skill-path`,
`commands/build.md` (Step 1 item 5 and Step 3 item 0) and `commands/start-multi.md` (step 0); this
file records why they are shaped the way they are.

## Only the orchestrator resolves it

**The framework skill is the host's declared `designTooling.scaffoldSkill`, resolved once per run to a
file, and only the orchestrator resolves it.** `/build` Step 1 item 5 runs
`skill-path --repo <checkout root> <scaffoldSkill>` and reads its last line, `SKILL-PATH:v1`, not its
exit code (ADR-004). An `outcome=ok` gives `file=` and `root=`, and every executor and verifier
dispatch of the run carries them as one line: `framework skill: <file> (plugin root <root>)`. A host
that declares nothing gets `framework skill: none declared`, and no plugin cache is searched.

**`skill-path` and `installed_plugins.json` are the single resolution.** The plugin cache keeps every
version it ever installed, each with its own copy of a skill, and only the manifest names the live
one, so the cache is never globbed. `skill-path` reads the manifest the way `bin/check-skill-shadows`
does. A worker routes from the file it was handed: a relative link resolves beside it, a
same-plugin name under `<root>/skills/`, `${CLAUDE_PLUGIN_ROOT}` is `<root>`. Only a qualified name
the bridge routes to in another plugin goes back through `skill-path`. The declared skill itself is
resolved once per `/build` run (`/start-multi` step 0 also resolves it, earlier and per host repo,
only to refuse), and never by a worker.

This extends ADR-012's posture, a file and not a skill where the reader holds no Skill tool, from
`step-lane-file` to the executor and the verifier.

**Rejected: the Skill tool on the executor and the verifier.** It pays the skill listing ADR-012
measured (about 10.5k tokens in every context that holds the tool) in the longest-lived worker, on
every turn. It reverses the pin that keeps `Skill` and `SlashCommand` out of both workers' `tools:`.
And it would still not reach a lane's orchestrator, which runs in `step-lane-file`. Also rejected:
pasting the skill's text into each dispatch, which grows the orchestrator's context per slice, and
having each executor resolve the skill itself, which duplicates the resolution in every worker.

## Refuse before start

**Refuse before start.** A declared framework skill that does not resolve is a fact about the
machine, not about any slice, so it is found once and before any compute is spent. `/build` Step 1
item 5 ends the run `blocked-on` before Step 2, so before any executor is dispatched. `/start-multi`
runs the same check in step 0, once per distinct host repo, before any worktree is cut. Both name the
plugin, the `reason=`, the install command `claude plugin install <plugin>`, and, for
`reason=not-installed`, the possible cause below. This is BP-196-F1, option refuse-before-start,
decided by the owner.

The refusal has **no escape hatch**: no flag or key lets a run carry on past it. Rejected: carry on
and record the missing skill as each slice's deviation, which commits framework code written blind
and leaves it to be found in the PR. Rejected: block each slice that touches framework code, which
pays a fleet's provisioning and then stops lane by lane.

**The `--plugin-dir` blind spot.** A plugin run from a source checkout with `--plugin-dir` is not in
`installed_plugins.json`, so `skill-path` reads it `not-installed` although the session loaded the
skill. `bin/check-skill-shadows` reads the same manifest and says a source checkout is "a different
corpus" from the installed tree it judges. The refusal message names this cause, and
the remedy is still installing the plugin.

## Scope precedence awaits the owner's confirmation

`skill-path` ranks a `local` entry over a `project` entry over a `user` or `managed` one, and two
applicable entries at the same level are `reason=ambiguous`. Ticket BP-196's design (D2) asks that
a project entry for this repo beat a user entry. A reading of the Claude Code 2.1.300 binary
suggests it may load the first existing entry instead. If so, a machine holding a user install of
version A and a project install of version B could see `skill-path` name B while the session loads
A. The harm is version skew between the skill the worker reads and the one a session would load. The
owner is to confirm which `installPath` loads in that case; if it is A, the level order flips. Until
then the design governs (decisions.md D3 of BP-196).

## What this does not decide

* **Dispatch sites outside `/build` and `/verify-build`** (the wave prefactor and backfill verifier in
  `/start-multi`, the follow-up sweep in `/merge-multi`, `/design` Step 4b) carry no
  `framework skill:` line; they are named in BP-196's decisions.md D4 for the owner.
* **The hosted `/implement` routine** and the hosted scaffold step are untouched.

## Status

Accepted (BP-196). Extends
[ADR-012](./ADR-012-artifacts-carry-rules-the-ledger-carries-evidence.md): a worker without the Skill
tool reads a skill by its file. Extends
[ADR-004](./ADR-004-a-step-reports-a-line-not-an-exit-code.md): `skill-path` ends in one
`SKILL-PATH:v1` line, read instead of its exit code.
