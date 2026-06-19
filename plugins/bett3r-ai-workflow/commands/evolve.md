---
description: Turn a plugin repo's accumulated ai-learning issues into reviewed PRs. Run inside the plugin repo whose issues you want to process.
---

# /evolve — issues → reviewed PRs

Process the `ai-learning` issues that `/capture-learnings` routed to **this** repo: cluster them, propose concrete changes, and open PRs for review. This is the per-repo consumer end of the propagation machine.

## Step 1 — Collect
`gh issue list --label ai-learning --state open` for this repo. Read each fully (body + comments).

## Step 2 — Cluster & dedupe
Group issues touching the same skill/command/agent or proposing the same change. Close exact duplicates (referencing the survivor). Drop or flag stale ones (already addressed, or no longer true). Converge the backlog — don't let it sprawl.

## Step 3 — Propose
For each cluster, decide the concrete change to the artifact. Where a change is contentious or a genuine trade-off, surface it for the user rather than guessing.

## Step 4 — Open PRs
For each agreed change: branch, make the edit, open a PR that **links the issues it closes** (`Closes #N`). **One PR per coherent change** (never one giant PR) so review stays tractable. Let the normal review pipeline (human and/or `/code-review`) gate the merge.

## Step 5 — Report
The clusters, the PRs opened (with the issues each closes), and anything left for the user to decide.

## Principles
- **Convergent, not accumulative** — dedupe and close so the backlog stays a real to-do list.
- One coherent change per PR; **reviewed before merge** — these are shared artifacts many repos consume.
- Don't auto-merge. Evolve proposes; review disposes.
