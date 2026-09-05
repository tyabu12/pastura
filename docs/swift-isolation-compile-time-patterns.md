# Swift isolation — the annotation traps the compiler reports

Companion to `.claude/rules/swift-isolation.md`, which keeps only the silent runtime traps (Patterns 6–8). The five patterns here all produce a **diagnostic** under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; they are collected so that the message, which fires at the *use* site rather than the declaration, can be mapped back to its cause. Moved out of the always-loaded rule in #1519.

Per CLAUDE.md, types in `Models/`, `LLM/`, `Engine/`, `Data/` are marked `nonisolated` at the type level. Conformances declared in `App/` (and any default-MainActor layer) hit MainActor inference in five patterns that share one root cause and surface in two diagnostic forms:

- **Conformance-site** (Pattern 1): `conformance of '<Type>' to protocol '<Protocol>' crosses into main actor-isolated code and can cause data races`.
- **Use-site** (Patterns 2–5): fires at the test, generic collection, Sendable closure callsite, or conformance-lookup callsite. Patterns 2–4 surface as `Call to main actor-isolated <thing> in a synchronous nonisolated context`; Pattern 5 as `main actor-isolated conformance of '<Type>' to '<Protocol>' cannot be used in nonisolated context`.

## Pattern 1 — Protocol-extension default impl + escaping closure

A default impl on an extension of a `nonisolated` protocol that builds escaping closures (`AsyncThrowingStream { continuation in ... }`, a standalone `Task { }`, `continuation.onTermination = ...`) needs explicit `nonisolated`. Pure `async` forwarding impls do not.

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

The escaping closure is sufficient, not necessary — the discriminator is sync-vs-`async`. `LLMService.knownTurnMarkers`, a plain synchronous computed property, still breaks every `nonisolated` conformer without `nonisolated` (measured by dropping the annotation, #1422), while the `async` members on the same extension carry none.

Reference: `Pastura/Pastura/LLM/LLMService.swift`.

## Pattern 2 — Value type with custom witness

An App/ value type conforming to `Hashable` / `Equatable` / `Codable` **with hand-written witness methods** (custom `static func ==`, `func hash(into:)`, `init(from:)`, `encode(to:)`) needs `nonisolated` at type level. Auto-synthesized witnesses are nonisolated regardless of enclosing isolation — but conformance lookup itself can still be MainActor-isolated (Pattern 5).

```swift
nonisolated struct RouteHint<T: Hashable & Sendable>: Hashable, Sendable {
  // custom == and hash(into:) impls — without `nonisolated`,
  // test sites fail with "Call to main actor-isolated operator '=='"
}
```

Reference: `Pastura/Pastura/App/RouteHint.swift`.

## Pattern 3 — Sibling-file extension on a `nonisolated` type

Splitting a `nonisolated` type into sibling files (`Foo.swift` + `Foo+Parser.swift`) requires `nonisolated` on the **extension itself**; methods in a plain `extension` inherit MainActor and break calls from the main file. The diagnostic fires at the **call site** in the main file. Applies to any sibling-file split of a `nonisolated` Engine/LLM/Models/Data type, and compounds with Pattern 2 when the extension adds custom witnesses.

```swift
// Foo+Parser.swift
nonisolated extension Foo {
  func tokenize(_ s: String) -> [Token] { ... }
}
```

Reference: `Pastura/Pastura/Engine/ConditionEvaluator+Parser.swift`.

The call-site diagnostic fires only when a `nonisolated` caller exists; with MainActor-only callers
the plain-`extension` version compiles clean and traps at runtime if the inherited-MainActor
member's body escapes the main actor (measured 2026-09-05,
`App/KMP/SharedEngineRunner+AppRunPath.swift`) — restate `nonisolated` on the extension's members
regardless of who calls it today.

## Pattern 4 — Reference type adding sync methods alongside `Sendable` protocol async

An App/ `final class` conforming to a `Sendable` protocol compiles fine while all methods are `async` — the hop conceals implicit MainActor binding. **Adding new synchronous instance methods** forces the class to MainActor and breaks `nonisolated` callers; the class can compile for a long time until someone adds a sync accessor.

```swift
nonisolated final class URLSessionModelDownloader: ModelDownloader, @unchecked Sendable {
  // protocol's async methods + new sync accessors (captureResumeData, cachedResumeData)
}
```

Reference: `Pastura/Pastura/App/ModelDownloader.swift`.

## Pattern 5 — Auto-synth Equatable / Hashable conformance lookup on a default-MainActor type

An App/ struct or enum with **auto-synthesized** `Equatable` / `Hashable`: the witnesses are nonisolated (Pattern 2), but the **conformance lookup** is MainActor-isolated. A `nonisolated` caller of `==` / `hashValue` gets `main actor-isolated conformance of '<Type>' to 'Equatable' cannot be used in nonisolated context` — at the use site (e.g. `#expect(x == .alice)` in a nonisolated test), not the declaration.

Fix order:

1. **Mark the test suite `@MainActor`** — smallest scope; MainActor can still call nonisolated methods, so the suite keeps exercising the production callers. Pastura's default.
2. **Mark the enum / extension `nonisolated`** — broader; use only with ≥2 unrelated nonisolated call sites.

Reference: `Pastura/PasturaTests/Views/ModelRowAccessibilityTests.swift` carries `@MainActor`; `SheepAvatar.Character` keeps its default isolation.

Two production shapes with the same cause, both build errors:

| Shape | Error | Fix |
|---|---|---|
| `nonisolated` type conforms to `Equatable`/`Hashable` and a stored member's own conformance is MainActor-isolated | `main actor-isolated conformance of 'X' to 'Equatable' cannot be used in nonisolated context` | Drop the conformance; compare members from MainActor. Marking `X` `nonisolated` is fix-order 2. |
| `nonisolated enum`/type whose `static let` initializers read MainActor-isolated statics | `Main actor-isolated default value in a nonisolated context` | Don't mark the namespace `nonisolated`; annotate only the closure that needs it. |

The `let`-read exemption is module-local, so a nonisolated *test* helper needs `@MainActor` where the equivalent in-module production closure does not — `DesignTokensTests+DarkMode.swift`'s `sRGBComponentsMatch` is the worked example.
