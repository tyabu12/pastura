import SwiftUI

/// One row's slice of the Home scenario list's single grouped card (d3, #684).
///
/// Home keeps `List` (for swipe-`.onDelete`) but renders its rows as one
/// continuous bordered card rather than the pre-#684 per-row ``PasturaCard``
/// (which spaced rows 18pt apart). Each slice fills ``Color/bubbleBackground``
/// and rounds only the card's outer corners (`.top` / `.bottom` / `.only`).
///
/// The 1pt ``Color/rule`` border reuses the **same** `.continuous`
/// `RoundedRectangle` + `strokeBorder` form as ``PasturaCard`` (so the corner
/// curvature matches the other browse cards exactly), but on interior slices it
/// is grown past the row by the corner radius (negative padding) and clipped to
/// the fill — so the horizontal edge shared with the adjacent row is never
/// drawn. That avoids both the doubled-hairline artifact of a per-slice
/// `strokeBorder` and the corner gaps of a hand-traced circular-arc border. The
/// row-to-row hairline is instead a single full-width 1pt line at the top of
/// each non-first slice, matching the `Divider`-based ``PasturaRowDivider`` the
/// `ScrollView`-host browse screens use.
struct ScenarioCardSlice: View {
  /// A row's position within the grouped card. `.only` is the sole row.
  enum Position { case only, top, middle, bottom }

  let position: Position

  var body: some View {
    let radius = PasturaCardMetrics.cornerRadius
    let topRounded = position == .only || position == .top
    let bottomRounded = position == .only || position == .bottom
    let fillShape = UnevenRoundedRectangle(
      topLeadingRadius: topRounded ? radius : 0,
      bottomLeadingRadius: bottomRounded ? radius : 0,
      bottomTrailingRadius: bottomRounded ? radius : 0,
      topTrailingRadius: topRounded ? radius : 0,
      style: .continuous)
    fillShape
      .fill(Color.bubbleBackground)
      // Border: full continuous rounded rect, grown past the row on the
      // interior (shared) edge(s) and then clipped to the fill, so the shared
      // horizontal edge is never stroked (no doubling) while the visible outer
      // corners stay continuous — identical curvature to ``PasturaCard``.
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Color.rule, lineWidth: PasturaCardMetrics.borderWidth)
          .padding(.top, topRounded ? 0 : -radius)
          .padding(.bottom, bottomRounded ? 0 : -radius)
      }
      .clipShape(fillShape)
      // Single inter-row hairline at the junction (top of every non-first
      // slice) — full width, like PasturaRowDivider on the other screens.
      .overlay(alignment: .top) {
        if position == .middle || position == .bottom {
          Color.rule.frame(height: PasturaCardMetrics.borderWidth)
        }
      }
  }
}
