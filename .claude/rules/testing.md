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
