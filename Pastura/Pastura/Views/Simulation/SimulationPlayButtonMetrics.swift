import SwiftUI

/// Layout + color tokens for the control-bar play/pause button, shared by
/// ``SimulationView`` (`controlBar`) and the DL-time demo replay control bar
/// (`ModelDownloadHostView.controlBar`) so the two stay in parity (#273).
///
/// Extracted from the View so `SimulationControlsTokenTests` can act as a
/// **change-detector tripwire** (ADR-009 § "Change-detector tripwire";
/// rendered appearance is code-review-gated only). A failure here is NOT a
/// bug — it means a code-review-gated visual token drifted in a refactor and
/// the editor must confirm the change was intended before updating the
/// expected value.
///
/// ## Why a filled circle (not the former bare glyph)
///
/// The old control used a lone `play.fill` / `pause.fill` glyph in
/// `Color.ink` — the only filled, near-black element on the frosted control
/// bar, so it read as a stray "black blob" rather than *the* primary action.
/// A `mossDark` filled circle with a white glyph reads as a deliberate
/// primary control and stays in-palette. No drop-shadow on the circle: the
/// frosted bar already supplies one elevation layer, and design-system §1/§4.3
/// limit the Sim screen to a single floating element (avoid double-lift).
enum SimulationPlayButtonMetrics {
  /// Circle diameter. User-confirmed at 34pt via mockup (a touch smaller than
  /// the 38pt first draft).
  static let diameter: CGFloat = 34

  /// White glyph point size inside the circle (~0.41 × diameter).
  static let glyphPointSize: CGFloat = 14

  /// Enabled fill — `mossDark` (#6B7852); white-on-fill ≈ 4.76:1 (WCAG AA).
  static let enabledFill: Color = .mossDark

  /// Disabled fill — `disabledText` (#B5B0A2). Disabled controls are exempt
  /// from the contrast target, so the muted tan + white glyph is intentional.
  static let disabledFill: Color = .disabledText

  /// Glyph color. On `enabledFill` this is the sanctioned on-accent pair —
  /// `inkOnAccent` over `mossDark` ≈ 4.7:1 (§1's "avoid pure white" concerns
  /// backgrounds, not glyphs on an accent fill). The disabled arm reuses it for
  /// visual continuity even though `disabledText` is **not** an accent and the
  /// pair there is only ≈2.2:1 — §8 exempts disabled controls from the
  /// contrast target (see `disabledFill` above).
  static let glyphColor: Color = .inkOnAccent
}
