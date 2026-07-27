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
/// The type stays `nonisolated` even though `Views/` defaults to `MainActor`:
/// UIKit may invoke the provider closure from any thread, and a MainActor
/// closure capturing MainActor state is `.claude/rules/swift-isolation.md`
/// Pattern 6/7 — a shape that emits no diagnostic and fails only at runtime.
/// Deliberately NOT `Equatable`, unlike ``PasturaColorValue``: a synthesized
/// `==` would need `PasturaColorValue`'s own `Equatable` conformance from this
/// `nonisolated` context, and that conformance is MainActor-isolated (the target
/// builds with `InferIsolatedConformances`) — `swift-isolation.md` Pattern 5,
/// which fails to compile with "main actor-isolated conformance of
/// 'PasturaColorValue' to 'Equatable' cannot be used in nonisolated context".
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
  /// Both values are copied into locals first so the escaping provider closure
  /// captures only `Sendable` `PasturaColorValue` structs and never `self` —
  /// see the isolation note on the type. Components are passed straight through
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
/// ADR-028 § "nightSurface" records it as deferred.
///
/// The remaining 59 light tokens have no dark counterpart and stay light-only;
/// the app is pinned to light via `Info.plist`'s `UIUserInterfaceStyle` until
/// they are designed, so no half-dark surface can render.
///
/// Unlike ``PasturaDynamicColor`` this namespace is deliberately NOT
/// `nonisolated`: its static initializers read `PasturaPalette`, which is
/// MainActor-isolated under `Views/`'s default isolation, and a `nonisolated`
/// namespace fails to compile with "Main actor-isolated default value in a
/// nonisolated context". Nothing is lost — the isolation that matters is on the
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
  /// Drift guard for `DesignTokensTests+DarkMode`: adding a pair without
  /// registering it here (or wiring a ninth without resolving the
  /// `nightSurface` question above) fails the count assertion.
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
