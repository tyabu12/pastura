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

## MockLLMService Usage

- Always call `try await mock.loadModel()` before running any code that calls
  `LLMService.generate()`.
- Provide exactly the number of responses expected. `MockLLMService` throws when
  exhausted — this is intentional to catch over/under-provisioning.
- Use `mock.capturedPrompts` to verify prompt content in tests.

## EventCollector

Use the shared `EventCollector` (in `EngineTestHelpers.swift`) for collecting
`SimulationEvent` from `@Sendable` emitter closures. Do not capture `var` arrays
in `@Sendable` closures — Swift 6 strict concurrency forbids this.
