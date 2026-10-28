# bett3r-pv4

The **pv4 + Blueprint** plugin: skills for designing and building pv4 apps on a Blueprint
board. pv4 work does not use the spec-driven flow of `bett3r-ai-workflow`; it leans on the board.

## Skills

| Skill | Does |
|---|---|
| `framework-adapter` | The pv4 vocabulary a Blueprint design run reads before modelling: each `pv4.yaml` term mapped to one of the board's eight kinds, pv4's naming (PascalCase names, invariant sentences, snake_case modules and fields, `renamed-from:`), and the file each kind becomes. Vocabulary only; the method stays in Blueprint. |

## Install

For a hand-run session (a design run gets it from `designPlugins` instead):

```bash
/plugin install bett3r-pv4 --marketplace bett3r-dev/bett3r-ai-workflow
```

## How a design run loads it

A pv4 repository declares the plugin in its `.blueprint.config.json`
`designTooling.designPlugins` (`{source, ref, plugin: "bett3r-pv4"}`); Steward fetches it at the
pinned sha and passes it with `--plugin-dir`. The agent invokes the skill with the `Skill` tool.

`scripts/test-framework-adapter.mjs` checks every `framework-adapter` skill in this marketplace
maps all eight board kinds and carries no method words.
