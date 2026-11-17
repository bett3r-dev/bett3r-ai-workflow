---
name: framework-adapter
description: "pv4 vocabulary for a Blueprint board: how each `pv4.yaml` term maps to a board kind and how pv4 names nodes, fields and files, and how the scaffold writes lists, views and screens. Read it in a Blueprint design run on a pv4 repository, before modelling."
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
| `sweeps.<Name>`: `{ over: ReadModel, due: <timestamp filter>, issues: Command }` | policy tagged `sweep` |
| `read-models.<Name>`, with its SELECT in `<module>/read_models/<read_model>/<read_model>_select.sql`; `projections.<Name>` | read model (a projection tagged `projection`) |
| `external-systems.<Name>`, with its send stub in `externalsystems/` | external system |
| `invariants.<Name>: {field?}` | invariant |
| a generated page, or a GET hand route under `handroutes/` | screen |

A sweep runs on a timer: each period it issues its command once per row of its read model
whose `due` timestamp has passed. Draw it as a policy tagged `sweep` with a reads-from edge
to that read model (its `over`), an issues edge to the command, and no event triggering it.
Its `due` is a timestamp field of the read model; give the read model one (a constant in the
past, `due_at`, makes every row due at once). The command it issues starts a flow of its own
on the board, the sweep drawn ahead of it. `jobs` have no board kind: they are not drawn.

## What is already in the code

The board's code layer is the session branch's extracted code. A node or edge that is there
already is drawn as it is: join it with edges, or propose a change to it
(ProposeElementChanges), never propose it again. Only what this change adds is a new node.

## Lists, views and screens

- A read model is drawn with each event that changes it projected-to it: `RoomAdded` projected-to
  `RoomDirectory` is `RoomDirectory: { reads-from: [Room] }`, a SELECT over the aggregate that
  emits it. Tagged `projection`, its events write its rows instead (`projections.<Name>`). It may
  read another read model's published view (a reads-from edge between read models). The board
  draws no `postgres-view` node: a read model's SELECT is its file, not a node.
- A read model's page is a screen labelled as the read model (`rooms_ui_room-directory`); a
  command it invokes lands on that page unless it lands on another already, or is another
  module's, which is asked about. A screen under another label that shows exactly one
  read model with a page, and invokes only that module's commands with a form, is taken as
  that page, with a note in the scaffold's report.
- Any other screen (two read models, none, another module's command) is a GET hand route named
  after the screen, at the default path `/<module>/<screen-in-kebab>` (`Front desk` is
  `FrontDesk` at `/rooms/front-desk`), listed under `<module>.admin`. Both are defaults to
  confirm: the path carries a `TODO(scaffold)` line, as does a new `<module>.admin`, and the
  scaffold's report lists both; the body that reads and posts what
  the screen's edges draw is the developer's. A default path pv4 already serves (an
  aggregate's page or a form of that name) is asked about instead.

## Names

- Aggregates, commands, events, policies, read models and external systems: PascalCase names
  (`PlaceOrder`, `OrderPlaced`).
- Invariants: PascalCase sentences that say what holds (`OneSessionPerTicket`).
- Modules and fields: snake_case (`session_engine`, `placed_at`).
- A command declares no field `id`: every command already carries the id of the aggregate it
  changes, and pv4 refuses one that declares it again. Name another aggregate's id for it
  (`slot_id`), a record found by a value of its own for that value (`sku`), and leave a command
  that needs nothing else with no field of its own.
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
| sweep | none of its own: the command it issues has its handler |
| external system | `<module>/externalsystems/<system>_send.go` |
| read model | `<module>/read_models/<read_model>/<read_model>_select.sql` |
| screen (hand route) | `handroutes/<route>_serve.go` |
