---
description: Orchestrate complete DDD module creation including schemas, aggregate, policies, read models, and tests. Use when scaffolding a new bounded context or feature module.
---

# Skill: Create Module

Orchestrate the creation of a complete PV3 DDD module by composing all sub-skills.

**Read [`ddd-patterns` → MODULES.md](../ddd-patterns/MODULES.md) before writing `index.ts`** — the `create()` composition shape and why a boot hook (`onStarted`) must be correct under *both* boot orders. [`ddd-patterns` → SKILL.md](../ddd-patterns/SKILL.md) carries the cross-cutting rules this skill's checklist assumes (the MDU/lift artifact-factory contract, the composition-root boundary, invariant placement) plus the trigger table naming the per-artifact references the sub-skills use.

## Project configuration

Resolve these placeholders from the repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>` | `domainEventsPackageName` | `@bett3r-dev/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## FIRST — Sub-Skill Patterns

Apply the patterns from these sibling skills (`create-schema`, `create-aggregate`, `create-policy`, `create-readmodel`, `create-tests`) — they are the source of truth for each component:

1. `create-schema`
2. `create-aggregate`
3. `create-policy`
4. `create-readmodel`
5. `create-tests`

## Generation Order

Generate components in this exact order (each step depends on the previous):

### Step 1: Schemas (the domain package)

Location: `<domainEventsPath>/src/<domain>/`

Generate:
- `<domain>.types.ts` — Event schemas, value objects
- `<domain>-integration.types.ts` — Aggregate state, command, readmodel schemas
- `<entity>.events.ts` — Event factory functions with friendlyName
- `index.ts` — Barrel exports (both `.types` and `-integration.types`)

Apply the patterns from the `create-schema` skill.

### Step 2: Server Re-export File

Location: `<serverPath>/src/modules/<module-name>/`

Generate:
- `<module>-module.types.ts` — Thin re-export of schemas from `<domainEventsPackageName>`

```typescript
export {
  MyAggregateSchema,
  CreateCommandSchema,
  EditCommandSchema,
  MyReadmodelSchema,
  MyReadmodelType
} from '<domainEventsPackageName>';
```

### Step 3: Aggregate

Location: `<serverPath>/src/modules/<module-name>/`

Generate:
- `<entity>.aggregate.ts` — AggregateBuilder with event reducers and command handlers

Apply the patterns from the `create-aggregate` skill.

### Step 4: Policies (if applicable)

Location: `<serverPath>/src/modules/<module-name>/`

Generate:
- `<purpose>.policy.ts` — One file per policy

Apply the patterns from the `create-policy` skill.

### Step 5: Read Models (if applicable)

Location: `<serverPath>/src/modules/<module-name>/`

Generate:
- `<entity>.readmodel.ts` — ReadmodelBuilder with projectors and queries

Apply the patterns from the `create-readmodel` skill.

### Step 6: Tests

Location: Co-located with source files

Generate:
- `<entity>.aggregate.test.ts`
- `<purpose>.policy.test.ts` (for each policy)
- `<entity>.readmodel.test.ts`

Apply the patterns from the `create-tests` skill.

### Step 7: Module Index

Location: `<serverPath>/src/modules/<module-name>/index.ts`

```typescript
import { Ports } from 'ports';
import { MyAggregate } from './<entity>.aggregate';
import { MyReadmodel } from './<entity>.readmodel';
import { MyPolicy } from './<purpose>.policy';

export const create = async ( ports: Ports ) => {
  ports.eventsourcing.routeCommandHandler( MyAggregate( ports ));
  ports.eventsourcing.routeEventHandler( MyReadmodel( ports ));
  ports.eventsourcing.routeEventHandler( MyPolicy( ports ));
};
```

## Integration Steps

After generating all module files:

### 1. Update the domain package barrel exports

Ensure the new domain is exported from `<domainEventsPath>/src/index.ts` (or the appropriate barrel file).

### 2. Register module in server

The module's `create()` function needs to be called from the server's module registration. Check the existing pattern in:
- `<serverPath>/src/modules/` — see how other modules are imported and their `create()` is called.

### 3. Run tests

```bash
npx jest <serverPath>/src/modules/<module-name>/ --verbose
```

## File Structure Summary

```
<domainEventsPath>/src/<domain>/
  <domain>.types.ts                  # Event schemas, value objects
  <domain>-integration.types.ts      # Aggregate, command, readmodel schemas
  <entity>.events.ts                 # Event definitions
  index.ts                           # Barrel exports

<serverPath>/src/modules/<module-name>/
  <module>-module.types.ts   # Re-exports from <domainEventsPackageName>
  <entity>.aggregate.ts      # Aggregate
  <entity>.readmodel.ts      # Read model
  <purpose>.policy.ts        # Policy (0 or more)
  <entity>.aggregate.test.ts # Aggregate tests
  <entity>.readmodel.test.ts # Readmodel tests
  <purpose>.policy.test.ts   # Policy tests
  index.ts                   # Module composition
```

## Critical Constraints

- **Follow sub-skill files exactly** — They are the source of truth
- **No `*.controller.ts`** — PV3 handles routing internally
- **No `*.module.ts`** — Replaced by `index.ts` `create()` function
- **No `*.service.ts` for readmodels** — PV3 ReadmodelBuilder handles projection inline
- **Every artifact factory takes EXACTLY `( ports )`** — aggregate, policy, readmodel, system. Never a second constructor argument. The MDU/lift loader instantiates artifacts as `factory( ports )`; an injected dep is `undefined` in any lifted deployment unit. Single-consumer infra → a lazy library singleton via `getX( ports )`, never the global `Ports` type. See the `ddd-patterns` skill → "Artifact Constructor Signature — the MDU/Lift Contract".
- **Co-located tests** — `*.test.ts` next to source, not in separate directory
- **Events in the domain package** — NOT in the server module
- **Types in the domain package** — NOT in the server module

## Output Summary

After completion, return:

```
## Module Created: <ModuleName>

**Domain schemas:** <domainEventsPath>/src/<domain>/
  - <domain>.types.ts
  - <entity>.events.ts
  - index.ts

**Module:** <serverPath>/src/modules/<module-name>/
  - <entity>.aggregate.ts
  - <entity>.readmodel.ts
  - <purpose>.policy.ts (if applicable)
  - <entity>.aggregate.test.ts
  - <entity>.readmodel.test.ts
  - <purpose>.policy.test.ts (if applicable)
  - index.ts

**Integration:**
  - [ ] domain package barrel exports updated
  - [ ] Server module registration updated
  - [ ] Tests passing
```

## Final Checklist

- [ ] All sub-skill files read before generation
- [ ] Schemas generated first (other components depend on them)
- [ ] Events have friendlyName with es/en/pt
- [ ] Aggregate uses AggregateBuilder pattern
- [ ] Every artifact factory (aggregate/policy/readmodel/system) takes EXACTLY `( ports )` — no second constructor argument (MDU/lift contract)
- [ ] Aggregate has `scopeInvariant()` via `.withCommandTemplate()` (unless internal/system)
- [ ] Aggregate creation event reducer captures `ownerId: metadata?.userId`
- [ ] Policies use PolicyBuilder pattern
- [ ] Readmodel uses ReadmodelBuilder pattern
- [ ] Readmodel queries have `FilterByAccountIdTransformer()` AND `FilterByScopeTransformer()`
- [ ] Readmodel creation projector includes `ownerId: event.metadata?.userId`
- [ ] All queries have authentication checks
- [ ] Tests co-located with source files
- [ ] Module index.ts registers all components
- [ ] Barrel exports updated
- [ ] Tests pass
