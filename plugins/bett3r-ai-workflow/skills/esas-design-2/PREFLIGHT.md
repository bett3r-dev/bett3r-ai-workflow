# ESAS board preflight (used by /design-2)

The capability half of the board-mode gate: what is actually on disk in this
checkout. It reports facts and decides nothing. Run it from the repo root, then
read the verdict table below. `/design-2` owns the relevance half.

### Gate 2 — capability: what is actually on disk

Run the preflight from the repo root. It reports facts and decides nothing:

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

### What each verdict means

| report | what it means | what you do |
|---|---|---|
| `plugin: loaded` | A version-keyed cache directory for this plugin is on `PATH`, and the `version:` line under it is the build **this session** is running. That is a different question from which source tree you are editing: the cache is copied afresh only when the version string changes, so an edited plugin whose version stayed put is still being served from the old copy. | Nothing, in the ordinary case — read it and carry on. It earns its place on one path: if you have just changed this plugin and the number here is the previous release, **the change is not loaded**, and nothing you are reading in this session is what is running. Say so before acting on any of it; the fix is a version bump and a fresh session, not another edit to a file nobody is executing. |
| `plugin: unknown` | No cache directory for this plugin on `PATH` — the session is running the plugin from source, or it was never installed from the marketplace at all. | **Not an error, and not a thing to fix.** It means this one line cannot answer the question, so carry on exactly as normal. If the answer turns out to matter — a command behaving like a version you do not recognise — read `~/.claude/plugins/installed_plugins.json` instead. |
| `esas_dir: absent` | No design layer here — a fleet worktree, or a repo the extractor has never run in. | **Board mode off.** Run Steps 1–4 exactly as written. Never create `.esas/` to switch it on; the directory is the marker of "this checkout designs". |
| `esas_dir: present`, `graph: absent` | `.esas/` exists but the extractor has not produced a graph. | Board mode off until it has. Ask the user to run the repo's extractor (`yarn esas` in teselly), then re-run the preflight. Proposals against a graph that isn't there have nothing to attach to. |
| `esas_dir: present`, `graph: present` | Reality is on disk. | Board mode is possible — continue down this table. |
| `design: absent`, `ops: absent` | No design session has started here. | The normal, clean start. There is nothing to create — BOARD-SETUP.md §*Seeding*. |
| `design: present` or `ops: present` | A design layer is already on disk. | It is either the unit of work you are resuming or the residue of one that shipped. **Ask whose session it is** — BOARD-SETUP.md §*Seeding*. |
| `mcp: registered` | The entry is in `.mcp.json`. That is not the same as the server running. | Call the `status` tool now — BOARD-SETUP.md §*Registering* for the three ways this answers. |
| `mcp: unregistered` / `mcp: absent` | This repo's `.mcp.json` does not register the server. That is all the preflight can see — it reads the project file only. | Write the entry, then **stop** — BOARD-SETUP.md §*Registering* — **unless the `mcp__esas__*` tools are already available in this session**, which means it is registered elsewhere (a user-scoped `~/.claude.json`). Then skip the write: it would cost a needless restart and put a duplicate entry in a git-tracked file. |
| `board: off` | Nothing is serving this repo on :3727. | The normal state before the user launches it. **Carry on** — the offer comes later, when the first batch of questions is ready, not here; BOARD-SETUP.md §*The board*. |
| `board: serving` | A board is up on this checkout. The `status:` line under it is the board's whole answer, including `sessions` — how many sessions are holding the summon channel (`/api/esas/ws`) open. | Compare its `lastSeq` with the `status` tool's. Same number ⇒ the link is live. Then read `sessions`: **`"sessions":0` means nobody would hear the *Ask Claude* button** — open the channel (`esas-design` skill, §*The summon*). A number ≥ 1 is not a guarantee anyone is listening (there is no heartbeat, so a half-open socket still counts), so never use it to decide *not* to open one; and an older board omits the field entirely, which is unknown, never zero. |
| `board: other-repo` | Something holds :3727 serving a *different* checkout, and the `status:` line under the verdict says which. | **Name the repo that holds it** — the `repoPath` in the `status:` line is the project root that board serves — and say so before the first proposal: until it is closed this repo's board cannot claim the port (`strictPort` never drifts), and the screen the user is watching will never move. Naming it is the difference between a thing the user can close and a board they may not remember starting. Then carry on. |
| `board: unknown` | No `curl` here, so the board was not probed at all. | Say it was not verified rather than reporting it down, and carry on. |

