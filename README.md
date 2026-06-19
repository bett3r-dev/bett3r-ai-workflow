# bett3r-ai-workflow (marketplace)

A private Claude Code **marketplace** for Bett3r's internal AI development tooling. One repo, two
plugins that co-evolve:

| Plugin | What it is | Install in |
|--------|------------|------------|
| [`bett3r-ai-workflow`](./plugins/bett3r-ai-workflow) | The **methodology** — a vertical-slice, dual-gated flow (start → design → plan → build → verify-build → capture-learnings → evolve). Project-agnostic; reads each host repo's conventions at runtime. | Any repo |
| [`bett3r-pv3-ai-skills`](./plugins/bett3r-pv3-ai-skills) | The **PV3 DDD framework skills** — `create-*` scaffolders + `ddd-patterns` reference. Reads packages/paths from each repo's `.esas.config.json`. | Any PV3 repo |

A PV3 repo (e.g. Teselly) installs both; a non-PV3 repo installs just the workflow plugin.

## Install

```bash
# add this private marketplace (git auth via SSH key / gh token with repo access)
/plugin marketplace add bett3r-dev/bett3r-ai-workflow

# install the plugins you want
/plugin install bett3r-ai-workflow@bett3r-ai-workflow
/plugin install bett3r-pv3-ai-skills@bett3r-ai-workflow
```

(The `@bett3r-ai-workflow` suffix is the marketplace name, set in `.claude-plugin/marketplace.json`.)

## Layout

```
.
├── .claude-plugin/
│   └── marketplace.json          # lists the plugins below
└── plugins/
    ├── bett3r-ai-workflow/        # the workflow plugin
    │   └── .claude-plugin/plugin.json
    └── bett3r-pv3-ai-skills/      # the PV3 framework-skills plugin
        └── .claude-plugin/plugin.json
```

Each plugin has its own README under `plugins/<name>/`. Add a new plugin by dropping it under
`plugins/` and adding an entry to `marketplace.json`.
