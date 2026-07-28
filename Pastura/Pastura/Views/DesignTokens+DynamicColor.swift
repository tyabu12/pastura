import SwiftUI
import UIKit

// Trait-resolving light/dark token pairs for the Pastura design system.
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
// file literal-free keeps that CI gate green without a mirror edit.

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
/// `nonisolated` context, and that conformance is MainActor-isolated (the target
/// sets `SWIFT_APPROACHABLE_CONCURRENCY = YES`, which enables
/// `InferIsolatedConformances`) — `swift-isolation.md` Pattern 5. Observed, not
/// predicted: with the conformance present the build fails with "main actor-isolated
/// conformance of 'PasturaColorValue' to 'Equatable' cannot be used in nonisolated
/// context".
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

// MARK: - The declared pairs

/// The light↔dark token pairs wired into the app's `Color.*` aliases.
///
/// **Eight pairs, not nine.** `design-system.md` §2.9 lists nine `night*`
/// tokens but maps two of them (`nightSurface`, `nightBubble`) onto the same
/// day token, `bubbleBackground`. `nightSurface` therefore has no light
/// partner and is not wired here — dark wants a background/surface/bubble
/// three-step where light has only two, and resolving that (a new light
/// `surface` token, or dropping `nightSurface`) is a visual-design decision.
/// ADR-028 § "The `nightSurface` double-mapping" records it as deferred.
///
/// The remaining 60 light tokens still owe a dark value and stay light-only;
/// the app is pinned to light via `Info.plist`'s `UIUserInterfaceStyle` until
/// they are designed, so no half-dark surface can render.
///
/// Unlike ``PasturaDynamicColor`` this namespace is deliberately NOT
/// `nonisolated`: its static initializers read `PasturaPalette`, which is
/// MainActor-isolated under `Views/`'s default isolation, and a `nonisolated`
/// namespace fails to compile — observed, not predicted: "Main actor-isolated
/// default value in a nonisolated context", once per static. Nothing is lost — the isolation that matters is on the
/// provider closure inside ``PasturaDynamicColor/uiColor``, which UIKit may
/// invoke off the main actor; reading these statics only ever happens from the
/// MainActor `Color` extension.
enum PasturaDynamicPalette {

  /// §2.1 — app body background.
  static let screenBackground = PasturaDynamicColor(
    light: PasturaPalette.screenBackground, dark: PasturaPalette.nightBackground)
  /// §2.1 — public speech-bubble fill.
  static let bubbleBackground = PasturaDynamicColor(
    light: PasturaPalette.bubbleBackground, dark: PasturaPalette.nightBubble)
  /// §2.1 — whisper (密談) speech-bubble fill.
  static let whisperBubble = PasturaDynamicColor(
    light: PasturaPalette.whisperBubble, dark: PasturaPalette.nightWhisperBubble)

  /// §2.2 — primary body text.
  static let ink = PasturaDynamicColor(
    light: PasturaPalette.ink, dark: PasturaPalette.nightInk)
  /// §2.2 — subtext / section labels.
  static let inkSecondary = PasturaDynamicColor(
    light: PasturaPalette.inkSecondary, dark: PasturaPalette.nightInkSecondary)
  /// §2.2 — meta info / footnotes.
  static let muted = PasturaDynamicColor(
    light: PasturaPalette.muted, dark: PasturaPalette.nightMuted)
  /// §2.2 — rule / divider lines.
  static let rule = PasturaDynamicColor(
    light: PasturaPalette.rule, dark: PasturaPalette.nightRule)

  /// §2.3 — brand accent.
  static let moss = PasturaDynamicColor(
    light: PasturaPalette.moss, dark: PasturaPalette.nightMoss)

  /// Every declared pair, keyed by its light-token name.
  ///
  /// Consumed by `DesignTokensTests+DarkMode`'s count assertion. Note what that
  /// does and does not catch: the registry is hand-maintained, so declaring a
  /// ninth pair and *not* appending it here leaves `all.count == 8` and passes.
  /// The count guards this list against its own documented size, nothing more —
  /// the real per-alias coverage is the wiring tests, which resolve each of the
  /// eight `Color.*` aliases under both schemes.
  static let all: [(name: String, pair: PasturaDynamicColor)] = [
    ("screenBackground", screenBackground),
    ("bubbleBackground", bubbleBackground),
    ("whisperBubble", whisperBubble),
    ("ink", ink),
    ("inkSecondary", inkSecondary),
    ("muted", muted),
    ("rule", rule),
    ("moss", moss)
  ]
}
