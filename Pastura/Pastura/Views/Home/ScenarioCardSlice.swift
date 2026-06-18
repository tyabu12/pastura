import SwiftUI

/// One row's slice of the Home scenario list's single grouped card (d3, #684).
///
/// Home keeps `List` (for swipe-`.onDelete`) but renders its rows as one
/// continuous bordered card rather than the pre-#684 per-row ``PasturaCard``
/// (which spaced rows 18pt apart). Each slice fills ``Color/bubbleBackground``,
/// rounds only the card's outer corners (`.top` / `.bottom` / `.only`), and
/// draws its 1pt ``Color/rule`` border via ``ScenarioCardBorder`` — which
/// traces **only the outer edges**, never the shared horizontal edge between
/// rows. The row-to-row hairline is instead a single full-width 1pt line at the
/// top of each non-first slice, matching the `Divider`-based ``PasturaRowDivider``
/// the `ScrollView`-host browse screens use. (The earlier `strokeBorder`-per-
/// slice form drew the shared edge twice, reading as a doubled/2pt divider.)
struct ScenarioCardSlice: View {
  /// A row's position within the grouped card. `.only` is the sole row.
  enum Position { case only, top, middle, bottom }

  let position: Position

  var body: some View {
    let radius = PasturaCardMetrics.cornerRadius
    let topRounded = position == .only || position == .top
    let bottomRounded = position == .only || position == .bottom
    UnevenRoundedRectangle(
      topLeadingRadius: topRounded ? radius : 0,
      bottomLeadingRadius: bottomRounded ? radius : 0,
      bottomTrailingRadius: bottomRounded ? radius : 0,
      topTrailingRadius: topRounded ? radius : 0,
      style: .continuous
    )
    .fill(Color.bubbleBackground)
    // Single inter-row hairline at the junction (top of every non-first
    // slice) — full width, like PasturaRowDivider on the other screens.
    .overlay(alignment: .top) {
      if position == .middle || position == .bottom {
        Color.rule.frame(height: PasturaCardMetrics.borderWidth)
      }
    }
    // Outer card border only (no interior horizontal edge → no doubling).
    // Pass plain `Bool`s (not `position`) so the `Shape` witness stays clear of
    // the default-MainActor `Position` Equatable conformance (swift-isolation
    // Pattern 5: `path(in:)` runs nonisolated).
    .overlay(
      ScenarioCardBorder(topRounded: topRounded, bottomRounded: bottomRounded, radius: radius)
        .stroke(Color.rule, lineWidth: PasturaCardMetrics.borderWidth))
  }
}

/// The outer edges of one ``ScenarioCardSlice`` — the left and right verticals
/// always, plus the rounded top and/or bottom for the card's end slices. It
/// deliberately omits the horizontal edge shared with an adjacent row so that
/// stroking adjacent slices never doubles the divider; the inter-row hairline is
/// drawn separately by ``ScenarioCardSlice``.
struct ScenarioCardBorder: Shape {
  let topRounded: Bool
  let bottomRounded: Bool
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let radius = self.radius
    let minX = rect.minX
    let maxX = rect.maxX
    let minY = rect.minY
    let maxY = rect.maxY
    var path = Path()

    // Left vertical edge (stops short of any rounded corner it meets).
    path.move(to: CGPoint(x: minX, y: topRounded ? minY + radius : minY))
    path.addLine(to: CGPoint(x: minX, y: bottomRounded ? maxY - radius : maxY))
    // Right vertical edge.
    path.move(to: CGPoint(x: maxX, y: topRounded ? minY + radius : minY))
    path.addLine(to: CGPoint(x: maxX, y: bottomRounded ? maxY - radius : maxY))
    // Top edge + corners (card top slice only).
    if topRounded {
      path.move(to: CGPoint(x: minX, y: minY + radius))
      path.addArc(
        tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + radius, y: minY),
        radius: radius)
      path.addLine(to: CGPoint(x: maxX - radius, y: minY))
      path.addArc(
        tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + radius),
        radius: radius)
    }
    // Bottom edge + corners (card bottom slice only).
    if bottomRounded {
      path.move(to: CGPoint(x: minX, y: maxY - radius))
      path.addArc(
        tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + radius, y: maxY),
        radius: radius)
      path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
      path.addArc(
        tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX, y: maxY - radius),
        radius: radius)
    }
    return path
  }
}
