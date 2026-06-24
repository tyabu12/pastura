import CoreGraphics

/// Load-bearing layout constants for the さがす (Browse / Shared Scenarios)
/// **catalog-card** rendering (tab-identity redesign PR2, #777): the leading
/// art tile, its sheep cluster, the landscape card chrome, the inline category
/// chip, and the list rhythm. Values are transcribed from the approved lookbook
/// (`docs/design/tab-identity/lookbook.html`, さがす row, "案C 中庸" column).
///
/// Extracted into a named `nonisolated enum` so the values are
/// **change-detector**-testable without rendering the View
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire"; ADR-009).
/// Only `Equatable` constants live here — `CGFloat` / `Int`. SwiftUI `Font`s
/// are **not** `Equatable`, so they stay inline in ``GalleryCatalogRow`` and are
/// code-review-gated, not asserted here.
///
/// `nonisolated` so the change-detector test reads the constants from a
/// `nonisolated` context without a `@MainActor` suite workaround
/// (swift-isolation.md Pattern 5). Values are tuned on-device — a test failure
/// means a code-review-gated layout token drifted, not a bug (see the test's
/// doc-comment).
nonisolated enum GalleryCatalogMetrics {
  // MARK: Art tile

  /// Side length of the square leading art tile.
  static let artTileSize: CGFloat = 74

  /// Corner radius of the art tile.
  static let artTileCornerRadius: CGFloat = 13

  /// Size of each ``SheepAvatar`` in the **3–4-sheep** (2×2) cluster — also the
  /// base tier `clusterSheepSize(forCount:)` returns for that band.
  static let artSheepSize: CGFloat = 26

  /// Sheep size for a **single**-agent tile (rendered large and centered).
  static let clusterSheepSizeSolo: CGFloat = 40

  /// Sheep size for a **2**-agent tile (one row of two).
  static let clusterSheepSizePair: CGFloat = 30

  /// Sheep size for a **5–6**-agent tile (2×3 grid — shrunk so three rows fit
  /// the 74pt tile).
  static let clusterSheepSizeDense: CGFloat = 21

  /// Gap between sheep in the 2-column cluster (both axes).
  static let artClusterSpacing: CGFloat = 1

  /// Hairline border width of the art tile (its own value, independent of the
  /// thinner card hairline — the tile reads as a distinct framed thumbnail).
  static let artTileBorderWidth: CGFloat = 1

  /// The most sheep the cluster ever draws, regardless of `agentCount`. The
  /// real gallery maxes at 5 agents; the ceiling is 6 as a safety valve for a
  /// curator-authored 6-agent scenario — beyond it the footer's exact
  /// "N agents" carries the count and the tile approximates.
  static let maxClusterSheep: Int = 6

  /// Per-sheep size for a cluster of `count` sheep, stepped so denser clusters
  /// stay within the fixed 74pt tile: 1 → solo (large), 2 → pair, 3–4 → 2×2
  /// base, 5–6 → dense (2×3). `count` is the already-clamped
  /// ``GalleryCatalogRowFormat/clusterSheepCount(agentCount:)`` value.
  static func clusterSheepSize(forCount count: Int) -> CGFloat {
    switch count {
    case ...1: return clusterSheepSizeSolo
    case 2: return clusterSheepSizePair
    case 3, 4: return artSheepSize
    default: return clusterSheepSizeDense
    }
  }

  // MARK: Card

  /// Horizontal gap between the art tile and the text body.
  static let cardSpacing: CGFloat = 13

  /// Corner radius of the landscape card.
  static let cardCornerRadius: CGFloat = 16

  /// Inner padding around the card's content.
  static let cardPadding: CGFloat = 13

  // MARK: List

  /// Vertical gap between consecutive catalog cards.
  static let listSpacing: CGFloat = 12

  /// Outer horizontal margin from the screen edge to the cards. The catalog
  /// list is inset (unlike the full-bleed `.grouped` empty-state band).
  static let listHorizontalMargin: CGFloat = 16

  // MARK: Body

  /// Description truncation limit (2-line catalog blurb). `Int`, also
  /// `Equatable` — asserted by the change-detector.
  static let descriptionLineLimit: Int = 2

  /// Top spacing between the title row and the inline category chip.
  static let titleChipSpacing: CGFloat = 5

  /// Top spacing between the category chip and the description.
  static let descriptionTopPadding: CGFloat = 6

  /// Top spacing between the description and the `N agents · N rounds` footer.
  static let footerTopPadding: CGFloat = 7

  // MARK: Category chip

  /// Horizontal inner padding of the category chip.
  static let catchipHorizontalPadding: CGFloat = 7

  /// Vertical inner padding of the category chip.
  static let catchipVerticalPadding: CGFloat = 2

  /// Corner radius of the category chip.
  static let catchipCornerRadius: CGFloat = 6
}
