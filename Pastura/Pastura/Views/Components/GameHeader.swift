import SwiftUI

/// Sticky frosted bar rendered at the top of chat-stream surfaces
/// (DL-time demo, live simulation; future Results-screen adoption is
/// deferred — see #297).
///
/// Two-row layout:
/// - **Row 1** — leaf icon + scenario title (`titleScenario`, 16pt) +
///   `GameHeaderStatus` pill (always visible).
/// - **Row 2** — `ROUND X / Y` (`metaRound`, mono UPPER) + `·`
///   separator + phase name (`metaInline`) + `Spacer` + tok/s
///   (`metaInline`, right-aligned). Each fragment is conditional —
///   nil/missing inputs collapse the corresponding piece.
///
/// First-frame correctness for the title comes from ADR-008's
/// `RouteHint<String>` pattern: `scenarioName` (the loaded VM value,
/// authoritative once available) falls back to `initialName` (the
/// push-time hint) and then to an empty string while loading. This
/// sink replaces `.navigationTitle()`'s previous role on
/// `SimulationView` — see ADR-008 §Amendment.
///
/// Sim opts out of `extendsIntoTopSafeArea` (default `false`) because
/// its NavigationStack-pushed nav bar already paints the top safe
/// area; Demo opts in (`true`) because it presents inside
/// `.fullScreenCover` with no system nav bar above it.
public struct GameHeader: View {

  /// Resolved scenario title (authoritative). Pass `nil` while the
  /// VM is still loading — `initialName` will fill in for the first
  /// frame.
  public let scenarioName: String?
  /// Push-time first-frame hint per ADR-008. Used only when
  /// `scenarioName` is nil.
  public let initialName: String?
  /// Always-visible trailing pill. See `GameHeaderStatus` for the
  /// 7-case shape and color groupings.
  public let status: GameHeaderStatus
  /// Round-counter numerator. ROUND fragment renders only when both
  /// `currentRound` and `totalRounds` are non-nil.
  public let currentRound: Int?
  /// Round-counter denominator. ROUND fragment renders only when
  /// both `currentRound` and `totalRounds` are non-nil.
  public let totalRounds: Int?
  /// Current phase label — already-localized display string from the
  /// caller (e.g., `"発言ラウンド 1"`). Nil hides the phase fragment.
  public let phaseLabel: String?
  /// Inference rate for Sim's right-side meta. Nil hides the tok/s
  /// fragment — Demo passes nil per the "no synthetic numbers"
  /// product principle.
  public let tokensPerSecond: Double?
  /// When `true`, the frosted background extends behind the top
  /// safe area (status bar / Dynamic Island). See type doc-comment
  /// for Demo / Sim guidance.
  public let extendsIntoTopSafeArea: Bool

  public init(
    scenarioName: String?,
    initialName: String? = nil,
    status: GameHeaderStatus,
    currentRound: Int? = nil,
    totalRounds: Int? = nil,
    phaseLabel: String? = nil,
    tokensPerSecond: Double? = nil,
    extendsIntoTopSafeArea: Bool = false
  ) {
    self.scenarioName = scenarioName
    self.initialName = initialName
    self.status = status
    self.currentRound = currentRound
    self.totalRounds = totalRounds
    self.phaseLabel = phaseLabel
    self.tokensPerSecond = tokensPerSecond
    self.extendsIntoTopSafeArea = extendsIntoTopSafeArea
  }

  // MARK: - Pure helpers (extracted for unit-test reach per ADR-009)

  /// Three-tier first-frame fallback chain — see ADR-008.
  static func resolveDisplayedTitle(
    scenarioName: String?, initialName: String?
  ) -> String {
    scenarioName ?? initialName ?? ""
  }

  /// Localized ROUND label. Source key `"Round %lld / %lld"` lives in
  /// `Localizable.xcstrings`; `metaRound` typography UPPERs the en
  /// rendering at draw time, so the source string stays mixed-case.
  static func formatRoundLabel(current: Int, total: Int) -> String {
    String(format: String(localized: "Round %lld / %lld"), current, total)
  }

  /// Tok/s display string. Intentionally not localized — `tok/s` is a
  /// technical unit treated as universal (matches existing
  /// `InferenceStatsFormatter` convention).
  static func formatTokensPerSecond(_ value: Double) -> String {
    String(format: "%.1f tok/s", value)
  }

  // MARK: - Layout

  private var displayedTitle: String {
    Self.resolveDisplayedTitle(scenarioName: scenarioName, initialName: initialName)
  }

  /// Whether row 2 has any visible fragment. Row collapses entirely
  /// when none of ROUND / phase / tok/s is present.
  private var hasMetaRow: Bool {
    (currentRound != nil && totalRounds != nil)
      || phaseLabel != nil
      || tokensPerSecond != nil
  }

  /// Combined accessibility label so VoiceOver reads the header as
  /// one focusable element rather than fragmenting across icon /
  /// title / pill / meta-row pieces.
  private var accessibilityLabelText: String {
    var parts: [String] = [status.label]
    if !displayedTitle.isEmpty { parts.append(displayedTitle) }
    if let currentRound, let totalRounds {
      parts.append(Self.formatRoundLabel(current: currentRound, total: totalRounds))
    }
    if let phaseLabel { parts.append(phaseLabel) }
    if let tokensPerSecond {
      parts.append(Self.formatTokensPerSecond(tokensPerSecond))
    }
    return parts.joined(separator: ", ")
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      titleRow
      if hasMetaRow {
        metaRow
      }
    }
    // Padding values are pinned to the design hand-off (HEADER_UPDATE.md
    // — top 12 / x 18 / bottom 10) rather than the Spacing.* token scale
    // because the GameHeader has its own dimensional spec independent
    // of the chat-stream rhythm those tokens were tuned for.
    .padding(EdgeInsets(top: 12, leading: 18, bottom: 10, trailing: 18))
    .background {
      ZStack {
        Color.screenBackground.opacity(0.78)
        Rectangle().fill(.ultraThinMaterial)
      }
      .modifier(GameHeaderTopSafeAreaExtension(enabled: extendsIntoTopSafeArea))
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.ink.opacity(0.07))
        .frame(height: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabelText)
  }

  private var titleRow: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
      LeafIcon()
        .frame(width: 9, height: 9)
      Text(displayedTitle)
        .textStyle(Typography.titleScenario)
        .foregroundStyle(Color.ink)
      Spacer(minLength: Spacing.xs)
      statusPill
    }
  }

  @ViewBuilder
  private var metaRow: some View {
    HStack(alignment: .center, spacing: 6) {
      if let currentRound, let totalRounds {
        Text(Self.formatRoundLabel(current: currentRound, total: totalRounds))
          .textStyle(Typography.metaRound)
          .foregroundStyle(Color.mossDark)
          .monospacedDigit()
        if phaseLabel != nil {
          Text("·")
            .textStyle(Typography.metaInline)
            .foregroundStyle(Color.headerRule)
        }
      }
      if let phaseLabel {
        Text(phaseLabel)
          .textStyle(Typography.metaInline)
          .foregroundStyle(Color.headerMetaInk)
      }
      Spacer(minLength: Spacing.xs)
      if let tokensPerSecond {
        Text(Self.formatTokensPerSecond(tokensPerSecond))
          .textStyle(Typography.metaInline)
          .foregroundStyle(Color.headerMetaSubdued)
          .monospacedDigit()
      }
    }
  }

  private var statusPill: some View {
    Text(status.label)
      .textStyle(Typography.pillStatus)
      .foregroundStyle(status.foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule().fill(status.background)
      )
  }
}

// MARK: - Helpers

/// 9×9 half-circle leaf accent for the title row. Visual translation
/// of `header_reference.html`'s `.gh-leaf` (border-radius 50%/0 +
/// rotate 45°) using SwiftUI's trim-on-Circle approximation.
private struct LeafIcon: View {
  var body: some View {
    Circle()
      .trim(from: 0, to: 0.5)
      .fill(Color.moss.opacity(0.75))
      .rotationEffect(.degrees(45))
  }
}

/// Conditionally applies `.ignoresSafeArea(.container, edges: .top)`.
/// `ViewModifier` form keeps the conditional out of the view-builder
/// path so the type system doesn't infer two divergent body shapes.
/// Mirrors the helper inside `PhaseHeader.swift` (which is removed in
/// PR 3 commit 6); the duplication is deliberate for the migration
/// period.
private struct GameHeaderTopSafeAreaExtension: ViewModifier {
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

#Preview("Demo (preset + phase, no tok/s)") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "ワードウルフ",
      status: .demoing,
      currentRound: 1,
      totalRounds: 4,
      phaseLabel: "個別発言",
      extendsIntoTopSafeArea: true
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Simulating") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .simulating,
      currentRound: 2,
      totalRounds: 5,
      phaseLabel: "negotiation",
      tokensPerSecond: 16.5
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Paused") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .paused,
      currentRound: 2,
      totalRounds: 5,
      phaseLabel: "negotiation",
      tokensPerSecond: 12.3
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Completed") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .completed,
      currentRound: 5,
      totalRounds: 5,
      phaseLabel: "scoreboard"
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("First-frame fallback (initialName)") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: nil,
      initialName: "ワードウルフ",
      status: .simulating,
      phaseLabel: "loading"
    )
    Spacer()
  }
  .background(Color.screenBackground)
}
