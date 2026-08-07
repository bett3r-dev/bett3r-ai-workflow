---
description: Grill the design to shared understanding while sharpening the domain model, then write a reviewable design doc. Composes the grill + domain-modeling skills.
---

# /design — grill + model the design

Resolve the design through a relentless interview, sharpening the ubiquitous language as you go, and leave a **reviewable** design doc plus durable glossary/ADR updates. This is "grill-with-docs": the `grill` skill drives the interview, the `domain-modeling` skill maintains the model.

## Argument: $ARGUMENTS
The thing to design (a ticket id, a feature description, or "the active work").

---

## Step 0 — Board mode (skip unless this repo has a `.esas/`)

Where ESAS is set up, this interview has a second surface: the decisions land in `.work/design.md` as always, and the **structure** lands on a live board the user watches on another screen while you talk. Board mode is off by default and costs one command to rule out.

Two gates decide it, and they ask different questions. **Capability asks whether a board is possible; relevance asks whether it is warranted.** Both must say yes — board mode is **on** only when they both do, and the `grill` skill's canvas subsection, which defers to "`/design` has put board mode on" rather than restating either half, reads it as that conjunction. (The `esas-design` skill is scoped differently on purpose: its standing rules fire wherever the `mcp__esas__*` tools exist, so "look at the board" still syncs correctly in a session where board mode was never armed.) Relevance is first, and it is cheaper than one command: it costs none.

### Gate 1 — relevance: what the decision tree names

**Board mode is armed by what the drafted decision tree names.** Draft the tree first — the `grill` skill opens the interview with it — then read it back: does any track name **a command, an event, an aggregate, a policy, a read model, or a coupling** between them? One is enough. If none does, the design is not about structure, and a board would render nothing but the questions' own text: a canvas of stickies nobody asked for, on a second screen the user now has to close.

So Step 0 is *settled* before the first proposal, not *finished* before Step 1. Ground the interview, draft the tree, answer this gate — and only on a yes go on to the preflight below. It keeps the number 0 because board mode has to be decided before anything is written, not because it is the first thing that happens.

**Relevance runs before the preflight, never after it.** The order is the mechanism, not a preference: the preflight prints verdicts and the table under it turns them into things you say out loud — *run the extractor*, *here is the launch line*, *another repo holds the port*. Run it first and the silent path has already spoken by the time the gate answers no. Which is also why relevance is **not** a preflight key and must never become one: a shell block cannot read a decision tree, and a key it printed would have to be answered before there was anything to answer about. The cost of this order is real and it lands on one path — a repo that needs the `esas-mcp` restart now hits that stop after the grounding rather than before it, and under the mid-interview fallback later still, after forks the user has already answered. All of it is re-done in the new session, which is why the restart copy below names what it costs instead of promising the stop is free. That is still the cheaper half of the trade; the alternative is every design in the repo opening with board talk, structural or not.

**On a no, say nothing at all about boards.** Not a shorter version, not a footnote — nothing. No offer, no "this repo has ESAS set up but we won't need it", no mention that a gate was consulted. Run Steps 1–4 exactly as written. A mention is not free: it hands the user a second surface to have an opinion about in a design where the answer is already known.

**The fallback is to arm mid-interview at the first artifact-touching fork.** This gate is answered at the moment of least knowledge, so a design that opens on config and turns structural at fork 4 must not be locked out by its opening. Re-ask it whenever a new fork names an artifact; on a yes, run the preflight then and pick board mode up from there. A late board loses nothing — it is a projection, and it catches up the moment it opens.

**When it is close, unsure means silent.** This gate asks for a judgement, and nothing in this repo's suite can tell a right call from a wrong one — the only thing that makes prose safe here is which way it fails, so it is stated as a rule rather than left to taste. A false yes costs the user a screen they did not want and a paragraph of board talk in a design with no structure in it; a false no costs a board that arrives one fork later through the fallback above. Those are not the same size. And do not resolve the doubt by asking: *"should I open a board?"* is exactly the output this gate exists to suppress.

**Frontend, infrastructure, PV3-internal plumbing and work outside the modelled subdomains are the usual no's — as worked examples, never as a rule.** Classify by kind of work and you are wrong precisely at the edges: `ui` is a node type in the extractor's own graph, and teselly's `.esas.config.json` carries a `webAppPath`, so "frontend" is not outside the model by definition. Read the tree in front of you, not the label on the ticket.

### Gate 2 — capability: what is actually on disk

Run the preflight from the repo root. It reports facts and decides nothing:

```sh
# --- esas preflight ---
# Facts about this checkout's design layer. Decides nothing; the table below
# does that. Every `key: value` line it can print has a row there, and
# scripts/test-esas-design.sh asserts both halves of that.
#
# No `exit` anywhere and every variable prefixed: this runs in whatever shell
# the tool call lands in, and it has no business ending it or renaming
# somebody's `path`.
esas_port=${ESAS_BOARD_PORT:-3727}

if [ ! -d .esas ]; then
  printf 'esas_dir: absent\n'
else
  printf 'esas_dir: present\n'
  if [ -f .esas/graph.json ];  then printf 'graph: present\n';  else printf 'graph: absent\n';  fi
  if [ -f .esas/design.json ]; then printf 'design: present\n'; else printf 'design: absent\n'; fi
  if [ -f .esas/ops.jsonl ];   then printf 'ops: present\n';    else printf 'ops: absent\n';    fi

  if [ ! -f .mcp.json ]; then
    printf 'mcp: absent\n'
  else
    esas_registered=no
    while IFS= read -r esas_line || [ -n "$esas_line" ]; do
      case $esas_line in *esas-mcp/bin/esas-mcp.mjs*) esas_registered=yes ;; esac
    done < .mcp.json
    if [ "$esas_registered" = yes ]
      then printf 'mcp: registered\n'
      else printf 'mcp: unregistered\n'
    fi
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'board: unknown\n'
  else
    esas_body=$( curl -fs --max-time 2 "http://127.0.0.1:$esas_port/api/esas/status" 2>/dev/null )
    # Which checkout the board serves is not a question about how it spells the
    # path or serialises the answer, so both spellings of this directory are
    # tried (the board resolves symlinks, a shell does not), spaced and
    # compact. A false `other-repo` sends the user hunting for a rival board
    # that is not there, which is worse than the ambiguity it would report.
    esas_serving=no
    for esas_path in "$PWD" "$( pwd -P )"; do
      case $esas_body in
        *"\"repoPath\":\"$esas_path\""*|*"\"repoPath\": \"$esas_path\""*) esas_serving=yes ;;
      esac
    done
    if [ -z "$esas_body" ]; then
      printf 'board: off\n'
    elif [ "$esas_serving" = yes ]; then
      printf 'board: serving\n';    printf '  status: %s\n' "$esas_body"
    else
      printf 'board: other-repo\n'; printf '  status: %s\n' "$esas_body"
    fi
  fi
fi
# --- end esas preflight ---
```

### What each verdict means

| report | what it means | what you do |
|---|---|---|
| `esas_dir: absent` | No design layer here — a fleet worktree, or a repo the extractor has never run in. | **Board mode off.** Run Steps 1–4 exactly as written. Never create `.esas/` to switch it on; the directory is the marker of "this checkout designs". |
| `esas_dir: present`, `graph: absent` | `.esas/` exists but the extractor has not produced a graph. | Board mode off until it has. Ask the user to run the repo's extractor (`yarn esas` in teselly), then re-run the preflight. Proposals against a graph that isn't there have nothing to attach to. |
| `esas_dir: present`, `graph: present` | Reality is on disk. | Board mode is possible — continue down this table. |
| `design: absent`, `ops: absent` | No design session has started here. | The normal, clean start. See *Seeding* below — there is nothing to create. |
| `design: present` or `ops: present` | A design layer is already on disk. | It is either the unit of work you are resuming or the residue of one that shipped. **Ask whose session it is** — see *Seeding*. |
| `mcp: registered` | The entry is in `.mcp.json`. That is not the same as the server running. | Call the `status` tool now — see *Registering* for the three ways this answers. |
| `mcp: unregistered` / `mcp: absent` | This repo's `.mcp.json` does not register the server. That is all the preflight can see — it reads the project file only. | Write the entry, then **stop** — see *Registering* — **unless the `mcp__esas__*` tools are already available in this session**, which means it is registered elsewhere (a user-scoped `~/.claude.json`). Then skip the write: it would cost a needless restart and put a duplicate entry in a git-tracked file. |
| `board: off` | Nothing is serving this repo on :3727. | The normal state before the user launches it. **Carry on** — the offer comes later, when the first batch of questions is ready, not here; see *The board*. |
| `board: serving` | A board is up on this checkout. | Compare its `lastSeq` with the `status` tool's. Same number ⇒ the link is live. |
| `board: other-repo` | Something holds :3727 serving a *different* checkout, and the `status:` line under the verdict says which. | **Name the repo that holds it** — the `repoPath` in the `status:` line is the project root that board serves — and say so before the first proposal: until it is closed this repo's board cannot claim the port (`strictPort` never drifts), and the screen the user is watching will never move. Naming it is the difference between a thing the user can close and a board they may not remember starting. Then carry on. |
| `board: unknown` | No `curl` here, so the board was not probed at all. | Say it was not verified rather than reporting it down, and carry on. |

### Registering `esas-mcp` — and the restart that makes it real

When the preflight says `mcp: registered`, call the `status` tool. It answers in exactly three ways:

- **It returns `{repoPath, gitSha, lastSeq, cursorSeq, pendingByAuthor, lockState, warnings}`** — board mode is live. Note `lastSeq` for the board comparison, and read `warnings` out loud if there are any: they mean another session is designing in this checkout, or that a writer is on a different build than yours.
- **There is no such tool in this session** — two causes, and they look identical from here. Either the entry was added by an earlier run and the session was never restarted: do the restart step below, and do **not** write the entry again. Or the server failed to spawn, in which case restarting changes nothing and the second attempt is the diagnosis: **still missing after a restart ⇒ the server failed to spawn** — check the entry's path resolves, and that the esas checkout has its dependencies installed (`bin/esas-mcp.mjs` runs the sources through `tsx`, so a fresh clone with no install dies at boot). Claude Code logs the spawn failure; read it rather than restarting a third time.
- **It returns `ESAS_DIR_MISSING`** — the server is running and answering about *this* checkout, which simply has no `.esas/`. In a fleet worktree that is **the correct answer, not a fault to fix** (see the skill's main-checkout rule). In the main checkout it means the extractor has not run here yet: `yarn esas`, then re-check. Do not add `ESAS_REPO_PATH` to point it elsewhere — that is how a worktree ends up writing into another checkout's design layer.

When the preflight says `mcp: unregistered` or `mcp: absent` — and the `mcp__esas__*` tools are not already in this session from a user-scoped registration — add the entry. **Add the one key to `mcpServers`** with an edit, not a read-modify-write of the whole file: rewriting it reformats every other server and turns a one-key diff into a whole-file one.

```jsonc
"esas": {
  "type": "stdio",
  "command": "node",
  "args": [ "<abs path to the esas checkout>/packages/esas-mcp/bin/esas-mcp.mjs" ]
}
```

Resolve the esas checkout from a link the host repo already has (teselly's `package.json` carries `"sticky-notes-board": "link:../esas/packages/sticky-notes-board"`, so it is `../esas`), and make it absolute. If nothing links esas, **ask** — do not guess a path.

**Do not set `ESAS_REPO_PATH`.** The server designs against its working directory, and Claude Code spawns a project server with the working directory set to the project root — including inside a worktree, where that is the worktree itself. `.mcp.json` is git-tracked, so the entry is byte-identical in every worktree of a fleet: pinning an absolute path there would make all of them design against the one checkout it names, which is exactly the split layer the main-checkout rule exists to prevent. Unpinned, a worktree answers `ESAS_DIR_MISSING`, which is the right answer there.

`.mcp.json` is git-tracked, so this dirties the working tree — say so, and let the user decide whether it ships with the PR.

Then **stop the command** with this, verbatim:

> **RESTART REQUIRED — `esas-mcp` is registered but not running.**
> Registration takes effect only at session start: Claude Code spawns stdio MCP servers when a session boots, so the tools do not exist in *this* one no matter what the file now says.
> Exit this session, start a new one in this repo, approve the `esas` server when Claude Code asks (repos with `enableAllProjectMcpServers` are not asked), and run `/design` again.
> No design write is lost — nothing has been written to `.esas/`, and `.work/design.md` is written at the end of the interview, not now. What the restart does cost is this session's reading: the grounding pass, and any forks already answered. The new session re-does them.

Three rules while this session lasts:

- **Do not call any `mcp__esas__*` tool for the rest of this session.** They are not there. A "no such tool" is not a transient failure to retry around.
- **Never substitute for the missing server.** Do not create or edit `.esas/design.json`, `.esas/ops.jsonl` or `.esas/.claude-cursor` by hand.
- **If the user does not restart** ("just keep going"): run Steps 1–4 with board mode off. That is a complete, correct `/design` — it produces `.work/design.md` and nothing else. Say once that the board layer will be there next session, then drop it.

### Seeding the design layer

`.esas/design.json` is the store's file and the store is the only writer: atomically, under a lock, with one attributed op appended to `.esas/ops.jsonl` per batch. **Never create or edit `.esas/design.json` by hand.** A hand-written verb has no op behind it, so it has no author, no rationale, no validation — the board renders a design nobody asserted, and the next `rebuild` (which replays the feed) drops it without a word.

So seeding is not a file write. `design: absent` already *is* the empty design everywhere that reads it — the board loader and `get_design` both answer with an empty document rather than an error. (The hook never opens `design.json` at all; it reads `ops.jsonl` against the cursor, so it is indifferent either way.) **The first `propose` seeds it**, through the same path every later write takes. Say that to the user instead of manufacturing an empty file.

What does need a decision is a layer that is already there. The design layer is gitignored and lives one unit of work, deleted after the merge — so `design: present` before you have written anything means you are resuming, or you are looking at residue. **Ask whose session it is.** Resuming keeps the verbs, the feed and the sync cursor and needs nothing done. Starting clean means the *user* deletes `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor`. Never delete them unasked: they are the only copy of a session's intent, and they are not in git.

(A sync cursor left behind by a previous feed reads as "nothing has been synced" and inflates the hook's pending count — see the `esas-pending` skill. That one is cosmetic and clears on the next sync. Another unit of work's *verbs* are not.)

### The board — offer the launch when there is something to see, verify the endpoint, never spawn it unasked

**Offer the board at the moment the first batch of questions is ready to post, and start it only on a yes.** That is the first moment it is worth looking at, and it is the same moment the summon watcher goes up (below), for the same reason: before it the canvas holds the graph and nothing to answer, so the offer costs the user a second screen and gives them nothing to do on it. Offer the line their repo uses — `yarn esas:board` in teselly, otherwise `node <esas checkout>/packages/sticky-notes-board/bin/esas-board.mjs` — together with the link the questions are behind, `?openComments=1&author=ai`, which opens on the open threads instead of on the whole canvas. On a yes, start it as a `Bash` call with `run_in_background`, which outlives the turn that started it; in the foreground it would hold that turn open for as long as the board serves. On a no, leave them the line and carry on — the board is a projection, and it opens current whenever they launch it.

**Never spawn it unasked, and never at the preflight.** The port is the reason, and it is strict (below): a board nobody asked for squats :3727 for as long as it runs, and the repo that pays is the *next* one — its board will not bind, in a session that did nothing wrong and has no reason to suspect a board it never started. An orphan is also the hardest kind to find, which is what the `board: other-repo` row above is for. Offering at the preflight makes that the ordinary outcome rather than the unlucky one: the preflight answers *capability*, and a checkout that can hold a board is not yet a design that needs one.

The board claims **:3727 strictly**. It never drifts to the next free port, so `GET /api/esas/status` on that port either answers for this repo or does not answer at all. It returns `{repoPath, gitSha, lastSeq}`; `lastSeq` is the same number the `status` tool reports, which is what makes a dead link visible by comparing two screens instead of debugging.

**Never block the design on the board.** It is the projection, not the source of truth: writes land in files through `esas-mcp`, and a board launched an hour later renders everything that already happened. What genuinely stops board mode is a missing `.esas/` (no substrate) or a missing server (no hands). A dark second screen is not one of them.

### What board mode changes about the rest of this command

- **Step 2 gains a surface.** Propose as decisions resolve, not in one dump at the end — the point is that the user watches the model take shape while you talk. Batch each turn's proposals into **one** call (arrays in, one write, one op).
- **Read reality with `get_flow`**, one command flow at a time, never by re-reading the whole graph. `scope.boundary` defaults to `'end-to-end'`; `'subdomain'` keeps a flow's cross-subdomain hand-offs visible as leaves rather than pretending the ripple stops at the boundary.
- **Arm the summon watcher on any turn that leaves the user something to answer on the board, as the last thing you do before going idle.** That is the moment, and the two neighbouring ones are wrong: at preflight there is nothing to answer yet, so the wake is spent on a press that resolves nothing; mid-turn, a background task that exits while you are still talking re-invokes a session that was never waiting. One armed watch at a time — arming a second while the first is alive costs a wake nobody asked for. What the watcher *is*, how the wake behaves and the six invariants that keep it from looping or going silent are the `esas-design` skill's half; this step decides only when it goes up.
- **The gestures live in the `esas-design` skill** — the sync point, the summon, corrections, restarts, and the fleet rule. Follow it; it is the behavioural half of this step.
- **Step 3 still writes `.work/design.md`.** The two surfaces are complementary, not redundant: `.work/design.md` carries the decisions — the forks, the why, the rejected options — and `design.json` (structure) carries the verbs. Both feed `/plan`, so do not thin one because the other exists.

---

## Step 1 — Ground the interview

- Read the ticket / context. Read the relevant bounded context's `CONTEXT.md` (locate it via `.esas.config.json` `domainEventsPath`, per the `domain-modeling` skill) so you speak the project's ubiquitous language from the first question.
- Explore the codebase for anything the design depends on — **answer from the code, not speculation**, wherever a question can be settled that way.
- **Verify the ticket against the code before trusting it — stale tickets are the norm, not the exception.** Building from the ticket text alone routinely produces the wrong change: re-implementing something that already shipped, or implementing something whose premise no longer holds. (In one 4-ticket run, three descriptions were stale — a "missing" flag had shipped months earlier, an already-fixed error, an event schema already live built-to-contract by its consumer — and a fourth's stated premise was simply false.) This is minutes of work and it is exactly what the design-first gate is for, so make it explicit:
  1. **Grep for the ticket's central symbol** — the flag, event, or command it names. Does it already exist?
  2. **`git log -S <symbol>`** — has it been shipped? Reverted? Had its tests deleted?
  3. **Check the ticket's stated *premise*, not just its ask** — if it says "this unblocks X," confirm X is blocked *only* by this, and that something actually populates what X depends on.
  4. Where the ticket and the code disagree, **the code wins** — and the design doc says so explicitly, so the reader knows the ticket text was stale and what the real change is.

## Step 1.5 — If the ticket carries a resolved-design block (second pass)

If the ticket has a `<!-- design-multi:resolved:v1 ... -->` block, its design was already resolved in an earlier `/design-multi` interview. **This run is a verification second pass, not a fresh grill.** Those are prior decisions, each with its rejected options and the evidence that settled it — treat them as **authoritative pre-answers**, the same way you treat the code:

- **Verify, don't re-derive.** For each resolved decision, confirm it still holds against the *current* code (the same step-1 protocol). Only **re-open** a fork the code now **contradicts** — e.g. the block was grounded against an older base and something it assumed has since shipped or changed.
- On a ticket whose code hasn't drifted, the grill has **nothing to ask** and flows straight to Step 2.5 / the doc. This is exactly what lets `/start-multi` run such a ticket unattended.
- Where a resolved decision no longer holds, surface it as a normal fork (Step 2). Running standalone, you ask the user; under `/start-multi`, that unit escalates.

## Step 2 — Grill (using the `grill` + `domain-modeling` skills)

Run the interview: walk every branch of the decision tree, one question at a time (under board mode the independent forks batch to the canvas and only the dependent ones stay serial — the `grill` skill's split), each with your recommended answer; resolve dependencies between decisions before moving on. While you do:

- **Sharpen the language** — challenge terms against the glossary, propose canonical terms for fuzzy ones, stress-test relationships with concrete edge-case scenarios, and **cross-reference claims against the code**.
- **Update `CONTEXT.md` inline** the moment a term resolves (glossary only — no implementation detail).
- **Offer an ADR** only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Continue until you reach genuine shared understanding — every pivotal fork resolved, no hand-waving.

## Step 2.5 — Critique the resolved design (using the `critique` skill)

Before writing it down, turn the lens on the design. The grill was *convergent* — it built the design *with* the user; the `critique` skill is *divergent* — it attacks the resolved position. Run `critique` (default `arch,ops` lenses) against the resolved decision tree and surface the verdict: the top weaknesses, the severity, and kill-or-continue.

- If critique lands a **fix that's clearly right**, fold it back into the design before writing the doc.
- If it surfaces a **genuine fork the grill missed**, drop back into Step 2 and resolve it.
- A weakness with **no good answer** is a risk — carry it into the design doc's *Risks* section rather than pretending it's solved.

Don't let this become a second grill; it's one focused adversarial pass on what's already decided.

## Step 3 — Write the design doc → `.work/design.md`

Write the resolved design to `.work/design.md` (create `.work/` if absent; it is gitignored and ephemeral). **Markdown + Mermaid** so it renders in an editor with a mermaid preview. Aim for a doc a teammate can review in one pass:

- **Problem & intent** — what we're solving, in the ubiquitous language.
- **The resolved decision tree** — each pivotal fork and the chosen answer, with the why.
- **Seams / flow** — a Mermaid diagram of the key flow (e.g. command → event → policy → …) and any new boundary the design crosses.
- **Test seams** — where the feature will be *verified*. Prefer existing seams to new ones; use the highest seam possible; minimize their number (ideal: one). Note a prior-art test to mirror for each. These become the slices' oracles in `/plan` — confirm them with the user before finishing.
- **Risks / the gate-less seam** — the riskiest part nothing automatically catches (this becomes the tracer bullet in `/plan`).
- **Scope boundaries** — explicit in/out, and any follow-ups to spin off.

This doc is **ephemeral** — it is the review surface and the input to `/plan`. Its durable conclusions live in the glossary/ADR updates (committed) and, later, the PR body. Do **not** commit `design.md`.

## Step 4 — Hand off

Summarise: the resolved design, any `CONTEXT.md`/ADR updates made, and the open risks. Then:

> Review `.work/design.md`. When it's right, run `/plan` to cut it into vertical slices.

## Principles

- The grill is the engine; the docs are a side effect, not the goal. Don't let doc-writing slow the interview.
- `CONTEXT.md` updates are durable and committed; `design.md` is ephemeral.
- Speak the ubiquitous language — if the design needs a term the glossary lacks, that's a term to resolve and record.
