---
description: Drive a hosted Blueprint session from this laptop. connect (the session for this branch, plus the local listener), disconnect (stop the listener, forget the session), status.
disable-model-invocation: true
---

# /blueprint — drive a hosted session from this laptop

A hosted Blueprint session can be driven from Claude Code on a laptop: the code, the experiments and the credentials stay here, and the chat and the design land on the hosted session. Three parts take part, and none of them is a local board:

- **The sign-in.** `blueprint login` signs this machine in to a host once; the CLI keeps the credential. The user types it at the prompt as `! blueprint login --host <url>`, because it opens a browser to approve a code. You never run it, and it is never a yarn script, which exists only inside the blueprint repo. `blueprint` on `PATH` is the `@bett3r-dev/blueprint-cli` package's binary.
- **The connection.** The `mcp__blueprint__connect` tool finds the session the host binds to this checkout's origin remote and branch and writes it to `blueprint-connection.json` in the git dir (`$(git rev-parse --git-dir)`, so each worktree has its own). From then on every `mcp__blueprint__*` tool works on that session, with no restart. `BLUEPRINT_HOST_URL` and the hosted env vars beside it override the record while they are set.
- **The listener.** `blueprint listen` holds this laptop's summon socket on the session, with the token in a header. It acks every ring and prints it as one line. A `Monitor` running it turns each line into a wake for this session. Never a `Monitor` ws URL at the host: the ws form sends no `Authorization` header and cannot ack (plugin `docs/adr/ADR-018`).

Your Asks (the Ask button, a comment that asks for a reply, closing the last fork) ring this laptop while the listener holds the socket. With no listener they go to the hosted agent. A ring nobody acks within about 10 s also goes to the hosted agent, and the board tells you the laptop did not answer. Other members' Asks always go to the hosted agent.

## Argument: $ARGUMENTS

| Form | Does |
|---|---|
| `connect [<host>]` | connect this checkout to its branch's session, then start the listener |
| `disconnect` | stop the listener, then forget the session |
| `status` | what this checkout is connected to, whether the sign-in stands, whether anything listens |

An empty argument is `status`.

## Before any form

If no `mcp__blueprint__*` tools are in this session, `blueprint-mcp` is not registered here: `skills/blueprint-design/BOARD-SETUP.md` §2, then stop. If `command -v blueprint` finds nothing, tell the user to install `@bett3r-dev/blueprint-cli` so `blueprint` is on `PATH`, and stop.

## `connect`

1. Call `mcp__blueprint__connect`, with `host` if the argument named one. Branch on the refusal's code, never on its message:

   | code | what you do |
   |---|---|
   | `CONNECT_NOT_SIGNED_IN` | Ask the user to run `! blueprint login --host <url>` (the message names the host when it knows it), then call `connect` again. |
   | `CONNECT_RECORD_MISMATCH` | This checkout's record names a session for this branch that the host no longer lists among the branch's sessions: show both (the message and `details`), let the user pick one of the listed sessions and call again with `sessionId`, or `/blueprint disconnect` first. |
   | `CONNECT_HOST_REQUIRED` | The laptop is signed in to several hosts and none was named: ask which, and call again with `host`. |
   | `CONNECT_PICK_SESSION` | Several sessions are bound to this branch: show the listed sessions, let the user pick, and call again with `sessionId`. |
   | `CONNECT_ORG_REQUIRED` | No session is bound to this branch, so `connect` starts a change from the repository's Baseline, and the remote is in several orgs: show them, let the user pick, and call again with `orgId`. |
   | `CONNECT_ENV_OVERRIDE` | `BLUEPRINT_HOST_URL` is set, and env vars win over a connection: say so; the user unsets them to connect. |
   | `CONNECT_NO_BRANCH` | This checkout has no branch or no origin remote: say so and stop. |
   | anything else | Quote the code and message and stop. |

   A refused `connect` writes nothing. `started: true` on the answer means no session was bound to this branch and `connect` started a change session: say so. `reused: true` means the record already named this branch's session and `connect` kept it (a started change is unfindable on the host until the branch is pushed, so a repeat `connect` never starts a second one).

2. If this session already runs a `Monitor` on `blueprint listen` for another session, `TaskStop` it first.
3. Start the listener with the answer's `listen` field, verbatim; do not rebuild it from the host and session. Its form is `blueprint listen --host <h> --session <id>`, and the call is:

   ```
   Monitor({ command: "blueprint listen --host <h> --session <id>", persistent: true })
   ```

   No `2>&1`. Only stdout reaches you as events, and on stdout `blueprint listen` prints the rings and nothing else, one line each. Its start line and its end reason go to stderr: `Monitor`'s end-of-watch notice carries the last stderr lines, so the end reason reaches you when the listener exits, and a startup line does not wake you for nothing.
4. Say in one line which session you connected to and that the listener is up. Then let the turn end.

### A ring

Each event is one line, `Ask from <member> on session <id>: <instruction>`, or `(no instruction; look at the board)` for a plain press. Handle it as a summon (`blueprint-design`, the summon): run the sync whole, then act on the instruction within the design gesture.

### Keeping the listener up

- **The watch expires.** `persistent: true` holds the watch for the session. Where `Monitor` still expires a watch at its `timeout_ms` (a remote session caps it), you get one expiry notice: arm the same command again at once, with `timeout_ms` at the maximum.
- **The listener exits.** `blueprint listen` never reconnects; it exits with one reason on stderr:

  | reason | means | what you do |
  |---|---|---|
  | `LISTEN_CLOSED` | The host closed the socket: a deploy, a network drop, the laptop slept, or the session was discarded. | Arm it again once and say so in one line. Nothing tells a discard apart from the others: if the user says the session is gone, `/blueprint disconnect`. |
  | `LISTEN_FAILED` | The socket never opened: the host could not be reached or refused it. | Arm it again once. Failing again, stop and tell the user the listener is down and their Asks go to the hosted agent. |
  | `LISTEN_REFUSED` | The host refused the socket because the sign-in no longer stands. | Do not re-arm. Ask the user to run `! blueprint login --host <h>`, then `/blueprint connect`. |
  | `NOT_SIGNED_IN` | This machine has no sign-in for the host. | Same as `LISTEN_REFUSED`. |

  The 10 s fallback means no Ask is lost while the listener is down; they reach the hosted agent instead.
- **A new session.** The listener lives as long as the `Monitor` that runs it. The `SessionStart` hook checks the record at t=0 and, when nothing holds the session's socket, prints the same `Monitor` call; make it.

## `disconnect`

1. **Stop the listener first.** `TaskStop` the `Monitor` running `blueprint listen` for this session. Until it stops it keeps acking rings, so your Asks never fall back to the hosted agent, and disconnecting would leave them ringing a laptop that no longer drives the session. If it is not in this context, find its task and stop it. If none runs here, check the laptop with `ps -ax -o pid,command | grep "[b]lueprint listen"`. A listener another session started is the user's to stop: name it and ask.
2. Call `mcp__blueprint__disconnect`. It removes `blueprint-connection.json`; the tools work on the local checkout again (or on the env-var target, when `BLUEPRINT_HOST_URL` is set). `disconnected: false` means there was no connection.
3. Say in one line what was disconnected and that the listener is stopped.

## `status`

Report each fact, read as follows:

```bash
cat "$(git rev-parse --git-dir)/blueprint-connection.json"      # the connection; absent = not connected
git symbolic-ref -q --short HEAD                                # the branch now
blueprint whoami --host <h>                                     # the sign-in
blueprint listen --probe --host <h> --session <id>              # exit 0: your Asks ring a laptop connection
```

- No record: not connected; `/design`'s local board mode applies. Stop there.
- No `mcp__blueprint__*` tools although `blueprint-mcp` is registered, and its stderr says `CONNECT_HOST_NOT_SIGNED_IN`: the record names a host this laptop is not signed in to, and `blueprint-mcp` refuses to start rather than silently working on the local checkout. The user runs `! blueprint login --host <h>` and restarts, or deletes the record (`rm "$(git rev-parse --git-dir)/blueprint-connection.json"`, what `disconnect` does) to design locally.
- `BLUEPRINT_HOST_URL` set: the env vars choose the target, not the record. Say so.
- The branch now differs from the record's `branchAtConnect`: the connection stays on that session (F2). Every `blueprint-mcp` result and the `SessionStart` hook carry one reminder line, `… Run /blueprint connect to switch to <branch>'s session.` Switching is the user's call: `/blueprint connect` again on this branch.
- The probe exits 1, or no `Monitor` in this session runs the listener: offer to start it (`connect` step 3).

Done when each fact is reported in one line.
