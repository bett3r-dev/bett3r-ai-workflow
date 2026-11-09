---
name: blueprint-pv4
description: "pv4 tenant board (`mcp__blueprint-pv4__*`, /api/pv4/mcp): connect a local session to a blueprint-pv4 tenant, or before its first tool call. The TS board (`mcp__blueprint__*`) is blueprint-design."
---

# Designing on a pv4 tenant

A pv4 tenant serves its design board over MCP at `POST https://<tenant host>/api/pv4/mcp` (JSON-RPC: `initialize`, `ping`, `tools/list`, `tools/call`). It is a different system from the TypeScript board: none of `read_changes`, `mark_synced`, `get_map`, `get_design`, the `map_*` tools, port 3727 or a websocket summon exists here, and the `blueprint: N pending` hook line never speaks for it.

## Connect

1. The person signs this laptop in by device code: `! blueprint-pv4 login --host https://<tenant host>`. It prints a URL and a code to approve there, then keeps the `pv4s_` token owner-only in `~/.config/blueprint-pv4/credentials.json`. Then, in the checkout, `blueprint-pv4 connect` records the session of the checkout's branch (`blueprint-pv4 status` shows it, `blueprint-pv4 disconnect` removes it); from then on the session-start hook offers the `blueprint-pv4 listen` line, and conversation capture sends to that session with that token when the checkout has no `/blueprint connect` record.

   Fallback, for a person who cannot sign in by device: an admin of the tenant mints an API key with the `design_agent` role, never `contributor`, at `https://<tenant host>/_pv4/api-keys` (or `pv4 apikey create -name <person>-laptop -role design_agent`). That role holds exactly a design run's tools and none of the person's presses. The key starts `pv4k_`; every call made with it acts as `agent:<key name>`.
2. The person registers the server (the token never passes through you) under the name `blueprint-pv4`, so its tools are `mcp__blueprint-pv4__*` and the TS board's rules stay out of reach:

   ```
   claude mcp add --transport http blueprint-pv4 https://<tenant host>/api/pv4/mcp --header "Authorization: Bearer $(blueprint-pv4 whoami --host https://<tenant host> --token)"
   ```

   With the fallback key, the header is `"Authorization: Bearer pv4k_..."`.
3. Restart the session; `tools/list` returns only what the token's role may call.

The token and the key are secrets: keep them out of the repo and the transcript, and add the server at `local` or `user` scope.

## Vocabulary

Each tool is a pv4 command or read model, named as the tenant names it. Among them:

- **Writes**: ProposeElements, ProposeElementChanges, ProposeElementRemovals, LinkElements, UnlinkElements, WriteComments, ResolveComments, RaiseForks, ChooseOptions, CiteSources, PostMapNodes, StrikeMapNodes, NoteMapLists, GroundMap.
- **Reads**: DesignElements, ShapeFields, Discussion, SessionMaps, MapNodes, MapLinks, MapForks, ForkOptions, MapNotes, DesignRuns, Search, Why, BoardGraph.

Read the session's design, discussion and map before you write to it. Every write is one transaction, recorded and attributed to whoever the token or key acts as; a no-op answer means the session already holds it, so treat it as success.

## The person's presses

Map agreed, Design done, Done and Run again are the person's presses. A `pv4s_` device token from `blueprint-pv4 login` acts within the tenant's `laptop_agent` role and is refused them; so is a `design_agent` key. If the tools list offers `PressDone`, `HandOffToDesign` or `SetAutoAcceptDefault`, the key is a contributor's: never call them, and tell the person to sign in with `blueprint-pv4 login` or ask for a `design_agent` key. With a device token, that list means the tenant does not bound its device tokens to `laptop_agent`: never call them either. A session's goal is the person's too: never change or strike it once posted, and never confirm an assumption (a who or an impact posted as assumed).

On a fork, the who-decides rule:

- The code settles it: choose the card's recommendation with settled_by: code and cite the code (CiteSources).
- A question only the person can answer (what they want, priority, money, who it is for, the why): raise it with for_person: true and leave it.
- Anything else stays open for the person. Choose a recommendation only on a fork you raised yourself in this session.

## Refusals

- A refusal names the invariant at fault and why. Read it, fix the entry it names, then send the whole call again; a retry unchanged gets the same refusal.
- A 401 (the token or key ended) or a 403 (its role may not do that): stop and tell the person what was refused. Never retry it.

## Where the method lives

The design method is the tenant's, run by its hosted design agent; this plugin carries none of it, and the tenant serves no MCP prompts yet. Until it does, a local session follows the rules above and leaves the method's steps to that agent and the person.
