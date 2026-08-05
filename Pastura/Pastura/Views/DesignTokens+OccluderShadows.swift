import SwiftUI

// Occlusion shadows — the §4.3 family whose tint is chosen for *direction*
// rather than for hue. Lives in its own file because `DesignTokens.swift` sits
// at 362 of swiftlint's 400-line `file_length` cap; the `DesignTokens` filename
// prefix is load-bearing, as `scripts/check_design_tokens_css.py` globs
// `Pastura/Pastura/Views/DesignTokens*.swift` and would silently stop mirroring
// these values if the file were renamed out of it.
//
// Source of truth for the values: `docs/design/design-system.md` §4.3.

/// Drop shadows for elements that sit **on the app ground** rather than on a
/// local surface.
///
/// ## Why these are not `PasturaShadows`
///
/// §4.3's `PasturaShadows.tight` / `.soft` are moss-tinted — `rgba(90,100,60)`
/// — which reads correctly on the cream ground but composites *lighter* than
/// the #1B1D17 night ground, i.e. as a glow. Naming a shadow's colour "fixed in
/// both appearances" is not enough: `a·C + (1−a)·ground` cannot fall below
/// `ground` when `C` is lighter than it, whatever `a` is. **The requirement is
/// that the tint be darker than every ground the element can cover**, which is
/// the same conclusion `PasturaPalette/scrim` reached for the full-bleed
/// occluder (ADR-028), and why this family reuses its #0B0C0A.
///
/// `PasturaShadows` shares the defect at an order of magnitude lower alpha and
/// is **deliberately** left alone — changing it re-opens §4.3's moss-tint rule
/// for five consumers and needs its own ADR amendment. See #1373.
///
/// ## What this buys in dark, honestly
///
/// Almost nothing visible: the night ground sits at relative luminance 0.0117,
/// so a correct shadow can only darken it by about one sRGB step. Elevation in
/// dark is carried by the surface being lighter than the ground (`nightBubble`
/// #2C2F28 over `nightBackground`) plus the element's hairline stroke. The
/// point of this family is **removing a wrong glow**, not adding a shadow.
///
/// ## Why the values are hoisted out of the view bodies
///
/// They are code-review-gated only. The `shadow_color_paired_alias` SwiftLint
/// rule fires on a leading-dot `Color.*` alias, so it never saw the shape that
/// actually shipped here — a raw `PasturaPalette` token that is fixed but too
/// light — and ADR-009 rules out the snapshot test that would.
/// `PasturaOccluderShadowsTests` asserts the direction requirement against
/// every ground; the geometry below is pinned there as a change-detector.
///
/// The tints are written as `PasturaColorValue(hex:opacity:)` rather than
/// built from a bare token, because that is the shape
/// `check_design_tokens_css.py` converts to `rgba(...)` — it keeps the alphas,
/// the drift-prone half, inside the mirror gate.
enum PasturaOccluderShadows {

  /// `ModelPickerView`'s model-list card, which floats directly on
  /// `screenBackground` / `nightBackground`. Alpha solved to leave the
  /// light-mode composite where `moss` at 0.22 put it (#E3E5D6 → #E4E2DD).
  ///
  /// One layer, not the handoff's `0 18px 36px -22px`: SwiftUI's `shadow`
  /// has no `spread`, so the negative-spread soft glow is approximated by a
  /// single softer shadow — the "近似 OK" carve-out in
  /// `design_handoff_model_select/`.
  static let modelPickerCard = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.1),
    radius: 14, x: 0, y: 12)

  /// `ModelPickerView`'s sticky download CTA. Sits on the `.ultraThinMaterial`
  /// band, whose composite tracks the ground beneath it in both appearances.
  static let modelPickerCTA = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.36),
    radius: 8, x: 0, y: 6)

  /// `InFlightSimulationIndicator`'s pill. Mounted as a root `.overlay` on
  /// `RootTabView`, so unlike the two above its ground is *every* screen —
  /// including `nightPage`, the palette's darkest token. That open ground set
  /// is why the family's tint had to clear #11130F rather than merely
  /// `nightBackground`.
  static let inFlightPill = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.1),
    radius: 8, x: 0, y: 2)
}
