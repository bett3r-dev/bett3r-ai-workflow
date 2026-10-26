#!/bin/sh
[ -n "${BLUEPRINT_CAPTURE_REPOSITORY:-}" ] || exit 0
#
# Stop, SessionEnd and SessionStart — "send this conversation to Blueprint's
# memory?" (ML-1 F28, F17).
#
# A conversation with Claude outside Blueprint holds the reasons behind the code,
# and Blueprint's memory can keep them as log hits of the repository ("said in
# conversation, not decided"). Nothing leaves the machine unless its person says
# so: the repository opts in from its checked-in settings, and each person picks
# how, from the environment Claude Code gives the hook:
#
#   BLUEPRINT_CAPTURE_REPOSITORY  the repository's name in Blueprint, set in the
#                                 checked-in .claude/settings.json `env`; unset,
#                                 this hook is the gate above and nothing else
#   BLUEPRINT_CAPTURE             the person's: off | ask | always (default ask),
#                                 in .claude/settings.local.json `env` or the shell
#
#   ask     the first Stop of a session blocks once, with an instruction for the
#           agent to ask the person "Send this conversation to Blueprint's
#           memory?" with a one-line summary; a yes runs `blueprint-send
#           --consent`, and SessionEnd then sends the whole conversation; a no
#           sends nothing. Stop is the only hook that gives the agent a turn;
#           SessionEnd runs after the conversation is over. Never asked in a run
#           nobody answers (claude -p, an SDK, a lane, a Steward design run).
#   always  SessionEnd sends the whole conversation, unasked.
#
# Every send is blueprint-capture.py's: the secret check first (a match stops the
# send with "This looks like a secret" and the ways on: redact, edit, send
# anyway; found at SessionEnd, the next SessionStart in the repository raises
# it), then the upload and CaptureConversation. A hook never blocks work and
# fails open: no `set -e`, every path exits 0, a failure is one line on stderr,
# and the one ask is its only block.

command -v python3 >/dev/null 2>&1 || {
  echo 'blueprint-send: python3 is not on PATH; nothing was sent' >&2
  exit 0
}
python3 "$(dirname -- "$0")/blueprint-capture.py" hook
exit 0
