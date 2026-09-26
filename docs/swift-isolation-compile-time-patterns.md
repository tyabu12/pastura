# Swift isolation — the annotation traps the compiler reports

Companion to `.claude/rules/swift-isolation.md`, which keeps only the silent runtime traps (Patterns 6–8). The patterns here (1–5, and 9) all produce a **diagnostic** under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; they are collected so that the message, which fires at the *use* site rather than the declaration, can be mapped back to its cause. Patterns 1–5 moved out of the always-loaded rule in #1519.

Per CLAUDE.md, types in `Models/`, `LLM/`, `Engine/`, `Data/` are marked `nonisolated` at the type level. Conformances declared in `App/` (and any default-MainActor layer) hit MainActor inference in patterns that share one root cause and surface in two diagnostic forms:

- **Conformance-site** (Patterns 1 and 9): `conformance of '<Type>' to protocol '<Protocol>' crosses into main actor-isolated code and can cause data races`.
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

The runtime half of this trap — MainActor-only callers, no diagnostic, trap when the body escapes
the main actor — is in `.claude/rules/swift-isolation.md` § Pattern 6 note.

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

## Pattern 9 — `Shape` conformer relying on inferred `nonisolated` (toolchain skew)

A `struct X: Shape` in a default-MainActor layer (`Views/`). Xcode 26.4 inferred the type `nonisolated` from the conformance, so it built clean; **Xcode 27 infers MainActor** and rejects it at the declaration with the Pattern-1 conformance-site message. CI pins Xcode 26.4, so **CI cannot see this one** — it fails only on a machine that has moved to Xcode 27. No gate enforces the explicit annotation until CI moves to Xcode 27; this entry is the only guard.

**Fix**: write `nonisolated struct X: Shape` explicitly. `Shape` is `Sendable` and SwiftUI may call `path(in:)` off the main actor, so an isolated (`@MainActor`) conformance is wrong; `nonisolated` builds on both toolchains. The type then cannot read MainActor-isolated statics in its own static initializers — inline the literal and pin it against the token in a test.

Reference: `BubbleShape` in `Views/Components/ChatBubble.swift` (and `ChatBubbleTests`' `Radius` pin), `CheckmarkPath` in `Views/ModelSelection/Components/CheckBadge.swift` (#1702).
