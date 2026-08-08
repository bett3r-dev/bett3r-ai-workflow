# PV3 schemas and events — reference

> Split out of [SKILL.md](./SKILL.md), which carries the project-configuration placeholders (`<domainEventsPackageName>`, `<serverPath>`, …), the cross-cutting MDU/lift artifact-factory contract, and the trigger table that names this file.

## Schemas

Use `@bett3r-dev/jsonschema-definer` (imported as `S`):

```typescript
import S, { omitFromSchema } from '@bett3r-dev/jsonschema-definer';

export const MyCreatedEventSchema = S.shape({
  name: S.string(),
  count: S.number().minimum( 0 ),
  status: S.string().optional()
});
export const MyEditedEventSchema = MyCreatedEventSchema.partial();
```

Type extraction: `typeof Schema.type` (not `z.infer<>`). Use `omitFromSchema( Schema, ['field'] )` (not `.omit()`).

Domain schemas split across two files in `<domainEventsPackageName>`:

| File | Contains |
|------|----------|
| `<domain>.types.ts` | Event schemas, value objects |
| `<domain>-integration.types.ts` | Aggregate state, command, readmodel schemas |

## Events

Factory functions with schema and friendlyName, at `<domainEventsPath>/src/<domain>/<entity>.events.ts`:

```typescript
import { Event } from '@bett3r-dev/pv3-types';

export const SomethingHappened = () => Event({
  schema: SomethingHappenedEventSchema,
  friendlyName: { es: 'Algo sucedio', en: 'Something happened', pt: 'Algo aconteceu' }
});
```

### Renaming a persisted field is schema evolution, not a rename

Renaming or removing a field on a **persisted event** schema (`<domain>.types.ts`) — or on the **aggregate state** that rehydrates from those events — requires an **upcaster or event-type version bump, never a bare rename.** PV3 rehydrates aggregates by reading event fields **by name**, so any event persisted under the old name rehydrates to `undefined` for that field (e.g. `accounts["undefined"]`), silently breaking replay and every command that depends on that state (`*_NOT_FOUND`).

- **The tell** — a PR scoped as a "pure rename" that edits `*.types.ts` event schemas, or the `applyEvent` / rehydration field reads on aggregate state. That is a data-store change, not a symbol rename.
- **The check** — does a pre-existing (old-shaped) event still rehydrate correctly? Is there a test that persists an old-shaped event and replays it? A green *targeted* test run does **not** cover this — the replay path usually has no test.
- **The safe contrast** — PV3 derives stream / route / subscription identity from the **filename**, not the const, so renaming *code symbols* (const names, type names) is safe and has zero data-store impact. Renaming *persisted fields* is not. Apply the rule to the persisted half only; don't over-apply it to symbol renames.

Cross-ref: this is why `create-schema` / `create-aggregate` renames on existing modules are not mechanical.
