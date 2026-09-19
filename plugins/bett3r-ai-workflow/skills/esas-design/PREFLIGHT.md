# ESAS board preflight (used by /design)

The capability half of the board-mode gate: what is on disk in this checkout. Run it from the repo root. It reports facts and decides nothing; the table under it decides. `/design` owns the relevance half.

```sh
# --- esas preflight ---
# Facts about this checkout's design layer. Decides nothing; the table below
# does that. Every `key: value` line it can print has a row there, and
# scripts/test-esas-design.sh asserts both halves of that.
#
# The plugin line leads because it is the one fact that can invalidate every
# line under it — and the whole command around them. A session runs the build
# the version-keyed cache holds, not the source tree you are reading, so if
# those two have drifted, everything below is a correct report from the wrong
# copy of this file. That is worth one line at the top rather than four JSON
# files under ~/.claude/plugins/ once somebody suspects it.
#
# No `exit` anywhere and every variable prefixed: this runs in whatever shell
# the tool call lands in, and it has no business ending it or renaming
# somebody's `path`.

# `CLAUDE_PLUGIN_ROOT` is substituted for *hook* invocations only, so it is
# unset here and cannot answer this. `PATH` can: the cache `bin` directory of
# every enabled plugin is on it, and that directory is keyed by the version —
#     …/plugins/cache/<marketplace>/bett3r-ai-workflow/<version>/bin
# The marketplace directory happens to share this plugin's name, which is why
# the pattern insists on a path segment *before* the plugin one: without it the
# sibling `bett3r-pv3-ai-skills` under the same marketplace would read as this
# plugin, and report its version as ours.
esas_plugin_version=''
esas_path_rest=$PATH
while [ -n "$esas_path_rest" ]; do
  esas_path_entry=${esas_path_rest%%:*}
  case $esas_path_rest in
    *:*) esas_path_rest=${esas_path_rest#*:} ;;
    *)   esas_path_rest='' ;;
  esac
  case $esas_path_entry in
    */plugins/cache/*/bett3r-ai-workflow/*/bin)
      esas_plugin_version=${esas_path_entry%/bin}
      esas_plugin_version=${esas_plugin_version##*/} ;;
  esac
done
if [ -n "$esas_plugin_version" ]; then
  printf 'plugin: loaded\n'; printf '  version: %s\n' "$esas_plugin_version"
else
  printf 'plugin: unknown\n'
fi

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

## What each verdict means

| report | meaning | what you do |
|---|---|---|
| `plugin: loaded` | A version-keyed cache directory for this plugin is on `PATH`; the `version:` line under it is the build this session runs, which is a different question from which source tree you are editing. | Nothing, ordinarily. If you have just changed this plugin and the number is the previous release, the change is not loaded: say so before acting on anything you read here; the fix is a version bump and a fresh session. |
| `plugin: unknown` | No cache directory for this plugin on `PATH`: it runs from source, or was never installed from the marketplace. | Not an error. Carry on; if the version matters, read `~/.claude/plugins/installed_plugins.json`. |
| `esas_dir: absent` | No design layer here: a fleet worktree, or a repo the extractor never ran in. | Board mode off. Run Steps 1–4 as written and leave the directory absent; it is the marker of "this checkout designs". |
| `esas_dir: present`, `graph: absent` | `.esas/` exists but the extractor has produced no graph. | Board mode off until it has: ask the user to run the extractor `.esas.config.json` declares as `designTooling.extract`, then re-run the preflight. |
| `esas_dir: present`, `graph: present` | Reality is on disk. | Board mode is possible; continue down the table. |
| `design: absent`, `ops: absent` | No design session has started here. | The clean start. There is nothing to create: BOARD-SETUP.md §3. |
| `design: present` or `ops: present` | A design layer is already on disk. | The unit you are resuming, or the residue of one that shipped. Ask whose session it is: BOARD-SETUP.md §3. |
| `mcp: registered` | The entry is in `.mcp.json`; that is not the same as the server running. | Call the `status` tool now: BOARD-SETUP.md §1. |
| `mcp: unregistered` / `mcp: absent` | This repo's `.mcp.json` does not register the server (the preflight reads the project file only). | Write the entry, then stop: BOARD-SETUP.md §2. Skip the write when the `mcp__esas__*` tools are already in this session (a user-scoped `~/.claude.json`); it would cost a needless restart and a duplicate entry in a git-tracked file. |
| `board: off` | Nothing is serving this repo on :3727. | The normal state before the user launches it. Carry on; the offer comes when the first batch of questions is ready: BOARD-SETUP.md §4. |
| `board: serving` | A board is up on this checkout. The `status:` line under it is the board's whole answer, including `sessions`: how many sessions hold the summon channel (`/api/esas/ws`) open. | Compare its `lastSeq` with the `status` tool's; the same number means the link is live. `"sessions":0` means nobody would hear the *Ask Claude* button: open the channel (`esas-design`, the summon). A count of one or more is not proof anyone is listening (no heartbeat, so a half-open socket counts) and never decides against opening one; an older board omits the field, which is unknown, never zero. |
| `board: other-repo` | Something holds :3727 serving a different checkout, and the `status:` line says which. | **Name the repo that holds it** (the `repoPath` in the `status:` line is the project root that board serves) before the first proposal: until it is closed this repo's board cannot claim the port, and the screen the user is watching will never move. Then carry on. |
| `board: unknown` | No `curl` here, so the board was not probed. | Say it was not verified rather than reporting it down, and carry on. |
