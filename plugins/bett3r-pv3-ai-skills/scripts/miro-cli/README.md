# miro-cli — Miro frame-data fetcher

The `miro-to-mermaid` skill's **Step 1** needs the raw items + connectors of a Miro
event-storming frame, fetched via the Miro REST API. This bundled CLI does that, so the skill
works in any repo without depending on a host-provided script. (The Miro API does not expose
callouts or code blocks — those come from a manual SVG export the script parses and merges in.)

## Setup

**1. Install the script's dependencies once:**

```bash
cd scripts/miro-cli && npm install
```

**2. Provide your Miro token.** The script reads `MIRO_ACCESS_TOKEN` from the environment. Get a
token at <https://miro.com/app/settings/user-profile/apps> → create/select an app → OAuth &
Permissions → generate one with the `boards:read` scope.

A Miro token is a **personal developer credential** (tied to your account, reused across boards
and repos), so the most robust home is a machine-level env var — it works wherever you run from
and survives plugin updates (this plugin dir is wiped on update). In order of preference:

- **Recommended — shell / secrets manager:** add `export MIRO_ACCESS_TOKEN=...` to `~/.zshrc`
  (or `~/.bashrc`), or inject it via a secrets manager / `direnv`.
- **One-off:** prefix the command — `MIRO_ACCESS_TOKEN=xxx npm run frame -- ...`.
- **`.env` file (optional):** put `MIRO_ACCESS_TOKEN=...` in a `.env` in the directory you run the
  command from, or beside this script (`cp .env.example .env`). A real exported env var always
  takes precedence over a `.env` file.

## Usage

```bash
npm run frame -- "<miro-frame-url>" --svg <path-to-frame.svg> --pretty
# or directly:
npx tsx get-frame-data.ts "<miro-frame-url>" --svg <path-to-frame.svg> --pretty
```

- `<miro-frame-url>` — full Miro URL including a `moveToWidget` / `focusWidget` param identifying the frame.
- `--svg <path>` — **required.** The frame's SVG export (right-click the frame in Miro → Export selection → SVG). Recovers callouts + code blocks the REST API omits.
- `--pretty` — pretty-print the JSON (default: compact).

Output is JSON on **stdout** (`items`, `connectors`, `metadata`); progress/warnings go to
**stderr**. Save it, then hand it to the `miro-to-mermaid` skill.

## Notes

- Host-repo-agnostic — it ships with the plugin. If your repo already has its own Miro
  frame-data fetcher, you can use that instead.
- Token resolution precedence: an exported `MIRO_ACCESS_TOKEN` env var → `.env` in the current
  directory → `.env` beside this script.
- Never commit your token: `.env` is git-ignored; only `.env.example` is tracked. Prefer an env
  var so the secret never lands in a file inside the plugin (which is wiped on update).
