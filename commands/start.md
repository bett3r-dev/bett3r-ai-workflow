---

## description: Begin a unit of work — create the branch and scaffold the ephemeral .work/ workspace. Thin and mechanical, no context docs.

# /start — begin work

Thin and mechanical: a branch and an ephemeral workspace. No `context.md`, no committed scaffolding, no ceremony.

## Argument: $ARGUMENTS

A ticket id and/or a short description of the work.

## Step 1 — Check for unfinished work

If `.work/slices.yaml` exists and holds slices not all `passes: true`, note it: "Unfinished work in `.work/` () — starting new work replaces it." **Default: proceed.** That prior work's real record is its branch/commits/PR; `.work/` is disposable. (Only pause if the user explicitly asked to be warned.)

**Records guard:** if `.work/learnings.md` has unprocessed entries (captured via the `record` skill), warn before replacing: "N unprocessed records in `.work/learnings.md` — run `/capture-learnings` first?" Losing these is the exact failure `record` exists to prevent, so default to surfacing it here.

## Step 2 — Branch

Create a branch off the current branch. Name it from the ticket id + a slug (e.g. `TV1-1594-delete-items`), or from the description if there's no id.

## Step 3 — Scaffold `.work/`

Create `.work/ and add it to .gitignore` if it is missing. It holds `design.md` and `slices.yaml` — ephemeral, never committed.

## Step 4 — (optional) Pull ticket context

If a ticket id is given and a tracker MCP is available (Jira/GitHub), fetch the ticket summary/description for context. If not, continue — the user will describe the work.

## Step 5 — Hand off

> Branch `<name>` ready. Run `/design` to grill and model the work.

## Principles

- Thin. The branch + `.work/` are all `start` produces.
- `.work/` is gitignored and disposable; git is the record.

