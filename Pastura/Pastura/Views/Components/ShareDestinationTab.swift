import SwiftUI

/// Layout constants for the horizontal share-destination row, shared by
/// ``StoryShareSheet`` (utterance card) and ``ScenarioShareSheet`` (scenario
/// link). Extracted as a named enum so a change-detector unit test can pin them
/// (ADR-009 view-testing rule): the row is a visual-only surface with no manual
/// test trigger, so drift is caught by asserting these values rather than
/// rendering the View.
enum ShareDestinationLayout {
  /// Diameter of each circular destination icon.
  static let iconDiameter: CGFloat = 56
  /// SF Symbol / glyph point size inside the icon circle.
  static let iconGlyphSize: CGFloat = 24
  /// Fixed width of one icon-plus-label tab (drives the horizontal scroll).
  static let tabWidth: CGFloat = 76
  /// On-screen size of the (down-scaled) 360 pt card preview (StoryShareSheet).
  static let previewSide: CGFloat = 176
}

/// Circle fills for the share destinations. Centralized so both sheets use the
/// same brand ramps.
enum ShareDestinationFill {
  /// Moss brand gradient — the primary (system share) destination.
  static var moss: AnyShapeStyle {
    AnyShapeStyle(
      LinearGradient(
        colors: [Color.moss, Color.mossDark], startPoint: .topLeading,
        endPoint: .bottomTrailing))
  }

  /// Instagram-recognizable warm→violet gradient. Raw RGB (not palette tokens)
  /// because it deliberately evokes Instagram's brand ramp, not Pastura's moss.
  static var instagram: AnyShapeStyle {
    AnyShapeStyle(
      LinearGradient(
        colors: [
          Color(red: 0.98, green: 0.55, blue: 0.12),
          Color(red: 0.84, green: 0.16, blue: 0.46),
          Color(red: 0.35, green: 0.36, blue: 0.84)
        ], startPoint: .topLeading, endPoint: .bottomTrailing))
  }

  /// Solid black for the X destination.
  static var xBlack: AnyShapeStyle { AnyShapeStyle(Color.black) }

  /// Neutral chip fill for the utility (save / copy) destinations.
  static var neutral: AnyShapeStyle { AnyShapeStyle(Color.ink.opacity(0.08)) }
}

/// One icon-over-label share destination tab: a circular tinted icon with a
/// caption beneath, sized to ``ShareDestinationLayout/tabWidth``. Shared by both
/// share sheets so their rows stay visually identical.
struct ShareDestinationTab<Icon: View>: View {
  let label: String
  let fill: AnyShapeStyle
  let action: () -> Void
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        ZStack {
          Circle()
            .fill(fill)
            .frame(
              width: ShareDestinationLayout.iconDiameter,
              height: ShareDestinationLayout.iconDiameter)
          icon()
        }
        Text(label)
          .font(.caption2)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
          // Degrade gracefully at large Dynamic Type instead of truncating the
          // longer labels inside the fixed-width tab.
          .minimumScaleFactor(0.85)
      }
      .frame(width: ShareDestinationLayout.tabWidth)
    }
    .buttonStyle(.plain)
  }
}

/// A standard SF-symbol glyph sized for a ``ShareDestinationTab`` circle.
struct ShareTabSymbol: View {
  let systemName: String
  let tint: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: ShareDestinationLayout.iconGlyphSize, weight: .semibold))
      .foregroundStyle(tint)
  }
}

/// The double-struck 𝕏 (U+1D54F) standing in for the X wordmark inside a tab
/// circle. The tab's "Post to X" label carries the meaning, so it's decorative.
struct ShareTabXGlyph: View {
  var body: some View {
    Text(verbatim: "𝕏")
      .font(.system(size: ShareDestinationLayout.iconGlyphSize, weight: .bold))
      .foregroundStyle(.white)
  }
}
