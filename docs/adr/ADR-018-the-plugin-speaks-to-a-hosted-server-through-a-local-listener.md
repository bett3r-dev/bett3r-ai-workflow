# The plugin speaks to a hosted server through a local listener, never a token-bearing Monitor URL

A session hears the board's **Ask** through a summon channel. On a local board that channel is a
`Monitor` ws watch on `ws://127.0.0.1:3727/api/blueprint/ws`: a loopback socket with no credential
and nothing to answer. BP-277 lets a developer drive a *hosted* session from Claude Code on a laptop,
and the hosted summon socket differs from the local one in two ways. It admits a member only on an
`Authorization: Bearer` header, because the host's upgrade gate reads headers only (BP-277 design D9).
And it expects each ring to be acked within about 10 s, after which the hosted agent takes the Ask
(BP-277-F3, option B).

`Monitor`'s ws form takes `{url, protocols}` and nothing else (BP-277 decisions D16, read from the
Claude Code 2.1.302 binary). It cannot send the header, and it cannot send an ack. Pointing it at the
host anyway leaves two options, both wrong: an unauthenticated socket the host refuses, or a token
in the URL, which the gate does not read and every proxy and access log keeps.

## The decision

**The plugin never hands `Monitor` a URL to a hosted server. A local process holds the socket, and
`Monitor` runs that process.** The process is `blueprint listen`, in the public
`@bett3r-dev/blueprint-cli` that `blueprint login` (BP-93) belongs to. It reads the machine's stored
sign-in, opens the summon socket with the token in a header, acks every ring, and prints each one as
a single stdout line. The plugin arms it in `Monitor`'s command form:

```
Monitor({ command: "blueprint listen --host <h> --session <id>", persistent: true })
```

`Monitor` turns each stdout line into a message, so a ring wakes the session the same way a local
summon frame does. The token never leaves the CLI's credential store, and nothing the plugin writes,
prints or tells the model to dial carries it.

Rejected: a `Monitor` ws URL at the host, which cannot authenticate or ack. A token in the query,
which the gate does not read and logs would keep. And `blueprint listen --relay` re-serving the
socket on a loopback ws for `Monitor`'s ws form to dial: BP-277's land-time rule kept it as the
fallback if the command form did not exist, and it does (decisions D16).

## What follows for the plugin

- **The listener is armed from the record, not from a URL.** `/blueprint connect` answers the exact
  `listen` command, which `commands/blueprint.md` arms verbatim. The `SessionStart` hook prints the
  same call when the checkout's connection record exists and `blueprint listen --probe` says no
  laptop connection holds the session (`hooks/blueprint-session-channel.sh`, pinned by
  `scripts/test-blueprint-design.sh`).
- **No `2>&1`.** `blueprint listen` writes rings to stdout and its start line and end reason to
  stderr. Only stdout lines are events, and the end-of-watch notice carries the last stderr lines, so
  the end reason (`LISTEN_CLOSED`, `LISTEN_FAILED`, `LISTEN_REFUSED`) reaches the model when the
  listener exits and nowhere else.
- **Re-arming is the model's job.** `blueprint listen` never reconnects (BP-277 decisions D17), so a
  deploy, a network drop or a sleeping laptop ends it. `commands/blueprint.md` says which end reasons
  are re-armed and which go back to `! blueprint login`, and that a `timeout_ms` expiry is re-armed.
  An Ask raised while the listener is down is not lost: the 10 s fallback hands it to the hosted agent.
- **Disconnect stops the process.** The `disconnect` MCP tool only removes the record; it cannot reach
  a `Monitor`. Until the listener stops it keeps acking, which suppresses the fallback, so
  `/blueprint disconnect` stops the `Monitor` (`TaskStop`) before it calls the tool.

## What this does not decide

- **The local board channel is unchanged.** A loopback board on `:3727` serves no credential and needs
  no ack, so its `Monitor` ws watch stays as it is.
- **Whether a ring line wakes Claude Code** is the owner's manual check. The evidence for the command
  form is strings in the 2.1.302 binary, not a live `Monitor` run.
- **Plugin-armed monitors.** Claude Code can load persistent `Monitor` tasks a plugin declares, without
  the model arming them. The listen command depends on a per-checkout record, so this record does not
  adopt that, and a later one may.

## Status

Accepted (BP-277). The plugin side of BP-277 design D9; the server side is blueprint's ADR-131. Like
every change to this plugin, it reaches installs only with a version bump
([ADR-001](./ADR-001-plugin-version-is-a-release-contract.md)), taken when it lands.
