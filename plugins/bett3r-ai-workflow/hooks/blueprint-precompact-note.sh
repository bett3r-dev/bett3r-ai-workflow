#!/bin/sh
case ${CLAUDE_PROJECT_DIR:-$PWD} in *.blueprint-worktrees/?*) ;; *) exit 0 ;; esac
#
# PreCompact — "write your note before the context goes" (ML-1, F14).
#
# A Blueprint design run keeps its working memory in the conversation: what it
# was doing, the dead ends it ruled out, the person's preferences. Compaction
# is exactly when those are lost, so before it the run is asked for a note,
# written to the session with the `WriteNote` tool; the newest note is the one
# the next pick-up reads, the ones before stay, superseded (the server's rule,
# not this hook's).
#
# ## What a PreCompact hook can do
#
# Claude Code appends this hook's stdout, on exit 0, to the compaction's custom
# instructions; the agent gets no turn between the hook and the summary. So the
# line below is addressed to the summary: keep the three things and the
# session id, and end with the instruction to call WriteNote with them before
# anything else once compaction is over. That call is conditional on the tool
# being in the agent's list: a Blueprint server older than WriteNote has none
# (the design's version-skew risk), and there the note stays in the summary. An exit 2 would BLOCK the compaction, so no path here
# exits anything but 0: no `set -e`, no `set -u`, no read of stdin.
#
# ## The gate (line 2)
#
# A Blueprint design run is Steward's: it runs the design agent in a worktree
# of the repository at `<repo>.blueprint-worktrees/<session id>` and starts
# claude there, so the project dir is that path. One `case` on a string, no
# process started: every other session in every repo where the plugin is
# enabled, including a checkout with a `.blueprint/` or a `/blueprint connect`
# record, prints nothing and exits 0.

printf '%s\n' 'blueprint: this Blueprint design run is about to be compacted, and what the conversation holds goes with it. In the summary, keep what you were doing, the dead ends you ruled out, the person'"'"'s preferences and the session id, and end it with this instruction: if your tools include mcp__blueprint__WriteNote, then before anything else call it with that note as its text and the session id, so whoever picks the session up next reads it; if they do not, keep the note in the summary and carry on.'
exit 0
