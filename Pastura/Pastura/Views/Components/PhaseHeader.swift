import SwiftUI

/// A sticky header displayed at the top of the demo replay chat stream.
///
/// Shows the preset name as a small uppercase tag and the current phase label
/// as a larger title, with a right-aligned "DEMO中" status badge. A subtle
/// tinted material background and a 1pt bottom border separate the header from
/// the scrolling content beneath it.
///
/// ```swift
/// PhaseHeader(presetName: "WORD WOLF", phaseLabel: "発言ラウンド 1")
/// ```
public struct PhaseHeader: View {

  /// The scenario preset name displayed as an uppercase tag (e.g. "WORD WOLF").
  public let presetName: String

  /// The human-readable phase label displayed below the preset tag (e.g. "発言ラウンド 1").
  public let phaseLabel: String

  public var body: some View {
    HStack(alignment: .center, spacing: 0) {
      // MARK: Left area — diamond ornament + text stack
      HStack(alignment: .center, spacing: Spacing.xs) {
        // A 6pt square rotated 45° renders as a diamond. No dedicated shape
        // exists in SwiftUI for a filled diamond, so this is the idiomatic approach.
        Rectangle()
          .fill(Color.moss.opacity(0.7))
          .frame(width: 6, height: 6)
          .rotationEffect(.degrees(45))

        VStack(alignment: .leading, spacing: 3) {
          Text(presetName)
            .textStyle(Typography.tagPhase)
            .foregroundStyle(Color.moss)

          Text(phaseLabel)
            .textStyle(Typography.titlePhase)
            .foregroundStyle(Color.ink)
        }
      }

      Spacer(minLength: Spacing.xs)

      // MARK: Right area — DEMO中 badge
      Text("DEMO中")
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.moss)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: Radius.button)
            .fill(Color.moss.opacity(0.1))
        )
    }
    .padding(.vertical, 10)
    // 10pt vertical is intentional per spec — falls between xs(8) and s(12);
    // no exact token exists so the literal is used here.
    .padding(.horizontal, Spacing.l)
    .background {
      ZStack {
        // Tint layer beneath the material — approximates "screenBackground at 78%"
        Color.screenBackground.opacity(0.78)
        // Blur layer on top for the frosted-glass effect
        Rectangle().fill(.ultraThinMaterial)
      }
    }
    .overlay(alignment: .bottom) {
      // 1pt bottom border per spec: rgba(60,62,48,0.07)
      Rectangle()
        .fill(Color.black.opacity(0.07))
        .frame(height: 1)
    }
  }
}

// MARK: - Previews

#Preview("Default") {
  VStack(spacing: 0) {
    PhaseHeader(presetName: "WORD WOLF", phaseLabel: "発言ラウンド 1")
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Long phase label") {
  VStack(spacing: 0) {
    PhaseHeader(presetName: "PRISONERS DILEMMA", phaseLabel: "協議フェーズ 1 / 3")
    Spacer()
  }
  .background(Color.screenBackground)
}
