# Swift Isolation — the traps with no diagnostic

**Scope**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Types in `Models/`, `LLM/`, `Engine/`, `Data/` are `nonisolated` at the type level (CLAUDE.md). The five annotation traps that **do** raise a compiler diagnostic (protocol-extension default impls, custom witnesses, sibling-file extensions, sync methods on a `Sendable` class, auto-synthesized conformance lookup) are catalogued in `docs/swift-isolation-compile-time-patterns.md` — the build points you at them. This rule carries only the three that build clean and fail at runtime.

## Pattern 6 — `nonisolated async` runs on the caller's executor (silent UI freeze)

Under Approachable Concurrency (SE-0461 `NonisolatedNonsendingByDefault`), a `nonisolated async` function does **not** hop to the global executor — it runs on the **caller's**. So an `await` from a MainActor context runs the body **on the MainActor**, and any synchronous blocking work inside (a multi-second C call, heavy CPU) freezes the UI. Type-level `nonisolated` does not save it: that governs members' default isolation, not which executor an `async` body runs on. The same method is safe when reached from an already-off-main caller, which is why a sibling can look fine while this one freezes.

**Fix**: mark the blocking `async` method `@concurrent` to force its body onto the global concurrent executor regardless of caller. Prefer it over `Task.detached` when the body touches non-`Sendable` state (C `OpaquePointer`s): `@concurrent` only changes the executor, so nothing crosses an isolation boundary. `@concurrent` on a protocol witness does not change the requirement's signature, so sibling conformances need no annotation.

```swift
nonisolated final class LlamaCppService: ... {
  // Without @concurrent this runs on the MainActor caller and the
  // synchronous multi-GB GGUF load freezes the scenario→simulation transition.
  @concurrent private func loadModelInternal(...) async throws {
    guard let model = llama_model_load_from_file(...) else { ... }  // blocking C call
    _model = model  // nonisolated(unsafe) — no Sendable crossing
  }
}
```

Reference: `LLM/LlamaCppService.swift` — `loadModelInternal` and `unloadModel`.

**Sibling-file extensions of a `nonisolated` type re-open this.** `nonisolated` on the type governs
members declared in its body; an `extension` in another file defaults back to MainActor. With a
`nonisolated` caller the compiler says so (`docs/swift-isolation-compile-time-patterns.md`
Pattern 3); with MainActor-only callers it compiles clean and traps (`swift_task_isCurrentExecutor`)
the moment the body runs off the main actor — an `AsyncStream` build closure, a `Task`. Restate
`nonisolated` on every member of the extension. Measured 2026-09-05,
`App/KMP/SharedEngineRunner+AppRunPath.swift`.

## Pattern 7 — Conforming to an *unannotated* ObjC protocol from a default-MainActor layer

"It's UIKit" does **not** imply MainActor. Many ObjC delegate / data-source protocols are imported **nonisolated**, so the framework may call the witness from any thread. A `Views/` or `App/` type conforming to one inherits default MainActor isolation, which puts an executor precondition on the `@objc` thunk: compiles clean, traps at runtime the first time the framework calls off-main.

**Do not infer this from the framework name, and do not trust an agent's assertion either way — ask the compiler.** Force it to print the requirement's type, with a known-MainActor control in the same probe:

```swift
// probe.swift — typecheck only, never added to the target
import UIKit
nonisolated func probe(_ s: any <ProtocolUnderTest>, _ control: any UIScrollViewDelegate) {
  let _: Int = s.<someRequirement>          // error prints the requirement's real type
  let _: Int = control.scrollViewDidScroll  // known-MainActor control — must print @MainActor
}
```

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun swiftc -typecheck -swift-version 6 -default-isolation MainActor \
  -target arm64-apple-ios18.0-simulator -sdk "$SDK" probe.swift 2>&1 | grep "cannot convert"
```

`@MainActor` in the printed type ⇒ isolated; its absence ⇒ nonisolated ⇒ **mark the conforming type `nonisolated`**. **The control line is load-bearing**: header / apinotes greps "confirm" nonisolated for every UIKit protocol, including genuinely-MainActor ones, so any check that cannot redden on the control is measuring nothing. "It compiled" proves nothing either — a `nonisolated` type conforms to a `@MainActor` protocol without complaint.

Pair `nonisolated` with `Sendable` when every stored member is an immutable `Sendable` constant, so a later `var` fails the build instead of quietly re-opening the race; and drop `@MainActor` from the type's test suite so the suite stops compiling if the isolation ever regresses.

Reference: `Views/Components/ShareCaptionItemSource.swift` (`UIActivityItemSource` is nonisolated; measured 2026-07-24).

A Kotlin/Native-exported protocol is the same case, not a UIKit one: `LLMBackend` imports as an
unannotated Obj-C protocol and `knownTurnMarkers` is read from `Dispatchers.Default`, so a
Stage-5 adapter in `App/KMP/` conforming to it must be `nonisolated`. Every conformer under
`Pastura/Pastura/App/KMP/` carries it (`LLMServiceBackend.swift`, `EngineLoggerBridge` /
`LanguageDetectorBridge`) — follow that precedent, not the compiler's silence. Measured 2026-08-31 by
`scripts/kmp/probe-pattern7-isolation.sh`, which automates the probe above against the staged
framework for all four seam protocols (`LLMBackend`, `LanguageDetector`, `EngineLogger`,
`RandomSource`), control line included — all four import unannotated. Re-run the script by hand
before merging a Kotlin bump that regenerates the umbrella header; `kmp-nightly.yml` also runs it
nightly as a regression step (#1661), a backstop up to 24 h late, not the pre-merge check.

## Pattern 8 — MainActor-inferred closure handed to a framework callback

A framework initializer taking a **non-`@Sendable`** escaping closure (`UIColor(dynamicProvider:)`, any `@escaping` UIKit callback) accepts a closure literal written in a MainActor context, where it is inferred `@MainActor`. The framework may then invoke it off the main actor. The build succeeds either way.

**Fix**: mark the *enclosing type* (or the member building the closure) `nonisolated`, and pass values the closure needs in as `Sendable` locals. Keep the annotation even though it will look removable to the next reader — the compiler is silent here.

Reference: `PasturaDynamicColor` in `Views/DesignTokens+DynamicColor.swift`; ADR-028 § Consequences.

**A `swiftc -typecheck` probe under-approximates the real target.** An isolated conformance reached only through a compiler-synthesized witness is realized at SIL generation and prints at `<unknown>:0`, so a probe for it must **compile** (`-c -o /dev/null`, `-wmo` for multi-file) with Pattern 7's flags — `-default-isolation MainActor` especially — and must not filter through `grep "cannot convert"`. Pattern 7 keeps `-typecheck` on purpose: a printed type is a type-check-stage answer. `scripts/xcodebuild.sh build` stays the verdict for anything a probe cannot state.
