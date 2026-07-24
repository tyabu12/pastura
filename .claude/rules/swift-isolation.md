# Swift Isolation Rules

**Scope**: `nonisolated` annotation traps + the `nonisolated async` executor-inheritance trap under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (with `SWIFT_APPROACHABLE_CONCURRENCY = YES`). Patterns 1–5 are **compile-time annotation traps** (a diagnostic fires); Patterns 6–7 are **silent runtime traps** (no diagnostic — a UI freeze and an executor-precondition trap respectively). Broader actor isolation topics (`@MainActor` binding, `Sendable` conformance design, actor reentrancy) are out of scope — keep those in CLAUDE.md or a separate rule.

Per CLAUDE.md, types in `Models/`, `LLM/`, `Engine/`, `Data/` are marked `nonisolated` at the type level. Conformances declared in `App/` (and any default-MainActor layer) hit MainActor inference traps in five specific patterns. The five share the same root cause (MainActor inference) but surface in two diagnostic forms:

- **Conformance-site** (Pattern 1): `conformance of '<Type>' to protocol '<Protocol>' crosses into main actor-isolated code and can cause data races` — a previously-compiling type suddenly refusing to build.
- **Use-site** (Patterns 2–5): fires at the test, generic collection, Sendable closure callsite, or conformance-lookup callsite — not the declaration. Patterns 2–4 surface as `Call to main actor-isolated <thing> in a synchronous nonisolated context`; Pattern 5 surfaces as `main actor-isolated conformance of '<Type>' to '<Protocol>' cannot be used in nonisolated context`.

Easy to miss because the diagnostic doesn't point at the type definition. **Patterns 6–7 are the exception to this framing** — they produce *no diagnostic at all*. They are grouped here because they share the root cause: a member that fails to land off-main under default-MainActor isolation.

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

Reference: `Pastura/PasturaTests/Views/ModelRowAccessibilityTests.swift`
carries `@MainActor` on the suite; `SheepAvatar.Character` keeps its
default-MainActor isolation.

## Pattern 6 — `nonisolated async` runs on the caller's executor (silent UI freeze)

Under `SWIFT_APPROACHABLE_CONCURRENCY = YES` (which enables the
`NonisolatedNonsendingByDefault` upcoming feature, SE-0461), a
`nonisolated async` function does **not** hop to the global executor on
its own — it runs on the **caller's** executor. So a `nonisolated async`
method `await`-ed from a MainActor context runs **on the MainActor**, and
any synchronous blocking work inside (a multi-second C call, heavy CPU)
**freezes the UI**. The type-level `nonisolated` on the enclosing class
does NOT save it: that annotation governs the *default isolation* of
members, not which executor an `async` body runs on.

Unlike Patterns 1–5 there is **no compiler diagnostic** — it builds clean
and the freeze only shows on a real device. The same method is safe when
reached from an already-off-main caller (e.g. inside an Engine `Task {}`
producer), which is why a sibling `nonisolated async` can look fine while
this one freezes.

### Fix

Mark the blocking `async` method `@concurrent` (the SE-0461 pairing
attribute) to force its body onto the global concurrent executor
regardless of caller.

```swift
nonisolated final class LlamaCppService: ... {
  // Without @concurrent this runs on the MainActor caller
  // (SimulationViewModel.run) and the synchronous multi-GB GGUF load
  // freezes the UI on the scenario→simulation transition.
  @concurrent private func loadModelInternal(...) async throws {
    guard let model = llama_model_load_from_file(...) else { ... }  // blocking C call
    _model = model  // nonisolated(unsafe) — no Sendable crossing
  }
}
```

Prefer `@concurrent` over wrapping the body in `Task.detached` when it
touches non-`Sendable` state (e.g. C `OpaquePointer`s): `@concurrent` only
changes the executor, so nothing crosses an isolation boundary, whereas
returning a non-`Sendable` value out of a detached task is a Swift 6 error.
`@concurrent` on a protocol witness does not change the protocol
requirement's signature, so sibling conformances need no annotation.

Reference: `Pastura/Pastura/LLM/LlamaCppService.swift` — `loadModelInternal`
and `unloadModel` carry `@concurrent` (#822).

## Pattern 7 — Conforming to an *unannotated* ObjC protocol from a default-MainActor layer

"It's UIKit" does **not** imply MainActor. Many ObjC delegate / data-source
protocols are imported **nonisolated**, so the framework may call the witness
from any thread. A `Views/` or `App/` type conforming to one inherits default
MainActor isolation, which puts an executor precondition on the `@objc` thunk:
compiles clean, then traps at runtime the first time the framework calls
off-main. Silent like Pattern 6 — no diagnostic points at it.

**Do not infer this from the framework name, and do not trust an agent's
assertion either way** — a plan critic and a review agent reached opposite
conclusions on `UIActivityItemSource`; the right one arrived with grep evidence
that turned out to be vacuous (see below). **Ask the compiler**, which is the
only authority here. Force it to print the requirement's type:

```swift
// probe.swift — typecheck only, never added to the target
import UIKit
nonisolated func probe(_ s: any <ProtocolUnderTest>, _ control: any UIScrollViewDelegate) {
  let _: Int = s.<someRequirement>          // error prints the requirement's real type
  let _: Int = control.scrollViewDidScroll  // known-MainActor control, always run it
}
```

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun swiftc -typecheck -swift-version 6 -default-isolation MainActor \
  -target arm64-apple-ios18.0-simulator -sdk "$SDK" probe.swift 2>&1 | grep "cannot convert"
```

`@MainActor` in the printed type ⇒ isolated; its absence ⇒ **nonisolated ⇒ mark
the conforming type `nonisolated`**. Observed 2026-07-24:
`UIActivityItemSource.activityViewControllerPlaceholderItem` prints
`(UIActivityViewController) -> Any` while the control prints
`(@MainActor (UIScrollView) -> Void)?`.

**The control line is load-bearing — do not drop it.** Header/apinotes greps are
the obvious check and they are *worthless* here: `UI_ACTOR` appears on no UIKit
protocol (it is not even defined in `UIKitDefines.h`), and the apinotes entries
carry no `SwiftMainActor`, so both "confirm" nonisolated for *every* protocol
including genuinely-MainActor ones. Any check that cannot redden on the control
is measuring nothing. Note also that conformance direction does not discriminate
either: a `nonisolated` type conforms to a `@MainActor` protocol without
complaint, so "it compiled" proves nothing.

Pair `nonisolated` with a `Sendable` conformance when every stored member is an
immutable `Sendable` constant — legal on a `final class` whose superclass is
`NSObject` — so a later `var` fails the build instead of quietly re-opening the
race. Drop `@MainActor` from the type's test suite as well: the suite then stops
compiling if the isolation ever regresses, which is a real guard rather than a
restatement.

Reference: `Pastura/Pastura/Views/Components/ShareCaptionItemSource.swift` (#1263).
