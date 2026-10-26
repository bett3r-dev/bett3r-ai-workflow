---
description: Send this conversation to Blueprint's memory now, the secret check first. A captured conversation becomes log hits of the repository, labelled "said in conversation, not decided".
disable-model-invocation: true
---

# /blueprint-send — this conversation, into Blueprint's memory

The person asked for this, so it is their yes: do not ask again whether to send. When this session ends, the capture hook sends it again, whole (unless the person's `BLUEPRINT_CAPTURE` is `off`), so the turns after this one land too. A choice is by message: a `--redact` or `--anyway` covers only the messages the person was shown when they chose (those of the last "This looks like a secret" warning, else those of the send) that no earlier choice covers, and never re-decides an earlier one. The session's end sends each of those messages the way its own choice says and checks every later message again: a secret there, or a match that runs from a chosen message into a later one, sends nothing and is raised by the next session in the repository, and the person's answer to that warning covers only the messages no earlier choice does. A choice run after a later message brought a new secret, before a warning showed it, blocks again. A conversation sent as edited with `--text` is not sent again. What is sent: prompts and replies in full, tool calls and tool output cut to 400 characters (a private key that starts before the cut is kept through its END marker, or, with no END marker of its own, cut at its header), no thinking. It lands as a conversation of the repository named by `BLUEPRINT_CAPTURE_REPOSITORY` (the repository's checked-in settings), attached to the Blueprint session `/blueprint connect` connected this checkout to, if any (not when `BLUEPRINT_HOST_URL` chooses the host).

## Argument: $ARGUMENTS

Empty sends this session's conversation. `--transcript <path>` or `--session-id <id>` names another of this project's conversations.

## Run it

```sh
blueprint-send $ARGUMENTS
```

Branch on its exit status:

| exit | what you do |
|---|---|
| `0` | Say its one line. Done. |
| `3` | It printed "This looks like a secret" and nothing was sent. Show the person those lines as they are, and ask which they want: **Redact and send**, **Edit** (they change the file it names, then you run its `--text` line), or **Send anyway**. Run the line it printed for their choice, and branch on that run's exit the same way. Never choose for them. |
| `1` | Say its one line (Blueprint unreachable, no sign-in it can read, not set up, refused). With no sign-in it can read, the line names the fix: `! blueprint login --host <host> --store file` (a sign-in kept in the OS keychain, the CLI's default, cannot be read) or `BLUEPRINT_ACCESS_TOKEN`. Do not retry in a loop; the person runs `/blueprint-send` again when it is fixed. |

If `blueprint-send` is not on `PATH`, the plugin is older than this command: say so and stop.
