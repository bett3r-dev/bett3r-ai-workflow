---
description: Generate tests using Given/When/Then pattern for PV3 DDD components. Use when adding tests for aggregates, policies, and readmodels.
---

# Skill: Create Tests

Generate co-located test files for PV3 DDD components using Jest and Given/When/Then structure.

**Open the `ddd-patterns` reference for the artifact you are testing** — each one names the fixtures that are *required*, not optional, and they are the cases a happy-path suite silently omits: [AGGREGATES.md](../ddd-patterns/AGGREGATES.md) (the happy-path + state-rejection pair per status-guarded command; the `STATE_NOT_FOUND` test for every state-reading idempotency predicate; the lock acquire/release fixtures), [POLICIES.md](../ddd-patterns/POLICIES.md) (the redelivery-after-partial-progress test asserting **zero** duplicate events), [READMODELS.md](../ddd-patterns/READMODELS.md) (the interleaved brand-new-key concurrency test), and [DELIVERY.md](../ddd-patterns/DELIVERY.md) for what redelivery a test has to simulate. [`ddd-patterns` → SKILL.md](../ddd-patterns/SKILL.md) has the trigger table.

## Project configuration

Resolve these placeholders from `.esas.config.json` at the repo root:

| Placeholder | `.esas.config.json` field | Example value |
|---|---|---|
| `<serverPath>` | `serverPath` | `src/services/server` |

The framework packages `@bett3r-dev/pv3-types`, `@bett3r-dev/jsonschema-definer`, and the
`ports` module are PV3 framework — identical in every PV3 repo — and appear verbatim below.

## This skill owns functional + happy-path coverage

**Default here, not E2E.** Per the host repo's testing rules § "Test Level": anything
assertable by calling a command/endpoint and reading the event store or readmodel
belongs at this (in-process) level. **Happy paths are covered by integration
tests, not E2E.** Reserve Playwright (`e2e-create-tests`) for browser-specific risk
only (rendering, route guards, input devices, navigation) — one smoke per journey.

Two in-process shapes this skill produces:
- **Unit / component** — aggregate invariants, policy reactions, readmodel
  projectors, pure functions, via `createTestPorts()` + `testCommandHandler()` /
  `testPolicy()` (mock infrastructure).
- **In-process API / pipeline (integration test)** — when the behavior spans
  aggregate→policy→readmodel (a full backend pipeline / bulk flow). Name it
  **`*.integration.test.ts`** and put it in an integration suite under the host
  repo's integration-tests package (see the `create-integration-test` skill): boot
  the full in-memory pipeline via **`createIntegrationHarness({ modules, testUser })`**,
  drive it with the typed client library / `endpoints.fetch`, assert the event store
  + readmodel. No browser/Vite. Run with `yarn test:integration` (NOT `yarn test`,
  which excludes integration tests). Put a test under a channel path only if it hits
  a real external service — those run via `yarn test:integration:channels`.

## File Location and Naming

Tests are co-located next to their source file:

```
<serverPath>/src/modules/<module-name>/
  orders.aggregate.ts
  orders.aggregate.test.ts      # <-- test file
  orders.readmodel.ts
  orders.readmodel.test.ts      # <-- test file
  myProcess.policy.ts
  myProcess.policy.test.ts      # <-- test file
```

**NOT** in a separate `test/` or `__tests__/` directory.

## Test Structure

```typescript
describe( 'MyComponent', () => {
  // Setup
  let ports: any;

  beforeEach(() => {
    ports = createTestPorts();
    jest.clearAllMocks();
  });

  // ═══════════════════════════════════════════════
  // GIVEN: [precondition description]
  // ═══════════════════════════════════════════════

  describe( 'Given [precondition]', () => {
    it( 'when [action] then [expected result]', async () => {
      // GIVEN
      const setupData = { ... };

      // WHEN
      const result = await executeAction( setupData );

      // THEN
      expect( result ).toMatchObject({ ... });
    });
  });
});
```

## Testing Aggregates

```typescript
import { createTestPorts } from '@bett3r-dev/pv3-library-tests';
import { MyAggregate } from './my.aggregate';

describe( 'MyAggregate', () => {
  let ports: any;
  let aggregate: ReturnType<typeof MyAggregate>;

  beforeEach(() => {
    ports = createTestPorts();
    aggregate = MyAggregate( ports );
  });

  // ═══════════════════════════════════════════════
  // GIVEN: No existing entity
  // ═══════════════════════════════════════════════

  describe( 'Given no existing entity', () => {
    it( 'when CreateEntity command then EntityCreated event emitted', async () => {
      // Test command handler logic
      // Verify events are created with correct data
    });
  });

  // ═══════════════════════════════════════════════
  // GIVEN: Existing entity
  // ═══════════════════════════════════════════════

  describe( 'Given existing entity', () => {
    it( 'when EditEntity command then EntityEdited event emitted with diff', async () => {
      // Test that only changed fields are in the event
    });

    it( 'when ChangeStatus command then EntityStatusChanged event emitted', async () => {
      // Test status change includes previousStatus
    });
  });
});
```

## Testing Policies

```typescript
import { createTestPorts } from '@bett3r-dev/pv3-library-tests';
import { testPolicy } from '@bett3r-dev/pv3-library-tests';
import { MyPolicy } from './my.policy';

describe( 'MyPolicy', () => {
  let ports: any;
  let mockClientLibrary: any;

  beforeEach(() => {
    ports = createTestPorts();
    mockClientLibrary = {
      commands: {
        DoSomething: jest.fn().mockResolvedValue( undefined )
      },
      queries: {
        GetSomething: jest.fn().mockResolvedValue( mockData )
      }
    };
  });

  it( 'Given SomethingHappened event when policy processes then triggers downstream command', async () => {
    // GIVEN
    const event = {
      id: 'event-id',
      data: { entityId: 'entity-1', value: 42 },
      metadata: {
        accountId: 'account-1',
        correlationId: 'corr-1',
        userId: 'user-1'
      },
      stream: 'MyAggregate-entity-1'
    };

    // WHEN
    const policy = MyPolicy( ports );
    // Execute the policy handler directly

    // THEN
    expect( mockClientLibrary.commands.DoSomething ).toHaveBeenCalledWith(
      expect.objectContaining({ entityId: 'entity-1' })
    );
  });
});
```

## Testing Readmodels

```typescript
import { createTestPorts } from '@bett3r-dev/pv3-library-tests';
import { MyReadmodel } from './my.readmodel';

describe( 'MyReadmodel', () => {
  let ports: any;
  let mockCollection: any;

  beforeEach(() => {
    mockCollection = {
      upsert: jest.fn().mockResolvedValue( undefined ),
      query: jest.fn().mockResolvedValue([]),
      count: jest.fn().mockResolvedValue( 0 ),
      ensureIndex: jest.fn().mockResolvedValue( undefined )
    };

    ports = createTestPorts();
    ports.database.getCollection = jest.fn().mockReturnValue( mockCollection );
  });

  // ═══════════════════════════════════════════════
  // Projector Tests
  // ═══════════════════════════════════════════════

  describe( 'Projectors', () => {
    it( 'Given EntityCreated event then upserts with full data + accountId + ownerId', async () => {
      const event = {
        data: { name: 'Test', status: 'active' },
        metadata: { accountId: 'account-1', userId: 'user-1' },
        stream: 'MyEntity-entity-1'
      };

      // Execute projector
      // ...

      expect( mockCollection.upsert ).toHaveBeenCalledWith( 'entity-1', {
        name: 'Test',
        status: 'active',
        accountId: 'account-1',
        ownerId: 'user-1'
      });
    });

    it( 'Given EntityEdited event then upserts with partial data', async () => {
      // Test partial update
    });
  });

  // ═══════════════════════════════════════════════
  // Query Tests
  // ═══════════════════════════════════════════════

  describe( 'Queries', () => {
    it( 'Given authenticated user when search then returns filtered results', async () => {
      // Test query handler with user context
    });

    it( 'Given no user when query then throws UnauthorizedError', async () => {
      // Test authentication requirement
    });
  });
});
```

## Test Data Patterns

### Event Factory

```typescript
const createEvent = ( type: string, data: any, overrides: any = {} ) => ({
  id: `event-${Date.now()}`,
  type,
  data,
  stream: `MyEntity-${overrides.entityId || 'test-entity-1'}`,
  metadata: {
    accountId: overrides.accountId || 'test-account-1',
    correlationId: overrides.correlationId || 'test-correlation-1',
    userId: overrides.userId || 'test-user-1',
    ...overrides.metadata
  },
  ...overrides
});
```

### Mock Ports

```typescript
const createMockPorts = () => ({
  logger: {
    createLoggerInstance: () => ({
      log: jest.fn(),
      error: jest.fn(),
      warn: jest.fn()
    })
  },
  database: {
    getCollection: jest.fn(),
    onStarted: jest.fn()
  },
  eventsourcing: {
    routeCommandHandler: jest.fn(),
    routeEventHandler: jest.fn(),
    PolicyBuilder: jest.fn()
  },
  endpoints: {
    fetch: jest.fn()
  }
});
```

## Commands

```bash
yarn test                        # All tests
npx jest <path> --verbose        # Specific file
yarn test -- --watchAll          # Watch mode
```

## Execution Context in Tests

Tests that execute commands (directly or via policy handlers) need an execution context to simulate the HTTP middleware context that exists at runtime. Wrap command execution in `runWithExecutionContext`:

```typescript
import { runWithExecutionContext } from '@bett3r-dev/pv3';

// Wrap the command or policy handler call
await runWithExecutionContext(
  { accountId: 'test-account', userId: 'test-user', correlationId: 'test-corr' },
  async () => {
    // Execute command or policy handler here
    await ports.eventsourcing.executeCommand( MyAggregate( ports ), 'DoSomething' )({
      params: { id: 'entity-1' },
      body: { name: 'Test' }
    });
  }
);
```

**When to use:** Any test that calls `executeCommand` or triggers a policy handler that calls `executeCommand` internally. The context provides `accountId`, `userId`, `correlationId`, and optionally `causationId` — the same values that the ALS middleware and PolicyBuilder set automatically at runtime.

**Note:** For policy tests, if you invoke the policy handler directly with an event that has `metadata.accountId` and `metadata.userId`, the PV3 PolicyBuilder wrapper automatically sets up the execution context from the event metadata. You only need manual `runWithExecutionContext` when calling `executeCommand` outside of a PolicyBuilder-wrapped handler.

## Critical Constraints

- **Every invariant/error test must assert the specific error code** — `.rejects.toBeDefined()` or `.rejects.toThrow()` without a code check is not acceptable when the test title or spec names a specific error code. Use `expect(promise).rejects.toMatchObject({ code: 'ERROR_CODE' })` or the project's `expectRejectsWithCode` helper. This applies to both hand-thrown `BadRequestError`s AND framework invariants — e.g. `invariants.stateExists()` rejects with `{ code: 'STATE_NOT_EXISTS' }` and must be asserted the same way.
- **Co-located tests** — `*.test.ts` next to source file, NOT in separate directory
- **Use `createTestPorts()`** — From `@bett3r-dev/pv3-library-tests` when available
- **Mock external dependencies** — Client library, external APIs, ports.endpoints
- **Test real domain logic** — Don't mock the component under test
- **Given/When/Then separators** — Use `═══` comment separators for readability
- **No `*.integration.test.ts` filenames in the co-located unit suite** — that suffix may be excluded by the unit `jest.config.js`; cross-aggregate integration suites must use a different suffix (e.g. `*.flows.test.ts`) or live in the host repo's integration-tests package
- **No vacuous zero-side-effect assertions** — `expect(calls).toHaveLength(0)` is only meaningful after the policy fires; assert *after* `testPolicy(...).when(...).then(...)`, not before
- **Import production functions, don't re-implement them** — If a function is exported (e.g. a computed-amount or rate helper), import and call it; inline re-implementations silently diverge on rounding and edge cases

## What to Test

| Component | Test Focus |
|-----------|-----------|
| Aggregate | Command handlers: correct events emitted, state transitions, edge cases |
| Policy | Event handlers: correct side effects, error handling, idempotency |
| Readmodel | Projectors: correct upserts; Queries: auth, filtering, pagination |

## Final Checklist

- [ ] Test file co-located: `<component>.test.ts`
- [ ] `describe` blocks group by precondition
- [ ] Given/When/Then structure in each test
- [ ] `═══` separators between test groups
- [ ] Mocks reset in `beforeEach`
- [ ] External dependencies mocked
- [ ] Happy path tested
- [ ] Edge cases tested (null state, missing data, auth failures)
- [ ] Every error/invariant test that names a code in its title asserts that exact code in the body
- [ ] Tests pass: `npx jest <path> --verbose`
