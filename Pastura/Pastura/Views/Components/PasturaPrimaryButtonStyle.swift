import SwiftUI

/// Filled primary-action button style for Pastura's browse surfaces.
///
/// A `mossDark` (#6B7852, design-system §2.3) fill with white label, 12pt
/// corners, and a pressed-state opacity dim — **no** capsule expansion or
/// scale animation, keeping design-system §1's "static, observed" voice.
///
/// ## Why a custom style (not `.borderedProminent`)
///
/// The system `.borderedProminent` tints with the app accent (`moss`
/// #8A9A6C), giving white-on-moss ≈ 3.0:1 — below WCAG AA (4.5:1) and
/// below Pastura's own §8 target. It also opts **into** iOS 26's Liquid
/// Glass capsule, which §5.8 deliberately opts out of for every other
/// custom control. `mossDark` fill lifts white-label contrast to ≈ 4.76:1
/// (AA pass) and keeps the flat moss tone.
///
/// ## Scope
///
/// The single primary call-to-action on a browse screen — currently the
/// gallery "Try this scenario" install action and the Shared Scenarios
/// empty/error-state "Retry". Width is left to the callsite (apply
/// `.frame(maxWidth: .infinity)` for a full-width CTA); the style only
/// owns fill, label color, padding, corners, and press feedback.
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

  private var fontSize: CGFloat { size == .compact ? 15 : 16 }
  private var verticalPadding: CGFloat { size == .compact ? 9 : 15 }
  private var horizontalPadding: CGFloat { size == .compact ? 16 : 20 }

  /// Fill color. `mossDark` (#6B7852) — white-on-fill ≈ 4.76:1 (AA pass),
  /// vs. base `moss` (#8A9A6C) ≈ 3.0:1 from `.borderedProminent`.
  static let fill: Color = .mossDark

  /// Label color. White on `mossDark` is the contrast-passing pair; this
  /// is text-on-accent, distinct from the §1 "avoid pure white surfaces"
  /// guidance which concerns backgrounds.
  static let foreground: Color = .white

  /// Corner radius. Slightly tighter than the 14pt card so a CTA inside a
  /// card never visually fights the enclosing corner.
  static let cornerRadius: CGFloat = 12

  /// Pressed-state opacity reduction — single source of truth, mirroring
  /// `PasturaToolbarButtonStyle.pressedOpacity`. Signals the touch without
  /// a scale or capsule animation.
  static let pressedOpacity: Double = 0.7
}
