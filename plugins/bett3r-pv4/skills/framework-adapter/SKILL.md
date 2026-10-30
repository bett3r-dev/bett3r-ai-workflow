---
name: framework-adapter
description: "pv4 vocabulary for a Blueprint board: how each `pv4.yaml` term maps to a board kind and how pv4 names nodes, fields and files. Read it in a Blueprint design run on a pv4 repository, before modelling."
---

# pv4 on the board

A pv4 app is declared in `pv4.yaml`, the manifest. Each node the manifest declares under a
module is a board node, and its id comes from the manifest alone:
`<slug(module)>_<abbrev>_<slug(name)>`, e.g. `orders_cmd_place-order`.

## Terms to board kinds

| pv4 term (`pv4.yaml`) | Board kind |
|---|---|
| `modules.<m>` | subdomain (the slug of the module) |
| `aggregates.<Name>` | aggregate |
| `commands.<Name>` (`handled-by`, `produces`, `reads`, `invariants: [...]`); `creates: true` is the board tag `starts` | command |
| `events.<Name>` | event |
| `policies.<Name>`: `issues: [Command]`, or `calls: {System: {on-success, on-failure}}` | policy |
| `read-models.<Name>`, with its SELECT in `db/<read_model>_select.sql` (the board draws that view as a `postgres-view` beside it) | read model |
| `external-systems.<Name>`, with its send stub in `externalsystems/` | external system |
| `invariants.<Name>: {field?}` | invariant |
| a generated page, or a GET hand route under `handroutes/` | screen |

`sweeps` and `jobs` have no board kind: they are not drawn.

## Names

- Aggregates, commands, events, policies, read models and external systems: PascalCase names
  (`PlaceOrder`, `OrderPlaced`).
- Invariants: PascalCase sentences that say what holds (`OneSessionPerTicket`).
- Modules and fields: snake_case (`session_engine`, `placed_at`).
- `renamed-from: <old name>` on a node keeps the id the old name had across a rename. Without it
  a rename is one node removed and one added.

## The file each kind becomes

File names are the snake_case of the manifest's names.

| Kind | File the developer fills |
|---|---|
| command | `<module>/<command>_handle.go` |
| invariant | `<module>/<invariant>_check.go` |
| aggregate + event | `<module>/<aggregate>_<event>_apply.go` |
| policy | `<module>/policies/<policy>_<event>_react.go` |
| external system | `<module>/externalsystems/<system>_send.go` |
| read model | `<module>/db/<read_model>_select.sql` |
| screen (hand route) | `handroutes/<route>_serve.go` |
