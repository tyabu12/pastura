import SwiftUI

/// The fill of `SimulationView`'s full-bleed loading scrim.
///
/// Hoisted out of the View body for one reason: the value is code-review-gated
/// only. The `shadow_color_paired_alias` SwiftLint rule does not reach a bare
/// `ZStack` fill, and no test can render the overlay (ADR-009 rules out
/// snapshots), so an edit back to a paired `Color.*` alias would silently
/// re-land the regression device QA caught in #1284 — the scrim brightening the
/// screen in dark instead of dimming it. `SimulationScrimStyleTests` pins which
/// token this reads; `DesignTokensTests` owns the token's value.
///
/// See `.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens" for why the pin is one `static let` against
/// itself rather than an assertion about what the colour looks like.
enum SimulationScrimStyle {
  /// Opacity is carried by the token, not applied here — see
  /// ``PasturaPalette/scrim``.
  static let fill: Color = PasturaPalette.scrim.color
}
