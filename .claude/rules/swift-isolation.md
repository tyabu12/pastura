# Swift Isolation Rules

**Scope**: `nonisolated` annotation traps under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only. Broader actor isolation topics (`@MainActor` binding, `Sendable` conformance design, actor reentrancy) are out of scope — keep those in CLAUDE.md or a separate rule.

Per CLAUDE.md, types in `Models/`, `LLM/`, `Engine/`, `Data/` are marked `nonisolated` at the type level. Conformances declared in `App/` (and any default-MainActor layer) hit MainActor inference traps in four specific patterns. All four fail with the same diagnostic family:

```
Call to main actor-isolated <thing> in a synchronous nonisolated context
```

The diagnostic fires at the **use site** (test, generic collection, Sendable closure), not the declaration site — easy to miss when only building.

## Pattern 1 — Protocol-extension default impl + escaping closure

Default impl on an extension of a `nonisolated` protocol that builds escaping closures (`AsyncThrowingStream { continuation in ... }`, standalone `Task { }`, `continuation.onTermination = ...`) needs explicit `nonisolated`. Pure `async` forwarding impls do NOT.

```swift
extension LLMService {
  // Pure forwarding — unmarked, works.
  public func generateWithMetrics(...) async throws -> GenerationResult {
    let text = try await generate(...)
    return GenerationResult(text: text, completionTokens: nil)
  }

  // Builds AsyncThrowingStream + Task — needs `nonisolated`.
  nonisolated public func generateStream(...) -> AsyncThrowingStream<LLMStreamChunk, Error> {
    AsyncThrowingStream { continuation in ... }
  }
}
```

Reference: `Pastura/Pastura/LLM/LLMService.swift`.

## Pattern 2 — Value type with custom witness

App/ value type conforming to `Hashable` / `Equatable` / `Codable` **with hand-written witness methods** (custom `static func ==`, `func hash(into:)`, `init(from:)`, `encode(to:)`) needs `nonisolated` at type level. Auto-synthesized conformances emit nonisolated witnesses regardless of enclosing isolation, so they don't need the annotation.

```swift
nonisolated struct RouteHint<T: Hashable & Sendable>: Hashable, Sendable {
  // custom == and hash(into:) impls — without `nonisolated`,
  // test sites fail with "Call to main actor-isolated operator '=='"
}
```

Reference: `Pastura/Pastura/App/RouteHint.swift`.

## Pattern 3 — Sibling-file extension on a `nonisolated` type

Splitting a `nonisolated` type into sibling files (e.g., `Foo.swift` + `Foo+Parser.swift`) requires `nonisolated` on the **extension itself**, even though the underlying struct is annotated. Methods declared in a plain `extension` inherit MainActor and break calls from the main file.

```swift
// Foo+Parser.swift
nonisolated extension Foo {
  func tokenize(_ s: String) -> [Token] { ... }
}
```

The diagnostic fires at the **call site** in the main file, not the extension declaration. Applies to ANY sibling-file split of a `nonisolated` Engine/LLM/Models/Data type — not just those involving closures (Pattern 1) — and compounds with Pattern 2 when the extension also adds custom witnesses.

Reference: `Pastura/Pastura/Engine/ConditionEvaluator+Parser.swift`.

## Pattern 4 — Reference type adding sync methods alongside `Sendable` protocol async

An App/ `final class` conforming to a `Sendable` protocol compiles fine when all methods are `async` — the hop conceals implicit MainActor binding. **Adding new synchronous instance methods** forces the class to MainActor and breaks `nonisolated` callers. More insidious than Pattern 2: the class can compile fine for a long time until someone adds a sync accessor.

```swift
nonisolated final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // protocol's async methods + new sync accessors (captureResumeData, cachedResumeData)
}
```

Reference: `Pastura/Pastura/App/ModelDownloader.swift` (class declaration ~L92).
