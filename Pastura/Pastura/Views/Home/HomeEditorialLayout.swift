import Foundation
import SwiftUI

/// Layout tokens for the editorial ホーム (Home) tab — the resume **hero**
/// (``HomePausedCard``) and the **compact icon rows** (``HomeCompactScenarioRow``)
/// introduced by the tab-identity redesign (案C 中庸; visual source-of-truth
/// `docs/design/tab-identity/lookbook.html`, ホーム column).
///
/// These constants are extracted from the Views so the change-detector tripwire
/// ``HomeCompactRowLayoutTests`` can guard them: Home's rendered appearance is
/// code-review-gated only (ADR-009 decision 3 — frame / layout bugs are out of
/// automated-test scope, and there is no manual trigger to *see* the
/// editorial layout). The tripwire does NOT verify rendered appearance; it
/// fails when a token drifts silently in a refactor, forcing a conscious
/// confirmation that a code-review-gated visual change was intentional.
/// See `.claude/rules/view-testing.md` § "Change-detector tripwire".
///
/// **`Font` is deliberately NOT tokenised** — `SwiftUI.Font` is not `Equatable`
/// so it cannot back a value-mirror assertion. Semantic fonts (hero title
/// `.title3.bold()`, description `.subheadline`, row name
/// `.subheadline.weight(.semibold)`) stay inline in the Views, code-review-gated
/// alongside the other rendered-appearance concerns. Only the few **fixed
/// point sizes** that have no semantic-font equivalent (the mono eyebrow /
/// progress / caption) are kept here as `CGFloat` so they remain assertable.
///
/// **A `Color` token qualifies on those same grounds** and so the enums are not
/// strictly layout-only: `Color` *is* `Equatable`, and a `static let` alias has
/// a stable provider instance, so pinning which token a consumer reads is the
/// positive shape `view-testing.md` sanctions rather than the vacuous
/// differ-assertion it warns about. Today that is
/// ``HomeCompactRowLayout/updateBadgeDotFill``.
///
/// Neither enum conforms to `Equatable`: a constant-only namespace doesn't need
/// it for a value-comparison change-detector (`#expect(HomeHeroLayout.x == 18)`
/// compares the `CGFloat`, not the enum), and adding the conformance would pull
/// in the default-MainActor `Equatable`-lookup isolation trap
/// (`.claude/rules/swift-isolation.md` Pattern 5).
enum HomeHeroLayout {
  /// Hero card corner radius (continuous). Larger than the list cards' 14 so
  /// the resume hero reads as the screen's focal element.
  static let cornerRadius: CGFloat = 18

  /// Hero content inset — horizontal.
  static let horizontalPadding: CGFloat = 17

  /// Hero content inset — vertical.
  static let verticalPadding: CGFloat = 16

  /// Moss-soft hairline border around the gradient fill.
  static let borderWidth: CGFloat = 1

  /// Top stop of the 135° moss gradient (`Color.moss.opacity(...)`).
  static let gradientStartOpacity: Double = 0.16

  /// Bottom stop of the 135° moss gradient.
  static let gradientEndOpacity: Double = 0.07

  /// Base vertical spacing between the hero's eyebrow / title / description.
  static let contentSpacing: CGFloat = 8

  /// Extra spacing above the footer row (progress + Resume) so the call to
  /// action sits apart from the body copy.
  static let footerTopSpacing: CGFloat = 12

  /// Diameter of the moss-dark status dot leading the eyebrow.
  static let eyebrowDotSize: CGFloat = 7

  /// Fixed point size of the mono uppercase eyebrow ("Interrupted Scenario").
  static let eyebrowFontSize: CGFloat = 11

  /// Letter spacing applied to the uppercase eyebrow for the editorial label feel.
  static let eyebrowTracking: CGFloat = 1.2

  /// Fixed point size of the mono progress label ("Round X / Y").
  static let progressFontSize: CGFloat = 12
}

/// Layout tokens for the compact Home scenario row (``HomeCompactScenarioRow``).
/// See ``HomeHeroLayout`` for the shared change-detector / Font rationale.
enum HomeCompactRowLayout {
  /// Side length of the square leading icon tile.
  static let iconTileSize: CGFloat = 34

  /// Icon tile corner radius (continuous).
  static let iconTileCornerRadius: CGFloat = 9

  /// Moss-wash tile fill opacity (`Color.moss.opacity(...)`). No `Color.selected`
  /// Swift token exists, so the wash is expressed inline at this opacity.
  static let iconTileBackgroundOpacity: Double = 0.10

  /// Moss-soft hairline border around the icon tile.
  static let iconTileBorderWidth: CGFloat = 1

  /// Sheep-avatar edge length inside the 34pt tile. Slightly larger than
  /// ``SheepAvatar/rowSize`` (18) because here the avatar is the row's primary
  /// icon, framed in a tile, rather than one of a dense inline cluster.
  static let sheepSize: CGFloat = 20

  /// Fixed point size of the self-made document glyph (`doc.text`).
  static let docGlyphFontSize: CGFloat = 17

  /// Leading gap between the icon tile and the text column.
  static let rowSpacing: CGFloat = 11

  /// Row content inset — horizontal.
  static let horizontalPadding: CGFloat = 15

  /// Row content inset — vertical (denser than the old card row's 12).
  static let verticalPadding: CGFloat = 11

  /// Fixed point size of the mono caption ("Preset · N agents · N rounds").
  static let captionFontSize: CGFloat = 11

  /// Letter spacing applied to the mono caption.
  static let captionTracking: CGFloat = 0.2

  /// Diameter of the accent "gallery update available" dot pinned to the icon
  /// tile's top-trailing corner. Replaces the old inline "Update" text badge —
  /// the compact row keeps the signal minimal; VoiceOver still announces it via
  /// the row's accessibility value.
  static let updateBadgeDotSize: CGFloat = 9

  /// Screen-background ring around the update dot so it reads as a badge over
  /// the moss-wash tile.
  static let updateBadgeDotStrokeWidth: CGFloat = 1.5

  /// Fill of the update dot — `mossDark`, not base `moss`.
  ///
  /// The load-bearing argument is the **light** measurement: `moss` on the
  /// `screenBackground` ring reads 2.908:1, under WCAG 1.4.11's 3:1 non-text
  /// bar; `mossDark` reads 4.538:1. §2.3 assigns the analogous *DL-progress*
  /// dot to `--moss-dark`, which corroborates but does not by itself prescribe
  /// this dot — see design-system §2.3, whose 用途 cell now names both.
  ///
  /// **The dark side is a trade, not a gain.** `moss` already sat at 7.999:1
  /// against `nightBackground` with no deficit, and §2.3's ladder inverts in
  /// dark (`nightMossDark` #B3C197 is *lighter* than `nightMoss` #A8B888), so
  /// this moves the dot to 8.902:1 and makes it read louder on an otherwise
  /// quiet row. Accepted as the same function-over-perceptual-weight-parity
  /// trade ADR-028 slice 2 took for the DL dot.
  ///
  /// **`.accessibilityHidden` does not exempt it.** 1.4.11 is a
  /// visual-perception criterion, so the row's `.accessibilityValue("Update")`
  /// is an orthogonal channel that discharges nothing — and since the inline
  /// "Update" text badge was retired (see ``updateBadgeDotSize``), this dot is
  /// the signal's only *visual* carrier.
  ///
  /// Tokenised rather than left inline because the dot renders only when
  /// `hasGalleryUpdate` is true — `HomeViewModelGalleryBadgeTests` builds that
  /// state, but nothing renders it: no UI test and no `ui-tour` stop reaches
  /// the dot on screen, so `HomeCompactRowLayoutTests` is its only observer.
  static let updateBadgeDotFill: Color = .mossDark
}
