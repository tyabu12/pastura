import SwiftUI

// swiftlint:disable identifier_name

// Single-source-of-truth tokens for the Pastura design system.
//
// Canonical source: `docs/design/design-system.md` §2 (colors), §3 (typography),
// §4 (spacing, radii, shadows). If a token value here disagrees with that doc,
// the doc wins — fix this file, not the doc.
//
// For §2.5 avatar colors specifically, the doc itself mirrors
// `docs/design/demo-replay-reference.html` `sheepAvatar()` (lines 309-312); see
// that file for the original prototype values.
//
// Organized in layered namespaces (see individual doc comments below):
//   - PasturaPalette / PasturaShadows — structural tokens (test-readable).
//   - Typography + Spacing + Radius   — layout + type scales.
//   - Color extension                 — SwiftUI-facing flat aliases.

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
  //
  // Naming convention: shared parts use `avatarPart` (e.g. `avatarEar`);
  // per-character parts use `avatarPartCharacter` (e.g. `avatarBodyAlice`).

  /// Alice — body (wool / cream). Gentle first voice.
  static let avatarBodyAlice = PasturaColorValue(hex: 0xF2E3C8)
  /// Bob — body (wool / sage). Agreeable / calm.
  static let avatarBodyBob = PasturaColorValue(hex: 0xDDE4CC)
  /// Carol — body (wool / pink). Observer.
  static let avatarBodyCarol = PasturaColorValue(hex: 0xEAD6D1)
  /// Dave — body (wool / slate). Wolf / central figure.
  static let avatarBodyDave = PasturaColorValue(hex: 0xD9D7C9)

  /// Alice — face oval (darker cream accent over body).
  static let avatarFaceAlice = PasturaColorValue(hex: 0xC9A979)
  /// Bob — face oval (moss accent over body).
  static let avatarFaceBob = PasturaColorValue(hex: 0x8A9A6C)
  /// Carol — face oval (terracotta accent over body).
  static let avatarFaceCarol = PasturaColorValue(hex: 0xB8877C)
  /// Dave — face oval (deep slate accent over body).
  static let avatarFaceDave = PasturaColorValue(hex: 0x6B6858)

  /// Alice — horn stroke.
  static let avatarHornAlice = PasturaColorValue(hex: 0xB29364)
  /// Bob — horn stroke.
  static let avatarHornBob = PasturaColorValue(hex: 0x6F7F54)
  /// Carol — horn stroke.
  static let avatarHornCarol = PasturaColorValue(hex: 0x9C6E64)
  /// Dave — horn stroke.
  static let avatarHornDave = PasturaColorValue(hex: 0x4F4C3F)

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

// MARK: - §3 Typography tokens

/// Pastura text style descriptor. Data-only — application to SwiftUI `Text`
/// lives in consumer sites (first is #B1 `AgentOutputRow` refactor).
///
/// SwiftUI `Font` alone cannot carry line-height, letter-spacing, italic, or
/// text-case; callers combine `font` with `.lineSpacing(lineSpacingPoints)`,
/// `.tracking(trackingPoints)`, and `.textCase(textCase)` where applicable.
struct PasturaTextStyle: Sendable, Equatable {
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  /// Unitless line-height ratio from the doc (e.g. 1.3, 1.65).
  let lineHeight: Double
  /// Letter-spacing in em from the doc (e.g. 0.22).
  let letterSpacingEm: Double
  let isItalic: Bool
  let textCase: Text.Case?

  /// SwiftUI `Font` built from size / weight / design (+ italic modifier).
  var font: Font {
    // Why: `Font.system(size:weight:design:)` is a fixed-size font, not Dynamic
    // Type aware. This is a deliberate trade-off per `docs/design/design-system.md`
    // — the scale's precise size/line-height values are load-bearing for the
    // Pastura visual voice. When Dynamic Type support is revived, route
    // `Font.system(size:relativeTo:)` through this single computed property.
    let base = Font.system(size: size, weight: weight, design: design)
    return isItalic ? base.italic() : base
  }

  /// Additional leading in points for `.lineSpacing(_:)`.
  /// Derived from CSS-style `line-height` × `size`, minus the font's intrinsic
  /// single leading (`size`): `size × (lineHeight − 1)`.
  var lineSpacingPoints: CGFloat { size * CGFloat(lineHeight - 1.0) }

  /// Tracking in points for `.tracking(_:)`. `size × letterSpacingEm`.
  var trackingPoints: CGFloat { size * CGFloat(letterSpacingEm) }
}

/// Pastura typography scale. See `design-system.md` §3. Apply at callsites
/// via `.font(style.font).lineSpacing(style.lineSpacingPoints).tracking(style.trackingPoints)
/// .textCase(style.textCase)` — a `View.textStyle(_:)` modifier is deferred to #B1.
enum Typography {
  /// title/phase — フェーズ見出し
  static let titlePhase = PasturaTextStyle(
    size: 13, weight: .semibold, design: .default,
    lineHeight: 1.3, letterSpacingEm: 0.02,
    isItalic: false, textCase: nil)

  /// tag/phase — フェーズタグ (UPPER, mono)
  static let tagPhase = PasturaTextStyle(
    size: 9.5, weight: .semibold, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.22,
    isItalic: false, textCase: .uppercase)

  /// body/bubble — 発言本文
  static let bodyBubble = PasturaTextStyle(
    size: 13, weight: .regular, design: .default,
    lineHeight: 1.65, letterSpacingEm: 0,
    isItalic: false, textCase: nil)

  /// body/promo — プロモ文
  static let bodyPromo = PasturaTextStyle(
    size: 12, weight: .regular, design: .default,
    lineHeight: 1.65, letterSpacingEm: 0,
    isItalic: false, textCase: nil)

  /// caption/name — アバター下の名前
  static let captionName = PasturaTextStyle(
    size: 10.5, weight: .regular, design: .default,
    lineHeight: 1.3, letterSpacingEm: 0.04,
    isItalic: false, textCase: nil)

  /// thinking/body — 内なる思考 (italic)
  static let thinkingBody = PasturaTextStyle(
    size: 10.5, weight: .regular, design: .default,
    lineHeight: 1.7, letterSpacingEm: 0.02,
    isItalic: true, textCase: nil)

  /// thinking/tag — REASON/THINKING ラベル (mono UPPER)
  static let thinkingTag = PasturaTextStyle(
    size: 8.5, weight: .regular, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.22,
    isItalic: false, textCase: .uppercase)

  /// meta/label — "DL" ラベル (mono semibold)
  static let metaLabel = PasturaTextStyle(
    size: 9, weight: .semibold, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.06,
    isItalic: false, textCase: nil)

  /// meta/value — `35%`, `1.0 GB` (mono)
  static let metaValue = PasturaTextStyle(
    size: 9, weight: .regular, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0,
    isItalic: false, textCase: nil)

  /// meta/eta — 残り約4分 (mono medium)
  static let metaEta = PasturaTextStyle(
    size: 10, weight: .medium, design: .monospaced,
    lineHeight: 1.3, letterSpacingEm: 0,
    isItalic: false, textCase: nil)

  /// status/complete — 準備ができました
  static let statusComplete = PasturaTextStyle(
    size: 16, weight: .medium, design: .default,
    lineHeight: 1.4, letterSpacingEm: 0.22,
    isItalic: false, textCase: nil)

  /// status/hint — tap anywhere to begin (mono)
  static let statusHint = PasturaTextStyle(
    size: 11, weight: .regular, design: .monospaced,
    lineHeight: 1.2, letterSpacingEm: 0.1,
    isItalic: false, textCase: nil)

  // GameHeader (§5.1) typography lives in `DesignTokens+ExtendedTypography.swift`
  // to keep this file under the 400-line `file_length` cap.
}

// MARK: - §4 Spacing + Radius tokens

/// Pastura spacing scale. See `design-system.md` §4.1.
///
/// 4pt-based scale with deliberate mid-values (14, 20) — design-system.md
/// emphasizes softness over strict 8-multiples. Use descriptive aliases at
/// callsites (e.g. `Spacing.bubbleGap`) when the number alone obscures intent.
enum Spacing {
  /// 4pt — smallest step (tight gutters, ornament spacing).
  static let xxs: CGFloat = 4
  /// 8pt — compact row gap.
  static let xs: CGFloat = 8
  /// 12pt — promo inner rhythm.
  static let s: CGFloat = 12
  /// 14pt — bubble / card rhythm (the "soft" mid-value).
  static let m: CGFloat = 14
  /// 20pt — block separation.
  static let l: CGFloat = 20
  /// 32pt — section separation.
  static let xl: CGFloat = 32
  /// 48pt — screen-level breathing room.
  static let xxl: CGFloat = 48
}

/// Pastura corner-radius scale. See `design-system.md` §4.2.
///
/// `dot` is `.infinity` (SwiftUI circle semantics via
/// `.clipShape(.circle)` or `RoundedRectangle(cornerRadius: .infinity)`).
enum Radius {
  /// iPhone body inner radius (follows device corner).
  static let deviceInner: CGFloat = 31
  /// Bubble tail corner (upper-left of tailed bubble).
  static let bubbleTail: CGFloat = 4
  /// Bubble body (non-tail corners).
  static let bubbleBody: CGFloat = 14
  /// Promo card.
  static let promo: CGFloat = 14
  /// Vote / action button.
  static let button: CGFloat = 8
  /// Full circle — DL progress dots and similar.
  static let dot: CGFloat = .infinity
}

// SwiftUI-facing helpers (`Color.*` aliases, `View.textStyle(_:)`) live in
// `DesignTokens+SwiftUI.swift` — split to keep this file under the 400-line
// cap and to ease the future SPM split (tokens module vs UI module).

// swiftlint:enable identifier_name
