import SwiftUI

/// Filled primary-action button style for Pastura's browse surfaces.
///
/// A `mossDark` (#6B7852, design-system §2.3) fill with an `inkOnAccent`
/// label — light: white; dark: `nightInkOnAccent`, a near-ground tone, not
/// white (ADR-028) — 12pt corners, and a pressed-state opacity dim — **no**
/// capsule expansion or scale animation, keeping design-system §1's
/// "static, observed" voice.
///
/// ## Why a custom style (not `.borderedProminent`)
///
/// The system `.borderedProminent` fills from the ambient `\.tint`, and
/// `RootTabView` sets `.tint(Color.moss)` on the whole `TabView` — a **paired**
/// token, so inside the tab hierarchy (where every consumer of this style lives)
/// it resolves #8A9A6C in light and #A8B888 in dark. Its label is the system's
/// own prominent-label colour, **not** `Color.inkOnAccent`, so pairing cannot
/// help it: white measures ≈3.03:1 in light and **≈2.13:1 in dark**, i.e. the
/// alternative gets *worse* under dark, dropping below even the 3:1 non-text bar.
/// (`AccentColor.colorset` is a single `universal` #8A9A6C with no dark
/// appearance, but that is only the fallback where nothing sets a tint — it is not
/// what these call sites resolve.) `.borderedProminent` also opts **into** iOS
/// 26's Liquid Glass capsule, which §5.8 deliberately opts out of for every other
/// custom control. This style's `mossDark` fill lifts text contrast to ≈4.74:1 in
/// light (AA) and ≈7.12:1 in dark (AAA), and keeps the flat moss tone.
///
/// ## Scope
///
/// The primary call-to-action on a screen. It began as a browse-screen CTA
/// (the gallery "Try this scenario" install action, the Shared Scenarios
/// empty/error-state "Retry") and #1284 widened it to every prominent action
/// that must clear contrast in both appearances — including failure screens
/// and a `ContentUnavailableView` action. Ten callsites; `git grep
/// 'buttonStyle(PasturaPrimaryButtonStyle'` is the current list, deliberately
/// not enumerated here so this comment cannot go stale again.
///
/// Width is left to the callsite (apply `.frame(maxWidth: .infinity)` for a
/// full-width CTA); the style only owns fill, label color, padding, corners,
/// and press feedback. It ignores `.controlSize` — the metrics come from its
/// own `Size` enum, so pairing the two is dead code.
///
/// The one sanctioned `.borderedProminent` left in the app is
/// `PasturaApp.swift`'s destructive "Reset Database"; the `bordered_prominent_button_style`
/// SwiftLint rule bars the rest. See that callsite for why a destructive role
/// is exempt.
///
/// ```swift
/// Button("Try this scenario") { ... }
///   .buttonStyle(PasturaPrimaryButtonStyle())
///   .frame(maxWidth: .infinity)
/// ```
struct PasturaPrimaryButtonStyle: ButtonStyle {
  /// Sizing variant. `.regular` is the full-width browse CTA (gallery Try /
  /// Shared Scenarios Retry). `.compact` is an inline card action (e.g.
  /// HomePausedCard's Resume) where the regular padding would dominate a
  /// footer row — only the metrics change; fill / foreground / press feedback
  /// are shared so contrast and voice stay identical.
  enum Size { case regular, compact }
  var size: Size = .regular

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: fontSize, weight: .semibold))
      .foregroundStyle(Self.foreground)
      .padding(.vertical, verticalPadding)
      .padding(.horizontal, horizontalPadding)
      .background(
        Self.fill,
        in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
      )
      .opacity(configuration.isPressed ? Self.pressedOpacity : 1.0)
  }

  // `.compact` is 13pt to match the d3 Home resume button (`.resume .go`,
  // 13px); the `play.fill` glyph in the `Label` rides this font, so no
  // separate icon-size override is needed. `.regular` stays 16pt.
  private var fontSize: CGFloat { size == .compact ? 13 : 16 }
  private var verticalPadding: CGFloat { size == .compact ? 9 : 15 }
  private var horizontalPadding: CGFloat { size == .compact ? 16 : 20 }

  /// Fill color. `mossDark` (#6B7852) — `inkOnAccent`-on-fill ≈4.74:1 in light
  /// (AA) / ≈7.12:1 in dark (AAA). `.borderedProminent` fills from the inherited
  /// `.tint(Color.moss)` with the system's white label: ≈3.03:1 in light and
  /// ≈2.13:1 in dark. See the type's doc comment.
  static let fill: Color = .mossDark

  /// Label color. `inkOnAccent` — white in light, `nightInkOnAccent` (a
  /// near-ground tone, not white) in dark — on `mossDark` is the
  /// contrast-passing pair in both appearances; this is text-on-accent,
  /// distinct from the §1 "avoid pure white surfaces" guidance which
  /// concerns backgrounds.
  static let foreground: Color = .inkOnAccent

  /// Corner radius. Slightly tighter than the 14pt card so a CTA inside a
  /// card never visually fights the enclosing corner.
  static let cornerRadius: CGFloat = 12

  /// Pressed-state opacity reduction — single source of truth, mirroring
  /// `PasturaToolbarButtonStyle.pressedOpacity`. Signals the touch without
  /// a scale or capsule animation.
  static let pressedOpacity: Double = 0.7
}
