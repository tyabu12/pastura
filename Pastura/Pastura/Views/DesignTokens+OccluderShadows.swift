import SwiftUI

// Occlusion shadows — the §4.3 family whose tint is chosen for *direction*
// rather than for hue. Lives in its own file because `DesignTokens.swift` sits
// at 362 of swiftlint's 400-line `file_length` cap; the `DesignTokens` filename
// prefix is load-bearing, as `scripts/check_design_tokens_css.py` globs
// `Pastura/Pastura/Views/DesignTokens*.swift` and would silently stop mirroring
// these values if the file were renamed out of it.
//
// **This file is the source of truth for the values** — `check_design_tokens_css.py`
// gates these literals against `docs/design/ds/tokens.css`, so the mirror runs
// Swift → CSS. `docs/design/design-system.md` §4.3.1 documents the family and
// restates the values as a mirror; update it in the same change.

/// Drop shadows for elements that sit **on the app ground** rather than on a
/// local surface.
///
/// ## Why these are not `PasturaShadows`
///
/// **Geometry, and only geometry** — since #1378 both families carry the same
/// #0B0C0A. §4.3's `PasturaShadows` is a fixed two-layer recipe stacked on a
/// card; this is a per-site registry, one entry per surface that needs its own
/// radius / offset. Reach for whichever fits and do not merge them: flattening
/// a reusable recipe into a site registry loses that distinction.
///
/// Both were moss-tinted once — `rgba(90,100,60)`, which reads correctly on the
/// cream ground but composites *lighter* than the #1B1D17 night ground, i.e. as
/// a glow. Naming a shadow's colour "fixed in both appearances" is not enough:
/// `a·C + (1−a)·ground` cannot fall below `ground` when `C` is lighter than it,
/// whatever `a` is. **The requirement is that the tint be darker than every
/// ground the element can cover**, which is the same conclusion
/// `PasturaPalette/scrim` reached for the full-bleed occluder (ADR-028).
///
/// **The binding ground is `nightBackground` #1B1D17** — every screen carries it
/// since the #1354 sweep, and the one darker token, `nightPage` #11130F, is
/// reachable by no member of this family (its sole consumer is
/// `ViewerPredictionSheet`, presented from `SimulationView`, where the pill is
/// suppressed by `isSimulationOnTop` and a sheet covers the root overlay
/// anyway). The family reuses the scrim's **#0B0C0A** so the palette carries one
/// occluder near-black rather than two; the margin it holds over #1B1D17 beyond
/// what is needed is free — the light composites differ by at most one sRGB step
/// from a value solved against the binding ground alone.
///
/// `PasturaShadows` shared the defect and was fixed the same way in #1378, so
/// the moss tint is gone from §4.3 entirely and there is no longer a "which
/// family is correct" question — only the geometry one above.
///
/// ## What this buys in dark
///
/// Less than a light-mode shadow, and not nothing: the night ground sits at
/// relative luminance 0.0117, leaving little room below it, so the same tints
/// darken by ~1.6 sRGB steps at α 0.10 and ~5.8 at α 0.36. Elevation in dark is
/// carried mostly by the surface being lighter than the ground (`nightBubble`
/// #2C2F28 over `nightBackground`) plus the element's hairline stroke. The point
/// of this family is **removing a wrong glow** first, and the shadow second.
///
/// ## Why the values are hoisted out of the view bodies
///
/// Because the requirement they carry is not one lint can state. The
/// `shadow_color_occluder_family` SwiftLint rule reaches every `shadow(color:)`
/// tint since #1377, but it is an **allowlist over family names** — it
/// certifies that a tint names this family, never that the value is dark enough
/// for the ground it covers. (Its predecessor keyed on a leading-dot `Color.*`
/// alias and never saw the shape that actually shipped here: a raw
/// `PasturaPalette` token, fixed but too light.) ADR-009 rules out the snapshot
/// test that would close the difference, so `PasturaOccluderShadowsTests`
/// asserts the direction requirement and pins the geometry as a
/// change-detector. It iterates ``all`` — keep new members in that list, or the
/// suite silently stops covering them.
///
/// The tints are written as `PasturaColorValue(hex:opacity:)` rather than
/// built from a bare token, because that is the shape
/// `check_design_tokens_css.py` converts to `rgba(...)` — it keeps the alphas,
/// the drift-prone half, inside the mirror gate.
enum PasturaOccluderShadows {

  /// `ModelPickerView`'s model-list card, which floats directly on
  /// `screenBackground` / `nightBackground`. Alpha solved to hold the light-mode
  /// composite's **red channel** where `moss` at 0.22 put it; the other two move
  /// and the result de-tints (#E3E5D6 → #E4E2DD, green −3 / blue +7). That
  /// neutralising is unavoidable at a near-black — see §4.3.1.
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
  /// `RootTabView`, so unlike the two above its ground is not one screen's —
  /// it floats over whichever tab is showing. Every one of those carries
  /// `nightBackground` in dark, so the binding constraint is the same #1B1D17;
  /// the pill does **not** widen the ground set (see the type's note on
  /// `nightPage`).
  static let inFlightPill = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.1),
    radius: 8, x: 0, y: 2)

  /// Every member, for the test to iterate. A new shadow added above and not
  /// listed here is covered by nothing.
  static let all: [PasturaShadow] = [modelPickerCard, modelPickerCTA, inFlightPill]
}
