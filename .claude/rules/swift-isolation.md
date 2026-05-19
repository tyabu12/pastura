# Swift Isolation Rules

**Scope**: `nonisolated` annotation traps under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only. Broader actor isolation topics (`@MainActor` binding, `Sendable` conformance design, actor reentrancy) are out of scope — keep those in CLAUDE.md or a separate rule.

Per CLAUDE.md, types in `Models/`, `LLM/`, `Engine/`, `Data/` are marked `nonisolated` at the type level. Conformances declared in `App/` (and any default-MainActor layer) hit MainActor inference traps in five specific patterns. The five share the same root cause (MainActor inference) but surface in two diagnostic forms:

- **Conformance-site** (Pattern 1): `conformance of '<Type>' to protocol '<Protocol>' crosses into main actor-isolated code and can cause data races` — a previously-compiling type suddenly refusing to build.
- **Use-site** (Patterns 2–5): fires at the test, generic collection, Sendable closure callsite, or conformance-lookup callsite — not the declaration. Patterns 2–4 surface as `Call to main actor-isolated <thing> in a synchronous nonisolated context`; Pattern 5 surfaces as `main actor-isolated conformance of '<Type>' to '<Protocol>' cannot be used in nonisolated context`.

Easy to miss because the diagnostic doesn't point at the type definition.

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

App/ value type conforming to `Hashable` / `Equatable` / `Codable` **with hand-written witness methods** (custom `static func ==`, `func hash(into:)`, `init(from:)`, `encode(to:)`) needs `nonisolated` at type level. Auto-synthesized conformance **witnesses** are nonisolated regardless of enclosing isolation, so they don't need the annotation. **But conformance lookup itself can still be MainActor-isolated — see Pattern 5.**

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

## Pattern 5 — Auto-synth Equatable / Hashable conformance lookup on default-MainActor type

App/ value type (struct / enum) under default-MainActor isolation with
**auto-synthesized** `Equatable` / `Hashable` conformance: the synthesized
**witnesses** are nonisolated (per Pattern 2), but the **conformance
lookup** itself is MainActor-isolated. A `nonisolated` caller of `==` /
`hashValue` triggers `main actor-isolated conformance of '<Type>' to
'Equatable' cannot be used in nonisolated context`.

Diagnostic fires at the **use site** (e.g., `#expect(x == .alice)` in
a nonisolated test), not the declaration. Easy to mis-attribute as
Pattern 2 (which says "auto-synth doesn't need the annotation").

### Fix order

1. **Mark the test suite `@MainActor`** — smallest scope. MainActor can
   still call nonisolated methods, so the suite continues to exercise
   the production nonisolated callers correctly. This is Pastura's default.
2. **Mark the enum / extension `nonisolated`** — broader scope, releases
   the conformance for any future nonisolated caller. Use only with
   ≥2 unrelated nonisolated call sites.

Reference: `Pastura/PasturaTests/Components/ModelRowAccessibilityTests.swift`
carries `@MainActor` on the suite; `SheepAvatar.Character` keeps its
default-MainActor isolation.
