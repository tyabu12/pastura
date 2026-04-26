# LLM Layer Rules

## Protocol-extension default implementations + actor isolation

When providing a default implementation in an extension of a `nonisolated`
protocol, mark the default impl `nonisolated` explicitly **if the body
builds escaping closures** — `AsyncThrowingStream { continuation in ... }`,
standalone `Task { }`, `continuation.onTermination = ...`.

Under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, those
closures infer MainActor isolation and break conformance for
`nonisolated` conforming types (`LlamaCppService`, `MockLLMService`, ...).

**Diagnostic:** compiler error

```
conformance of '<Type>' to protocol '<Protocol>' crosses into
main actor-isolated code and can cause data races
```

fires at the conformance site, **not** at the default impl itself — the
surface symptom is a type that previously compiled against the protocol
suddenly refusing to.

**Not required for pure `async` forwarding impls.** A default impl that
only does `try await otherMethod(...)` without closure capture / Task
creation inherits the protocol's `nonisolated` declaration and works
unannotated.

### Example

`Pastura/Pastura/LLM/LLMService.swift` has both patterns:

```swift
extension LLMService {
  // Pure forwarding — unmarked, works.
  public func generateWithMetrics(
    system: String, user: String
  ) async throws -> GenerationResult {
    let text = try await generate(system: system, user: user)
    return GenerationResult(text: text, completionTokens: nil)
  }

  // Builds an AsyncThrowingStream + Task + onTermination closure —
  // needs explicit `nonisolated` to avoid MainActor inference.
  nonisolated public func generateStream(
    system: String, user: String
  ) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        // ...
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
```
