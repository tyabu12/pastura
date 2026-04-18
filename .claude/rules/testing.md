---
paths:
  - "Pastura/PasturaTests/**"
---

# Testing Rules

## Swift Testing Parallelism

Tests that create `SimulationRunner` (or any type that spawns `Task` + `AsyncStream`
internally) **must** use `@Suite(.serialized)` to avoid test-process crashes from
concurrent Task/AsyncStream cleanup. This applies to integration tests that consume
`AsyncStream<SimulationEvent>` via `for await`.

Individual unit tests (e.g., handler tests with `MockLLMService`) are safe to run
in parallel because they await the handler directly without AsyncStream.

## `.timeLimit` Trait on Every Suite (CI-Hang Diagnostic)

Every Swift Testing suite under `Pastura/PasturaTests/` **must** carry
`.timeLimit(.minutes(1))` (Swift Testing's minimum; `.seconds` is not supported).
A hung test then fails individually at the 1-minute boundary with a
`failed (timed out)` line naming the specific test, instead of silently
eating the CI job's 15-minute wall-clock and corrupting the xcresult bundle.
This is a load-bearing diagnostic — do not remove it from existing suites,
and do not skip it when adding new ones.

Apply to both suite forms:

- **Explicit `@Suite(...)`**: include the trait alongside any existing traits.
  ```swift
  @Suite(.timeLimit(.minutes(1)))                              struct FooTests { ... }
  @Suite(.serialized, .timeLimit(.minutes(1)))                 struct BarTests { ... }
  @Suite(.serialized, .timeLimit(.minutes(1))) @MainActor      struct BazTests { ... }
  @Suite("Display Name", .serialized, .timeLimit(.minutes(1))) struct QuxTests { ... }
  ```
- **Implicit suite** (`struct XxxTests` with `@Test` methods and no `@Suite`):
  Swift Testing treats it as an implicit suite; without the attribute there
  is no place to hang the trait. Promote to explicit `@Suite`:
  ```swift
  @Suite(.timeLimit(.minutes(1)))
  struct XxxTests { @Test ... }
  ```

**Exceptions (document inline when skipping):**

- Integration suites gated out of CI by env var (`OLLAMA_INTEGRATION`,
  `LLAMACPP_INTEGRATION`) are exempt from the suite-level 1-minute cap
  because it would be resolved as the tighter bound and silently break
  local integration runs against real LLMs. Each `@Test` in these suites
  **must** carry its own `.timeLimit(.minutes(2-5))` sized for real-LLM
  inference — without a per-test bound, a hung integration test would be
  unbounded by *both* rules. (See `OllamaIntegrationTests.swift` and
  `LlamaCppIntegrationTests.swift` for the current shape.)
- Helper-only files (no `@Test` / `@Suite` declarations, e.g.
  `EngineTestHelpers.swift`) don't need the trait.

**If a unit test legitimately needs more than 1 minute:** override at the
`@Test` level (`@Test(.timeLimit(.minutes(N))) func ...`). Swift Testing
resolves the tightest-bound among suite + test traits, so a per-test widen
is unusual — consider first whether the test is doing too much (split it,
mock heavier work, etc.).

**History:** PR #134 (Issue #131) introduced this rule after a
cancel-before-store race in `SuspendController.awaitResume()` silently
hung one test for 15 minutes on CI. See `memory/project_ci_timeout_investigation.md`.

## `-only-testing` and Swift Testing

When using `-only-testing` with `xcodebuild`, prefer **suite-level** targeting
(e.g., `PasturaTests/SimulationRunnerTests`) over individual test names
(e.g., `PasturaTests/SimulationRunnerTests/myTest`). Individual Swift Testing
(`@Test`) functions may not match reliably, causing tests to silently not run
while `xcodebuild` still reports `TEST SUCCEEDED`.

**Why:** Swift Testing uses a different identifier scheme than XCTest. `xcodebuild`
resolves zero matching tests and reports success (0 failures = `TEST SUCCEEDED`).
This does NOT affect XCTest (`func testXxx()` in `XCTestCase`), which individual
targeting works correctly for.

**Verify:** Always check the test count in the output to confirm tests actually ran.

## MockLLMService Usage

- Always call `try await mock.loadModel()` before running any code that calls
  `LLMService.generate()`.
- Provide exactly the number of responses expected. `MockLLMService` throws when
  exhausted — this is intentional to catch over/under-provisioning.
- Use `mock.capturedPrompts` to verify prompt content in tests.

## Shared Test Helpers (`EngineTestHelpers.swift`)

- **`EventCollector`**: Thread-safe event collector for `@Sendable` emitter closures.
  Do not capture mutable local variables (e.g., `var events: [...]`) in `@Sendable`
  closures — Swift 6 strict concurrency rejects this as a potential data race.
- **`makeTestScenario(agentNames:rounds:phases:context:extraData:)`**: Convenience
  factory for test scenarios. Defaults: 3 agents (`["Alice", "Bob", "Charlie"]`),
  1 round, empty phases. Use this instead of constructing `Scenario` manually.
- **`makePhaseContext(scenario:phaseIndex:llm:collector:)`**: Convenience factory
  for `PhaseContext`. Bundles scenario, phase, LLM, and emitter for handler tests.
  Use this instead of constructing `PhaseContext` manually.
