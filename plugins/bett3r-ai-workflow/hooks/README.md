# Hooks

## How this plugin declares a hook

`hooks/hooks.json` — **this exact path** — is loaded automatically for every
enabled plugin. Nothing in `plugin.json` needs to reference it; that manifest's
`hooks` field is for *additional* hook files only, and pointing it back here is
an error ("The standard hooks/hooks.json is loaded automatically, so
manifest.hooks should only reference additional hook files").

Verified against Claude Code 2.1.220, three ways:

1. **The published schema** — `https://json.schemastore.org/claude-code-plugin-manifest.json`
   describes `plugin.json`'s `hooks` as "additional hooks (in addition to those
   in `hooks/hooks.json`, if it exists)".
2. **`claude plugin validate <plugin> --strict`** reads this file — renaming the
   event to `UserPromptSubmitt` fails with
   `hooks.UserPromptSubmitt: Invalid key in record`.
3. **A live run** — `claude -p … --plugin-dir <this plugin> --debug-file …`
   logged `Read hooks.json for plugin bett3r-ai-workflow`, then
   `Hook UserPromptSubmit success: esas: 2 pending (seq 1→4)`, and the line
   reached the model's context.

Shape:

```jsonc
{ "hooks": { "<Event>": [ { "hooks": [ { "type": "command", … } ] } ] } }
```

`${CLAUDE_PLUGIN_ROOT}` is substituted in `command` **and** in each `args`
element, and is available *only* to plugin hooks — a `settings.json` hook that
references it is rejected. `${CLAUDE_PROJECT_DIR}` is both substitutable and
exported into the hook's environment, which is what `esas-pending.sh` reads.

`args` is the exec form: the command is spawned directly, with no shell
re-parse, so a plugin path containing spaces cannot break the invocation. Keep
`command` a bare executable name when `args` is present.

## esas-pending.sh — the ESAS board pending count

A `UserPromptSubmit` hook that injects one line, `esas: N pending (seq A→B)`,
while the user has unsynced semantic edits on the ESAS design board. It is
**telemetry, never a trigger**; the standing rule for reacting to it lives in
`skills/esas-pending/SKILL.md`, deliberately not in the hook's output.

Two properties are load-bearing, because this runs on **every prompt in every
repo** where the plugin is enabled (there is no per-directory matcher):

- **It always exits 0.** A `UserPromptSubmit` hook that exits 2 blocks
  processing and erases the user's prompt. Every path here — corrupt cursor,
  unreadable feed, torn feed, binary garbage — exits 0.
- **It is free when there is no board.** Line 2 is
  `[ -f "${CLAUDE_PROJECT_DIR:-.}/.esas/ops.jsonl" ] || exit 0`. Measured
  against an empty script on the same machine, the difference is **below the
  noise floor** — the whole cost is the process spawn that every command hook
  pays, and the hook's own work does not register.

It also degrades silently rather than loudly: with `wc` and `awk` — the only two
tools it still needs — absent (`PATH=/nonexistent`) it prints nothing, to
either stream, and exits 0.

The declared `timeout` is 5 s. Scanning cost is linear in feed size, on the feed
the cursor has *not* bounded:

| feed | scan |
|---|---|
| 1 MB / 2 000 ops | 0.47 s |
| 9.7 MB / 20 000 ops | 4.6 s — **at the timeout** |

A design session's semantic feed does not approach that, but debounced
`class: layout` position writes are the plausible route: they are excluded from
the *count*, not from the *scan*. Hitting the timeout is benign — the hook is
killed, no line is injected, and the prompt proceeds untouched, because a
timed-out hook is not a non-zero exit. It costs one prompt's telemetry, never
the prompt.

Tested by `scripts/test-hooks.sh` at the repo root, against fixtures produced by
the real `@bett3r-dev/esas-store` (see `scripts/fixtures/esas-pending/README.md`).

## esas-session-channel.sh — arming the board's summon channel

A `SessionStart` hook that prints one instruction: open the ESAS **session
channel** with `Monitor({ ws: { url: 'ws://127.0.0.1:<port>/api/esas/ws' },
persistent: true })`. That socket is how the board's *Ask Claude* button reaches
an idle session (esas ADR-014); the gesture itself is
`skills/esas-design/SKILL.md`, and this hook only says *now would be the time*.

**Why a hook exists at all** is the whole reason the mechanism was rewritten.
The channel it replaced was a shell watcher armed by the `/design` command, so
its arming died at every session boundary — a resume, a `/handon`, any other
session in the repo — and the recovery was the human remembering to ask.
`SessionStart` fires for **every** session in the repo, resumed ones included,
so the channel can go up at t=0 with nobody asked.

It obeys `esas-pending.sh`'s two rules for the same reason (no per-directory
matcher, so it runs at the start of every session in every repo): **line 2 is
the whole program** — `[ -d "${CLAUDE_PROJECT_DIR:-.}/.esas" ] || exit 0` — and
**every path exits 0**, silently, including a missing `curl`.

**Silence is the behaviour under test.** It speaks in exactly one state: a board
answering `GET /api/esas/status` on `${ESAS_BOARD_PORT:-3727}`, serving **this**
checkout (`repoPath` matched in both JSON spellings and both the logical and
physical spelling of the project root), and reporting `sessions: 0`. Nothing on
the port, a board serving another checkout, `sessions >= 1`, and a board with no
`sessions` field at all (unknown, never zero) are **all silent** — `.esas/`
existing is deliberately *not* sufficient, or every unrelated session in a
designing repo would open a socket it will never use.

What it does **not** cover: a board restarted later in the session, which
`SessionStart` has already run past. That is recovered by the
`esasSessionChannel` notice `esas-mcp` attaches to every tool result while the
channel is shut. This hook buys t=0 only.

Tested by `scripts/test-hooks.sh`, against a stub board on an ephemeral port.

## Fallback: installing the hook by hand

The plugin mechanism above is verified, so this is **not** needed in a normal
install. It exists for the case where a user wants the count without enabling
the plugin, or is on a Claude Code old enough not to load plugin hooks. Add to
`.claude/settings.json` in the repo being designed:

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh",
            "args": [".claude/esas-pending.sh"],
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

and copy `esas-pending.sh` to `.claude/esas-pending.sh`. Note the two
differences from the plugin form: `${CLAUDE_PLUGIN_ROOT}` is **not** available
in `settings.json` (Claude Code rejects a hook that references it there), so the
path must be a real one; and a hand-installed copy does not update with the
plugin. If both are installed the line appears twice — remove one.
