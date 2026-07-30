import SwiftUI

/// The selection indicator at the trailing edge of each picker row.
///
/// - `filled == true`: solid moss-colored circle with a white check.
/// - `filled == false`: hairline-outline circle, transparent fill.
///
/// Decoration of the row's `.accessibilityAddTraits(.isSelected)` state —
/// the row itself carries the selection semantic for VoiceOver. The badge
/// is `.accessibilityHidden(true)` so VoiceOver doesn't announce a redundant
/// "filled circle" beside the row's "selected" trait.
///
/// The checkmark geometry mirrors the design-handoff Path (`M6.5 11.2 l3 3
/// 6,-6.4`) at the 22pt default, scaled by `size / 22`. Stroke width and
/// outline stroke width both scale with `size` so the visual weight stays
/// consistent across sizes.
struct CheckBadge: View {
  var size: CGFloat = 22
  var filled: Bool = false
  var tint: Color = .moss

  // Hand-off stroke widths at 22pt.
  private var outlineLineWidth: CGFloat { 1.4 * (size / 22) }
  private var checkLineWidth: CGFloat { 2.0 * (size / 22) }

  var body: some View {
    ZStack {
      if filled {
        Circle()
          .fill(tint)
        CheckmarkPath()
          // Deliberately on base `moss` (the `tint` default) rather than the
          // `mossDark` that on-accent *text* requires: a checkmark is a shape,
          // so WCAG 1.4.11's 3:1 non-text bar applies and ≈3.03:1 clears it —
          // by ~1%, so re-measure if `moss` ever shifts. Resolved by ADR-028
          // gate 1: `inkOnAccent` was paired (not `nightMoss` darkened), so
          // dark reads `nightInkOnAccent` on `nightMoss` at ≈6.40:1 — clears
          // both the 3:1 shape bar and the 4.5:1 text bar with headroom.
          .stroke(
            Color.inkOnAccent,
            style: StrokeStyle(
              lineWidth: checkLineWidth,
              lineCap: .round,
              lineJoin: .round
            )
          )
          // Inset slightly so the checkmark sits centered, not crowded
          // against the circle edge.
          .padding(size * 0.22)
      } else {
        // Handoff spec: `rgba(60,62,48,.25)` — low-contrast quiet outline.
        // Resolves to `Color.ink` at 25% alpha. Not promoted to a token
        // because no other surface uses this exact value yet.
        Circle()
          .stroke(
            Color.ink.opacity(0.25),
            lineWidth: outlineLineWidth
          )
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// The check stroke shape inside a unit square, matching the hand-off
/// path coordinates `M6.5 11.2 l3 3 6,-6.4` (22pt viewBox, padding-adjusted
/// here to 0..1 unit space).
private struct CheckmarkPath: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // Map the handoff's 22-unit viewBox coordinates (inset to 0..1 by the
    // outer `.padding`) onto the actual rect. The 0.22 padding above
    // brings the 6.5..15.5 / 4.8..11.2 source range into rect.
    let start = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55)
    let middle = CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY)
    let end = CGPoint(x: rect.maxX, y: rect.minY)
    path.move(to: start)
    path.addLine(to: middle)
    path.addLine(to: end)
    return path
  }
}

#Preview {
  HStack(spacing: 24) {
    CheckBadge(filled: false)
    CheckBadge(filled: true)
    CheckBadge(size: 44, filled: false)
    CheckBadge(size: 44, filled: true)
  }
  .padding()
  .background(Color.screenBackground)
}
