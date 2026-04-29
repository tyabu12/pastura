import SwiftUI

/// Sticky frosted bar rendered at the top of chat-stream surfaces
/// (DL-time demo, live simulation, past-result replay). The component
/// itself owns only the chrome — material background, bottom border,
/// height-parity floor, and consistent vertical/horizontal padding —
/// while leading and trailing content are caller-composed via slot
/// closures. Demo packs a diamond + uppercase preset tag + phase
/// label into `leading` and a "DEMO中" badge into `trailing`; Sim
/// packs `Round X/Y` into `leading` and inference-stats + status
/// badge into `trailing`.
///
/// ```swift
/// PhaseHeader(extendsIntoTopSafeArea: true) {
///   HStack { /* diamond + 2-line VStack */ }
/// } trailing: {
///   Text("DEMO中") /* badge */
/// }
/// ```
public struct PhaseHeader<Leading: View, Trailing: View>: View {

  /// Floor applied to the leading slot so a single-line caller
  /// (Sim's `Round X/Y`) and a 2-line caller (Demo's preset tag +
  /// phase label) render at the same total header height. Pinned
  /// to fit Demo's natural typography stack (tagPhase ~9.5pt + 3pt
  /// spacing + titlePhase ~13pt ≈ 25.5pt) with comfort margin.
  /// Pinned by `PhaseHeaderContractTests`.
  ///
  /// Computed (not stored) because Swift forbids static stored
  /// properties on generic types — `PhaseHeader<Leading, Trailing>`
  /// has two type parameters, so the per-instantiation storage rule
  /// kicks in. Behavior is identical to a `let`.
  public static var minLeadingHeight: CGFloat { 32 }

  /// When `true`, the frosted background extends behind the top
  /// safe area (status bar / Dynamic Island). Demo opts in because
  /// it presents inside `.fullScreenCover` / `.needsModelDownload`
  /// slot with no system nav bar above it. Sim/Results stay at the
  /// default `false` because their NavigationStack-pushed nav bar
  /// already paints the top safe area with `.ultraThinMaterial`,
  /// and adding a second frosted layer beneath risks doubled blur.
  public let extendsIntoTopSafeArea: Bool

  let leading: () -> Leading
  let trailing: () -> Trailing

  public init(
    extendsIntoTopSafeArea: Bool = false,
    @ViewBuilder leading: @escaping () -> Leading,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.extendsIntoTopSafeArea = extendsIntoTopSafeArea
    self.leading = leading
    self.trailing = trailing
  }

  public var body: some View {
    HStack(alignment: .center, spacing: 0) {
      leading()
        .frame(minHeight: Self.minLeadingHeight, alignment: .leading)

      Spacer(minLength: Spacing.xs)

      trailing()
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
      // Conditional safe-area extension: see `extendsIntoTopSafeArea` doc.
      // Applied inside `.background { }` so only the chrome layer extends —
      // the foreground HStack stays within the safe area.
      .modifier(TopSafeAreaExtensionModifier(enabled: extendsIntoTopSafeArea))
    }
    .overlay(alignment: .bottom) {
      // 1pt bottom border per spec: rgba(60,62,48,0.07). `Color.ink`
      // is the project's "warm dark ink" token (`#2D2E26`).
      Rectangle()
        .fill(Color.ink.opacity(0.07))
        .frame(height: 1)
    }
  }
}

// MARK: - Helpers

/// Conditionally applies `.ignoresSafeArea(.container, edges: .top)`.
/// `ViewModifier` form keeps the conditional out of the view-builder
/// path so the type system doesn't infer two divergent body shapes.
private struct TopSafeAreaExtensionModifier: ViewModifier {
  let enabled: Bool

  func body(content: Content) -> some View {
    if enabled {
      content.ignoresSafeArea(.container, edges: .top)
    } else {
      content
    }
  }
}

// MARK: - Previews

#Preview("Demo (preset tag + phase label + DEMO中 badge)") {
  VStack(spacing: 0) {
    PhaseHeader(extendsIntoTopSafeArea: true) {
      HStack(alignment: .center, spacing: Spacing.xs) {
        Rectangle()
          .fill(Color.moss.opacity(0.7))
          .frame(width: 6, height: 6)
          .rotationEffect(.degrees(45))
        VStack(alignment: .leading, spacing: 3) {
          Text("WORD WOLF")
            .textStyle(Typography.tagPhase)
            .foregroundStyle(Color.moss)
          Text("発言ラウンド 1")
            .textStyle(Typography.titlePhase)
            .foregroundStyle(Color.ink)
        }
      }
    } trailing: {
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
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim (Round X/Y + status)") {
  VStack(spacing: 0) {
    PhaseHeader {
      Text("Round 2/5")
        .textStyle(Typography.metaEta)
        .monospacedDigit()
    } trailing: {
      HStack(spacing: 4) {
        ProgressView().scaleEffect(0.7)
        Text("Running")
          .textStyle(Typography.titlePhase)
          .foregroundStyle(Color.inkSecondary)
      }
    }
    Spacer()
  }
  .background(Color.screenBackground)
}
