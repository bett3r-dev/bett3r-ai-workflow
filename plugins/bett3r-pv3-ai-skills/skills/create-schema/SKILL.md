---
description: Scaffold schemas, types, and events for a new DDD domain using @bett3r-dev/jsonschema-definer. Use when defining the schema layer for a new module.
---

# Skill: Create Schema

Scaffold type definitions, event schemas, and aggregate schemas for a PV3 DDD module.

**Read [`ddd-patterns` → SCHEMAS.md](../ddd-patterns/SCHEMAS.md) before writing the files** — the `jsonschema-definer` conventions, the two-file domain split, the event factory shape, and (load-bearing on any *existing* module) why renaming or removing a persisted field is schema evolution, not a rename.

**The scaffolder cannot help here, and that is structural.** An ESAS node carries a label, a
subdomain and a resource key — it has **no fields**. So every schema is hand-written, and a
scaffolded artifact does not compile until you write it: `<Name>CommandSchema` for a generated
command fragment, `<Name>EventSchema` for a generated event fragment, `<Name>ReadmodelSchema` /
`<Name>ReadmodelType` for a generated read model. Those names are not suggestions — the generated
files already import them, so they are the contract.

Run this skill straight after [`scaffold-from-design`](../scaffold-from-design/SKILL.md); it is
the first item in every generated file's `STILL OWED` block.

## Project configuration

This skill resolves the following placeholders from your repo's `.esas.config.json`:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<domainEventsPath>` | `domainEventsPath` | `src/packages/shared/teselly-domain` |
| `<domainEventsPackageName>` | `domainEventsPackageName` | `@bett3r-dev/teselly-domain` |
| `<serverPath>` | `serverPath` | `src/services/server` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## Schema Library

Use `@bett3r-dev/jsonschema-definer` (imported as `S`):

```typescript
import S, { omitFromSchema } from '@bett3r-dev/jsonschema-definer';
```

**NOT Zod.** This project uses jsonschema-definer exclusively.

## Generated Files

### 1. Types File: `<domainEventsPath>/src/<domain>/<domain>.types.ts`

```typescript
import S, { omitFromSchema } from '@bett3r-dev/jsonschema-definer';

// Value Objects (reusable shapes)
export const AddressSchema = S.shape({
  line1: S.string().optional(),
  city: S.string().optional(),
  state: S.string().optional(),
  country: S.string().optional(),
  postalCode: S.string().optional()
});
export type AddressType = typeof AddressSchema.type;

// Event Schemas
export const MyEntityCreatedEventSchema = S.shape({
  name: S.string(),
  status: S.string(),
  count: S.number().minimum( 0 ),
  address: AddressSchema.optional(),
  tags: S.array().items( S.string() ).optional()
});
export const MyEntityEditedEventSchema = MyEntityCreatedEventSchema.partial();
export const MyEntityStatusChangedEventSchema = S.shape({
  status: S.string(),
  previousStatus: S.string().optional()
});
```

### 2. Integration Types File: `<domainEventsPath>/src/<domain>/<domain>-integration.types.ts`

Contains aggregate state schemas, command schemas, and readmodel schemas — everything the server modules and client library need beyond events.

```typescript
import S, { mergeSchemas, omitFromSchema } from '@bett3r-dev/jsonschema-definer';
import {
  MyEntityCreatedEventSchema,
  MyEntityEditedEventSchema
} from './<domain>.types';

//*******************************************
// MyEntity Aggregate
//*******************************************

export const MyEntityAggregateSchema = S.shape({
  accountId: S.string(),
  name: S.string(),
  status: S.string(),
  count: S.number().minimum( 0 )
});

export const CreateMyEntityCommandSchema = MyEntityCreatedEventSchema;
export const EditMyEntityCommandSchema = MyEntityEditedEventSchema;

//*******************************************
// MyEntity Readmodel
//*******************************************

export const MyEntityReadmodelSchema = mergeSchemas( MyEntityCreatedEventSchema, S.shape({
  id: S.string(),
  accountId: S.string()
}));
export type MyEntityReadmodelType = typeof MyEntityReadmodelSchema.type;
```

**Key conventions:**
- Separate from `<domain>.types.ts` (which holds event schemas and value objects)
- Command schemas are typically aliases of event schemas: `export const XCommandSchema = XEventSchema;`
- Readmodel schemas use `mergeSchemas()` to compose from event schemas + extra fields (`id`, `accountId`)
- Use section comment blocks (`//*****...`) to visually separate aggregates, commands, and readmodels

### 3. Events File: `<domainEventsPath>/src/<domain>/<entity>.events.ts`

```typescript
import { Event } from '@bett3r-dev/pv3-types';
import {
  MyEntityCreatedEventSchema,
  MyEntityEditedEventSchema,
  MyEntityStatusChangedEventSchema
} from './<domain>.types';

export const MyEntityCreated = () => Event({
  schema: MyEntityCreatedEventSchema,
  friendlyName: {
    es: 'Entidad fue creada',
    en: 'Entity was created',
    pt: 'Entidade foi criada'
  }
});

export const MyEntityEdited = () => Event({
  schema: MyEntityEditedEventSchema,
  friendlyName: {
    es: 'Entidad fue editada',
    en: 'Entity was edited',
    pt: 'Entidade foi editada'
  }
});

export const MyEntityStatusChanged = () => Event({
  schema: MyEntityStatusChangedEventSchema,
  friendlyName: {
    es: 'Estado de la entidad fue cambiado',
    en: 'Entity status was changed',
    pt: 'Estado da entidade foi alterado'
  }
});
```

### 4. Barrel Export: `<domainEventsPath>/src/<domain>/index.ts`

```typescript
import * as MyEntityEvents from './<entity>.events';

export { MyEntityEvents };
export * from './<domain>.types';
export * from './<domain>-integration.types';
```

## Critical Constraints

### Schema Operations

- Use `omitFromSchema( Schema, ['field'] )` — NOT `.omit()`
- Use `Schema.partial()` for edit/update event schemas
- Use `S.shape({})` for object schemas — NOT `z.object({})`
- Type extraction: `typeof Schema.type` — NOT `z.infer<typeof Schema>`

### Event Naming

- Past tense: `OrderPlaced`, `EntityCreated`, `StatusChanged`
- Domain-prefixed to avoid collisions: `SalesOrderPlaced` not just `OrderPlaced`
- Events are factory functions: `export const MyEvent = () => Event({...})`

### Schema Types

| Type | Method |
|------|--------|
| String | `S.string()` |
| Number | `S.number()` |
| Boolean | `S.boolean()` |
| Array | `S.array().items( S.string() )` |
| Object | `S.shape({...})` |
| Map / Record | `S.array().items( S.shape({ key, value }) )` — jsonschema-definer has no `S.record()` |
| Optional | `.optional()` |
| Enum | `S.string().enum(['a', 'b'])` |
| UUID | `S.string().format( 'uuid' )` |
| Email | `S.string().format( 'email' )` |
| Date (ISO-8601) | `S.string().format( 'date' )` — **required** when the field is compared lexicographically (e.g. monotonicity invariants) |
| DateTime | `S.string().format( 'date-time' )` |
| Min/Max | `S.number().minimum( 0 ).maximum( 100 )` |
| Partial | `Schema.partial()` |
| Additional props | `S.shape({}).additionalProperties( true )` |
| Freeform JSON | `new BaseSchema<any>()` (import from `@bett3r-dev/jsonschema-definer`) |

**IMPORTANT:** Never use `S.any()`. It bypasses all validation and is never appropriate. For fields that accept arbitrary JSON objects, use `new BaseSchema<any>()` instead. If types don't match, fix the schema — don't escape with `S.any()`.

**Map / Record indexing caveat:** the `{ key, value }[]` array-map is the only way to model `Record<string, T>`, but the database layer **cannot index a field nested inside it** — only flat, top-level fields are indexable. A parent readmodel that holds children as a nested array-map therefore cannot serve an indexed query that filters on a child field. When a policy or query must scan or filter a *subset* of those children, project a **separate flat readmodel keyed by the child entity**, carrying the filter fields at top level, and drive the scan from there (e.g. a `contractId`-keyed flat readmodel with a compound `status` + `termEnd` index alongside the nested parent, so a renewal/recurring-run policy gets an indexed scan instead of a full table load).

### Multi-Entity Modules

If a module has multiple aggregates/entities, use separate event files:

```
<domainEventsPath>/src/my-domain/
  my-domain.types.ts        # All schemas for the domain
  entityA.events.ts          # Events for entity A
  entityB.events.ts          # Events for entity B
  index.ts                   # Barrel exports all
```

### FriendlyName

Events MUST have `friendlyName` with at least `es`, `en`, `pt` translations.
Events without user-visible names (internal/system events) can omit friendlyName.

## Reference Files

- Look at an existing domain under `<domainEventsPath>/src/` in your repo for a working reference of types (`<domain>.types.ts`) and events (`<domain>.events.ts`).

## File Structure Summary

```
<domainEventsPath>/src/<domain>/
  <domain>.types.ts                  # Event schemas, value objects
  <domain>-integration.types.ts      # Aggregate, command, readmodel schemas
  <entity>.events.ts                 # Event factory functions
  index.ts                           # Barrel exports all
```

## Final Checklist

- [ ] Types file uses `S` from `@bett3r-dev/jsonschema-definer`
- [ ] Type extraction uses `typeof Schema.type`
- [ ] `omitFromSchema()` used (not `.omit()`)
- [ ] Events are factory functions: `() => Event({...})`
- [ ] Events have `friendlyName` with es/en/pt
- [ ] Event names are past tense PascalCase
- [ ] Integration types file has aggregate, command, and readmodel schemas
- [ ] Server module has thin re-export file from `<domainEventsPackageName>`
- [ ] Barrel export in domain `index.ts` exports both `.types` and `-integration.types`
- [ ] Readmodel schema includes `id` field
- [ ] No `S.any()` usage — use `new BaseSchema<any>()` for freeform JSON fields
