import SwiftUI
import UIKit

// The trait-resolving light/dark pair MECHANISM for the Pastura design system.
// The pairs themselves are the data, and live in
// `DesignTokens+DynamicPalette.swift` (split at #1313 so the growing table
// stops sharing a line budget with the fixed-size mechanism).
//
// Canonical source: `docs/design/design-system.md` §2.9 (Dark Mode). Design
// record: `docs/decisions/ADR-028.md`.
//
// Lives in its own file rather than in `DesignTokens.swift` because that file
// sits at 396 of swiftlint's 400-line `file_length` budget.
//
// NOTE: this file deliberately introduces **no** `PasturaColorValue(hex:)`
// literal — every value is a reference to an existing `PasturaPalette` token.
// `scripts/check_design_tokens_css.py` globs `DesignTokens*.swift` and requires
// each hex literal to be mirrored in `docs/design/ds/tokens.css`; keeping this
// file literal-free keeps that CI gate green without a mirror edit. The
// pair-table file shares that property; the hexes live in
// `DesignTokens+NightPalette.swift` and `DesignTokens.swift`.

// MARK: - §2.9 Dynamic (trait-resolving) token pair

/// A light/dark design-token pair that resolves against the ambient
/// `UIUserInterfaceStyle`.
///
/// Wraps two ``PasturaColorValue``s in a `UIColor` dynamic provider, so a
/// single ``color`` can be assigned to a `Color.*` alias and every existing
/// callsite adapts with no edit. `UIColor(dynamicProvider:)` is the
/// platform-canonical trait mechanism — it is what asset-catalog color sets
/// compile down to — but keeping the values in Swift preserves both the
/// component-level assertions in `DesignTokensTests` and the `tokens.css`
/// mirror gate, which an asset catalog would take out of reach.
///
/// The type stays `nonisolated` even though `Views/` defaults to `MainActor`.
/// This is a **runtime** guard, not a compile requirement — measured: removing it
/// still builds clean. `UIColor(dynamicProvider:)` takes a non-`@Sendable`
/// escaping closure, so without the annotation the closure literal is inferred
/// `@MainActor` while UIKit may invoke it off the main actor, and nothing
/// diagnoses that.
///
/// The stronger reason to keep it, also measured: **with** the annotation, a
/// future edit that touches MainActor state inside the provider closure is
/// diagnosed — `call to main actor-isolated global function '…' in a synchronous
/// nonisolated context [#ActorIsolatedCall]`. **Without** it, that identical edit
/// compiles silently. So the annotation is a compile-time tripwire for the racy
/// edit, not merely documentation. This is a third
/// sibling of `swift-isolation.md` Patterns 6–7 — same silence, different
/// mechanism (6 is `nonisolated async` executor inheritance, 7 is
/// unannotated-ObjC-protocol conformance); see that file's § "Same cause, two
/// non-test shapes" for the two build-error shapes this file also hits.
/// Deliberately NOT `Equatable`, unlike ``PasturaColorValue``: a synthesized
/// `==` would need `PasturaColorValue`'s own `Equatable` conformance from this
/// `nonisolated` context, and that conformance is MainActor-isolated because
/// ``PasturaColorValue`` takes the target's default isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) — `swift-isolation.md` Pattern 5.
/// Observed, not predicted: with the conformance present the build fails with
/// "main actor-isolated conformance of 'PasturaColorValue' to 'Equatable' cannot be
/// used in nonisolated context". Not `SWIFT_APPROACHABLE_CONCURRENCY`, which an
/// earlier revision credited — measured, the error reproduces with that setting's
/// feature flags absent and stops only when `-default-isolation MainActor` is
/// dropped (ADR-028 § Consequences).
/// Compare `.light` / `.dark` individually from a MainActor context instead. Do
/// not "restore" the conformance without also marking `PasturaColorValue`
/// `nonisolated`, which Pattern 5 reserves for ≥2 nonisolated call sites.
nonisolated struct PasturaDynamicColor: Sendable {
  /// Value used when the resolving trait collection is light (or unspecified).
  let light: PasturaColorValue
  /// Value used when the resolving trait collection is dark.
  let dark: PasturaColorValue

  init(light: PasturaColorValue, dark: PasturaColorValue) {
    self.light = light
    self.dark = dark
  }

  /// The trait-resolving `UIColor`.
  ///
  /// Both values are copied into locals first, which reads the intent plainly;
  /// capturing `self` would be equally safe since this is a `nonisolated`
  /// `Sendable` struct, so the locals are style, not a safety mechanism. The
  /// annotation that matters is the type-level `nonisolated` — see the note on
  /// the type for what it does and does not buy.
  /// Components are passed straight through
  /// to `UIColor(red:green:blue:alpha:)`, keeping the explicit-sRGB discipline
  /// that ``PasturaColorValue/color`` documents.
  var uiColor: UIColor {
    let lightValue = light
    let darkValue = dark
    return UIColor { traitCollection in
      let value = traitCollection.userInterfaceStyle == .dark ? darkValue : lightValue
      return UIColor(
        red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
    }
  }

  /// SwiftUI-facing form. Assign to a `Color.*` alias in
  /// `DesignTokens+SwiftUI.swift`.
  var color: Color { Color(uiColor) }
}
