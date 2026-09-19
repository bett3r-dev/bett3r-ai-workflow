# Hooks

## How this plugin declares a hook

`hooks/hooks.json` at this exact path is loaded automatically for every enabled plugin; `plugin.json`'s `hooks` field is for additional hook files only, and pointing it back here is an error. Shape:

```jsonc
{ "hooks": { "<Event>": [ { "matcher": "<tool>", "hooks": [ { "type": "command", "command": "sh", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/<file>"], "timeout": 5 } ] } ] } }
```

`${CLAUDE_PLUGIN_ROOT}` is substituted in `command` and in each `args` element, and only for plugin hooks; `${CLAUDE_PROJECT_DIR}` is exported into the hook's environment, which is what every script here reads. `args` is the exec form: no shell re-parse, so a plugin path with spaces cannot break the invocation. `matcher` selects on the tool name and nothing else; there is no per-directory matcher, so every hook here runs in every repo where the plugin is enabled, and the first thing each script does is one cheap check that exits 0 wherever the hook does not apply.

## esas-pending.sh (`UserPromptSubmit`)

Injects one line, `esas: N pending (seq A→B)`, while the user has unsynced semantic edits on the ESAS design board. Telemetry, never a trigger; the rule for reacting to it is `skills/esas-pending/SKILL.md`. Line 2 is `[ -f "${CLAUDE_PROJECT_DIR:-.}/.esas/ops.jsonl" ] || exit 0`. Every path exits 0, because a `UserPromptSubmit` hook that exits 2 erases the user's prompt; with `wc` and `awk` missing it prints nothing. Scanning is linear in the part of the feed the cursor has not bounded, and a hit of the 5 s timeout costs one prompt's telemetry, never the prompt.

## esas-session-channel.sh (`SessionStart`)

Prints one instruction, to open the board's session channel with `Monitor({ ws: { url: 'ws://127.0.0.1:<port>/api/esas/ws' }, persistent: true })`, so the board's *Ask Claude* button can reach an idle session from t=0, resumed sessions included. Line 2 is `[ -d "${CLAUDE_PROJECT_DIR:-.}/.esas" ] || exit 0`. It speaks in exactly one state: a board answering `GET /api/esas/status` on `${ESAS_BOARD_PORT:-3727}`, serving this checkout, reporting `sessions: 0`. Nothing on the port, a board for another checkout, `sessions >= 1`, no `sessions` field, no `curl`: all silent, exit 0. A board started later in the session is recovered by the `esasSessionChannel` notice `esas-mcp` attaches to its tool results.

## lane-git-guard.sh (`PreToolUse`, matcher `Bash`)

In an unattended lane, blocks the git commands that discard or shelve the working tree. A lane is any checkout holding `.work/lane.yaml`, the brief the provisioner writes, and the checkout a command acts on is not always the project dir (a fleet lane is a subagent of the orchestrator's session and reaches its worktree through `cd` or `git -C`). So the hook reads the event JSON on stdin (line 2; a payload with no `git` in it exits there on a glob match), takes `tool_input.command` and `cwd` from it, tokenises the command with `;`, `|`, `&`, `(`, `)`, a backtick and a newline as separators, and looks for the brief in the cwd, in `CLAUDE_PROJECT_DIR`, and in every path after `cd`, `-C` or `--work-tree` (relative paths resolve against the cwd). When one of them holds the brief and the command carries `git stash` (except `create`, `list`, `show`), `git reset --hard`, `--merge` or `--keep`, `git checkout --`, `.`, `-f` or `--force`, `git switch -f`, `--force` or `--discard-changes`, `git restore` or `git clean -f`, it exits 2 with one line on stderr naming the command and the alternative, `git stash create` plus `git diff <object>`. Everything else exits 0, and nothing is ever written to stdout. The match is on the command's own tokens, so the words inside a quoted string or a description do not match; a heredoc body line starting with `git stash` does.

## Tests

`sh scripts/test-hooks.sh` at the repo root covers all three: the pending count against fixtures produced by the real `@bett3r-dev/esas-store` (`scripts/fixtures/esas-pending/README.md`), the session channel against a stub board on an ephemeral port, the guard against synthesized `PreToolUse` payloads, and the wiring in `hooks.json`.

## Fallback: installing a hook by hand

Not needed in a normal install. For a user who wants the pending count without enabling the plugin, add to `.claude/settings.json` in the repo being designed and copy `esas-pending.sh` to `.claude/esas-pending.sh`:

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "sh", "args": [".claude/esas-pending.sh"], "timeout": 5 } ] }
    ]
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` is not available in `settings.json`, so the path is a real one, and a hand-installed copy does not update with the plugin. If both are installed the line appears twice; remove one.
