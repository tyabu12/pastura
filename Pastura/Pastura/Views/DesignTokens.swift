import SwiftUI

// swiftlint:disable identifier_name file_length

/// Single-source-of-truth tokens for the Pastura design system.
///
/// Canonical source: `docs/design/design-system.md` §2 (colors), §3 (typography),
/// §4 (spacing, radii, shadows). If a token value here disagrees with that doc,
/// the doc wins — fix this file, not the doc.
///
/// Organized in three namespaces:
/// - ``PasturaPalette`` — color tokens as structural `(r, g, b, opacity)` tuples.
/// - ``PasturaShadows`` — two-layer shadow recipe from §4.3.
/// - `Color` extension — SwiftUI-facing flat aliases (`Color.page`, `Color.moss`, …).
///
/// Typography, Spacing, and Radius tokens are defined in sibling sections below
/// (added by follow-up commits on the same issue).

// MARK: - §2 Color tokens

/// A single color token, stored as sRGB components so tests can verify values
/// against the canonical hex in `design-system.md` without round-tripping
/// through `Color.Resolved` (which is linear-light and lossy).
///
/// Construct from a 24-bit hex literal via ``init(hex:opacity:)`` — keeps the
/// source aligned with the doc's `#RRGGBB` notation.
struct PasturaColorValue: Sendable, Equatable {
  let red: Double
  let green: Double
  let blue: Double
  let opacity: Double

  /// Build a token from a 24-bit sRGB hex integer (e.g. `0xF3EFE7`).
  /// Opacity defaults to 1; pass a fractional value for `rgba(...)` tokens
  /// like §2.5's avatar highlight.
  init(hex: UInt32, opacity: Double = 1.0) {
    self.red = Double((hex >> 16) & 0xFF) / 255.0
    self.green = Double((hex >> 8) & 0xFF) / 255.0
    self.blue = Double(hex & 0xFF) / 255.0
    self.opacity = opacity
  }

  /// Build a token from raw 0...1 sRGB components. Used for §4.3 shadow tints
  /// specified as `rgba(90, 100, 60, ...)` where a hex literal would obscure
  /// the source numbers.
  init(red: Double, green: Double, blue: Double, opacity: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  /// Materialize as an sRGB `Color`. Explicit `.sRGB` color space (not the
  /// default) is load-bearing: it ensures consumers and test round-trips agree
  /// on the color space without relying on device-default assumptions.
  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }
}

/// Canonical Pastura color palette. See `design-system.md` §2.
///
/// Test suites read components directly (`PasturaPalette.page.red` etc.); view
/// code typically uses the `Color.*` aliases in the `Color` extension below.
enum PasturaPalette {

  // MARK: §2.1 Backgrounds / Surfaces

  /// Outside the app surface (workbench / outside Safe Area).
  static let page = PasturaColorValue(hex: 0xF3EFE7)
  /// App body background — crisp wool-color.
  static let screenBackground = PasturaColorValue(hex: 0xFCFAF4)
  /// Speech bubble background.
  static let bubbleBackground = PasturaColorValue(hex: 0xFFFFFF)
  /// Promo / banner background.
  static let promoBackground = PasturaColorValue(hex: 0xFBFAF2)
  /// Promo / banner border.
  static let promoBorder = PasturaColorValue(hex: 0xE4E7D2)

  // MARK: §2.2 Ink

  /// Primary body text. Intentionally not pure black.
  static let ink = PasturaColorValue(hex: 0x2D2E26)
  /// Subtext / section labels.
  static let inkSecondary = PasturaColorValue(hex: 0x5A5A55)
  /// Meta info / footnotes.
  static let muted = PasturaColorValue(hex: 0x8A8A83)
  /// Rule / divider lines.
  static let rule = PasturaColorValue(hex: 0xE0DBCE)

  // MARK: §2.3 Moss Accent — Pastura's only brand color, 4 steps

  /// Leaf icon, promo left border (3pt).
  static let moss = PasturaColorValue(hex: 0x8A9A6C)
  /// DL progress dot (lit), accent links.
  static let mossDark = PasturaColorValue(hex: 0x6B7852)
  /// Dog outline, completion title.
  static let mossInk = PasturaColorValue(hex: 0x3D4030)
  /// THINKING left-rule, gentle dividers.
  static let mossSoft = PasturaColorValue(hex: 0xD4CBA8)

  // MARK: §2.4 Meta Contrast Presets (DL progress)

  // L3 is the documented default. Consumers hard-code `L3` unless they have
  // an explicit reason to override — environment-based preset switching is
  // deferred to #B1/#C.
  static let metaBaseL1 = PasturaColorValue(hex: 0x8A8B76)
  static let metaStrongL1 = PasturaColorValue(hex: 0x5D6848)
  static let metaDotOnL1 = PasturaColorValue(hex: 0x8A9A6C)

  static let metaBaseL2 = PasturaColorValue(hex: 0x6A6D5A)
  static let metaStrongL2 = PasturaColorValue(hex: 0x3D4530)
  static let metaDotOnL2 = PasturaColorValue(hex: 0x7A8A5C)

  static let metaBaseL3 = PasturaColorValue(hex: 0x4A4E3D)
  static let metaStrongL3 = PasturaColorValue(hex: 0x2D2E26)
  static let metaDotOnL3 = PasturaColorValue(hex: 0x6B7852)

  static let metaBaseL4 = PasturaColorValue(hex: 0x2D2E26)
  static let metaStrongL4 = PasturaColorValue(hex: 0x1A1B15)
  static let metaDotOnL4 = PasturaColorValue(hex: 0x556340)

  // MARK: §2.5 Avatar palette (sheep characters)

  /// Alice — cream. Gentle first voice.
  static let avatarAlice = PasturaColorValue(hex: 0xF2E3C8)
  /// Bob — sage. Agreeable / calm.
  static let avatarBob = PasturaColorValue(hex: 0xD9E2C6)
  /// Carol — pink. Observer.
  static let avatarCarol = PasturaColorValue(hex: 0xEBD4D4)
  /// Dave — slate. Wolf / central figure.
  static let avatarDave = PasturaColorValue(hex: 0xD0D7DC)

  /// Shared avatar ear color.
  static let avatarEar = PasturaColorValue(hex: 0xE8D9BC)
  /// Inner ear tint.
  static let avatarEarInner = PasturaColorValue(hex: 0xD4C19E)
  /// Avatar nose.
  static let avatarNose = PasturaColorValue(hex: 0x3D4030)
  /// Avatar eye.
  static let avatarEye = PasturaColorValue(hex: 0x2D2E26)
  /// Translucent highlight (rgba(255,255,255,.6)).
  static let avatarHighlight = PasturaColorValue(hex: 0xFFFFFF, opacity: 0.6)
}

// MARK: - §4.3 Shadow tokens

/// A single shadow layer matching SwiftUI's `.shadow(color:radius:x:y:)` shape.
///
/// CSS source (`design-system.md` §4.3) uses a negative spread on the second
/// layer (`-12px`). SwiftUI's built-in `.shadow` has no spread parameter, so
/// the spread is dropped; the visual approximation is close enough for the
/// soft-shadow use case. If the exact spread matters for a specific surface,
/// reach for a custom `.background { ... }` mask — but do not add spread
/// handling to this token type without revisiting design-system.md §4.3 first.
struct PasturaShadow: Sendable, Equatable {
  let color: PasturaColorValue
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat
}

/// Two-layer moss-tinted shadow recipe from `design-system.md` §4.3.
///
/// Apply by stacking both `.shadow(...)` modifiers on the same view:
/// ```
/// view
///   .shadow(
///     color: PasturaShadows.tight.color.color,
///     radius: PasturaShadows.tight.radius,
///     x: PasturaShadows.tight.x,
///     y: PasturaShadows.tight.y)
///   .shadow(
///     color: PasturaShadows.soft.color.color,
///     radius: PasturaShadows.soft.radius,
///     x: PasturaShadows.soft.x,
///     y: PasturaShadows.soft.y)
/// ```
enum PasturaShadows {
  /// Inner tight layer — `0 1px 2px rgba(90,100,60,.04)`.
  static let tight = PasturaShadow(
    color: PasturaColorValue(
      red: 90.0 / 255.0, green: 100.0 / 255.0, blue: 60.0 / 255.0, opacity: 0.04),
    radius: 2, x: 0, y: 1)
  /// Outer soft layer — `0 12px 26px -12px rgba(90,100,60,.2)` (spread dropped).
  static let soft = PasturaShadow(
    color: PasturaColorValue(
      red: 90.0 / 255.0, green: 100.0 / 255.0, blue: 60.0 / 255.0, opacity: 0.2),
    radius: 26, x: 0, y: 12)
}

// MARK: - Color extension (SwiftUI-facing aliases)

extension Color {
  // §2.1 Backgrounds
  static let page = PasturaPalette.page.color
  static let screenBackground = PasturaPalette.screenBackground.color
  static let bubbleBackground = PasturaPalette.bubbleBackground.color
  static let promoBackground = PasturaPalette.promoBackground.color
  static let promoBorder = PasturaPalette.promoBorder.color

  // §2.2 Ink
  static let ink = PasturaPalette.ink.color
  static let inkSecondary = PasturaPalette.inkSecondary.color
  static let muted = PasturaPalette.muted.color
  static let rule = PasturaPalette.rule.color

  // §2.3 Moss
  static let moss = PasturaPalette.moss.color
  static let mossDark = PasturaPalette.mossDark.color
  static let mossInk = PasturaPalette.mossInk.color
  static let mossSoft = PasturaPalette.mossSoft.color

  // §2.4 Meta L1
  static let metaBaseL1 = PasturaPalette.metaBaseL1.color
  static let metaStrongL1 = PasturaPalette.metaStrongL1.color
  static let metaDotOnL1 = PasturaPalette.metaDotOnL1.color

  // §2.4 Meta L2
  static let metaBaseL2 = PasturaPalette.metaBaseL2.color
  static let metaStrongL2 = PasturaPalette.metaStrongL2.color
  static let metaDotOnL2 = PasturaPalette.metaDotOnL2.color

  // §2.4 Meta L3 (default)
  static let metaBaseL3 = PasturaPalette.metaBaseL3.color
  static let metaStrongL3 = PasturaPalette.metaStrongL3.color
  static let metaDotOnL3 = PasturaPalette.metaDotOnL3.color

  // §2.4 Meta L4
  static let metaBaseL4 = PasturaPalette.metaBaseL4.color
  static let metaStrongL4 = PasturaPalette.metaStrongL4.color
  static let metaDotOnL4 = PasturaPalette.metaDotOnL4.color

  // §2.5 Avatars
  static let avatarAlice = PasturaPalette.avatarAlice.color
  static let avatarBob = PasturaPalette.avatarBob.color
  static let avatarCarol = PasturaPalette.avatarCarol.color
  static let avatarDave = PasturaPalette.avatarDave.color
  static let avatarEar = PasturaPalette.avatarEar.color
  static let avatarEarInner = PasturaPalette.avatarEarInner.color
  static let avatarNose = PasturaPalette.avatarNose.color
  static let avatarEye = PasturaPalette.avatarEye.color
  static let avatarHighlight = PasturaPalette.avatarHighlight.color
}

// swiftlint:enable identifier_name file_length
