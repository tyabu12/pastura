import SwiftUI

/// Sticky frosted bar rendered at the top of chat-stream surfaces
/// (DL-time demo, live simulation; future Results-screen adoption is
/// deferred — see #297).
///
/// Two-row layout:
/// - **Row 1** (`titleRow`) — leaf icon + scenario title (`titleScenario`,
///   16pt, single-line truncating) + `GameHeaderStatus` pill (always
///   visible, fixed-size, layout-priority protected).
/// - **Row 2** (`metaRow`) — `ROUND X / Y` (`metaRound`, mono UPPER) +
///   `·` separator + phase name (`metaInline`) + `Spacer` + tok/s
///   (`metaInline`, right-aligned). Each fragment is conditional —
///   nil/missing inputs collapse the corresponding piece. The whole
///   row collapses when all three are nil.
///
/// First-frame correctness for the title comes from ADR-008's
/// `RouteHint<String>` pattern: `scenarioName` (the loaded VM value,
/// authoritative once available) falls back to `initialName` (the
/// push-time hint) and then to an empty string while loading.
///
/// ## Rendering modes
///
/// - **Unified `body`** — Demo's `ModelDownloadHostView` path. Both
///   rows render together inside a single frosted-material container,
///   `extendsIntoTopSafeArea: true` so the moss-tinted material fills
///   behind the status bar / Dynamic Island. VoiceOver reads as a
///   single combined element.
/// - **Split `titleRow` / `metaRow`** — Sim's "fill the bar" path
///   (ADR-008 §Amendment 2026-05-10). Title row is hosted inside the
///   system nav bar via `ToolbarItem(placement: .principal)`; meta
///   row is mounted via `.safeAreaInset(edge: .top)` directly below.
///   The system bar's background is hidden via
///   `.toolbarBackground(.hidden, for: .navigationBar)` so the chevron
///   stays interactive (preserving swipe-back gesture and the upstream
///   view's title as the back-button label) while the 44pt slot is
///   reclaimed by the title row's content. VoiceOver traversal becomes
///   3-stop: back-button → title row → meta row → first chat row. The
///   caller is responsible for providing frosted-material backgrounds
///   per row in this mode (the sub-views render content only).
///
/// `extendsIntoTopSafeArea` applies only to the unified `body`; the
/// split sub-views ignore it (the host decides their containment).
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
  /// Round-counter pair. ROUND fragment renders only when non-nil;
  /// the pair-or-nothing semantic is enforced by `GameHeaderRound`
  /// itself (#313) so callers cannot construct a partial pair.
  public let round: GameHeaderRound?
  /// Current phase label — already-localized display string from the
  /// caller (e.g., `"発言ラウンド 1"`). Nil hides the phase fragment.
  public let phaseLabel: String?
  /// Inference rate for Sim's right-side meta. Nil hides the tok/s
  /// fragment — Demo passes nil per the "no synthetic numbers"
  /// product principle.
  public let tokensPerSecond: Double?
  /// When `true`, the unified `body`'s frosted background extends
  /// behind the top safe area (status bar / Dynamic Island). Has no
  /// effect on `titleRow` / `metaRow` when used as split sub-views.
  public let extendsIntoTopSafeArea: Bool

  public init(
    scenarioName: String?,
    initialName: String? = nil,
    status: GameHeaderStatus,
    round: GameHeaderRound? = nil,
    phaseLabel: String? = nil,
    tokensPerSecond: Double? = nil,
    extendsIntoTopSafeArea: Bool = false
  ) {
    self.scenarioName = scenarioName
    self.initialName = initialName
    self.status = status
    self.round = round
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
  /// universal technical unit. See `InferenceStatsFormatter` doc for
  /// the canonical convention statement and the leak-detection.md
  /// Permanent carve-out entry.
  static func formatTokensPerSecond(_ value: Double) -> String {
    String(format: "%.1f tok/s", value)
  }

  /// VoiceOver label for the title row (status + scenario name).
  /// Status comes first so the user hears the screen state before
  /// the scenario identity — matches the original combined-label
  /// ordering. Empty title (both `scenarioName` and `initialName` nil
  /// or empty string) collapses to status-only.
  static func titleAccessibilityLabel(
    scenarioName: String?, initialName: String?, status: GameHeaderStatus
  ) -> String {
    let title = resolveDisplayedTitle(
      scenarioName: scenarioName, initialName: initialName)
    var parts: [String] = [status.label]
    if !title.isEmpty { parts.append(title) }
    return parts.joined(separator: String(localized: ", "))
  }

  /// VoiceOver label for the meta row (round + phase + tok/s).
  /// Returns the empty string when all three inputs are nil — caller
  /// can guard on `isEmpty` to skip applying the label when the row
  /// itself is collapsed. Locale-aware separator (`, ` en / `、` ja).
  static func metaAccessibilityLabel(
    round: GameHeaderRound?, phaseLabel: String?, tokensPerSecond: Double?
  ) -> String {
    var parts: [String] = []
    if let round {
      parts.append(formatRoundLabel(current: round.current, total: round.total))
    }
    if let phaseLabel { parts.append(phaseLabel) }
    if let tokensPerSecond {
      parts.append(formatTokensPerSecond(tokensPerSecond))
    }
    return parts.joined(separator: String(localized: ", "))
  }

  // MARK: - Layout

  private var displayedTitle: String {
    Self.resolveDisplayedTitle(scenarioName: scenarioName, initialName: initialName)
  }

  /// Whether row 2 has any visible fragment. Row collapses entirely
  /// when none of ROUND / phase / tok/s is present. Exposed so the
  /// split-rendering host (Sim's `safeAreaInset`) can guard whether
  /// to mount `metaRow` at all.
  var hasMetaRow: Bool {
    round != nil || phaseLabel != nil || tokensPerSecond != nil
  }

  private var titleA11yLabel: String {
    Self.titleAccessibilityLabel(
      scenarioName: scenarioName, initialName: initialName, status: status)
  }

  private var metaA11yLabel: String {
    Self.metaAccessibilityLabel(
      round: round, phaseLabel: phaseLabel, tokensPerSecond: tokensPerSecond)
  }

  /// Combined label for the unified `body` rendering — preserves the
  /// pre-split single-stop UX (Demo path). The split sub-views own
  /// their own labels independently when hosted in different
  /// containers (Sim path).
  private var combinedAccessibilityLabel: String {
    let title = titleA11yLabel
    let meta = metaA11yLabel
    if meta.isEmpty { return title }
    return "\(title)\(String(localized: ", "))\(meta)"
  }

  // Local layout constants — the GameHeader has its own dimensional
  // spec (HEADER_UPDATE.md design hand-off) independent of the
  // chat-stream rhythm the `Spacing.*` token scale was tuned for. Named
  // here so a future grep finds the GameHeader spec deliberately rather
  // than chasing magic numbers.
  private static let headerInsets = EdgeInsets(
    top: 12, leading: 18, bottom: 10, trailing: 18)
  private static let metaRowSpacing: CGFloat = 6

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      titleRow
      if hasMetaRow {
        metaRow
      }
    }
    .padding(Self.headerInsets)
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
    .accessibilityLabel(combinedAccessibilityLabel)
  }

  /// Title row — leaf icon + scenario name + status pill. Renders
  /// content only (no background); caller wraps with material as
  /// needed when used as a split sub-view.
  ///
  /// Layout contract (Sim's `ToolbarItem(.principal)` placement is
  /// width-constrained on small iPhones — see ADR-008 §Amendment
  /// 2026-05-10):
  /// - Title shrinks first via `.lineLimit(1) + .truncationMode(.tail)`.
  ///   No `.minimumScaleFactor` — the design system's load-bearing
  ///   fixed sizes (see `PasturaTextStyle.font`) preclude runtime
  ///   font scaling.
  /// - Status pill protected via `.fixedSize(horizontal: true) +
  ///   .layoutPriority(1)` so the pill never compresses; the title
  ///   yields the available width.
  /// - Carries `.accessibilityAddTraits(.isHeader)` so the rotor
  ///   "Headings" navigation can jump to it on Sim and Demo alike.
  var titleRow: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
      LeafIcon()
        .frame(width: 9, height: 9)
      Text(displayedTitle)
        .textStyle(Typography.titleScenario)
        .foregroundStyle(Color.ink)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: Spacing.xs)
      statusPill
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(titleA11yLabel)
    .accessibilityAddTraits(.isHeader)
  }

  /// Meta row — ROUND + phase + tok/s + drift. Renders content only (no
  /// background). Caller is responsible for collapsing the row entirely
  /// when `hasMetaRow == false` is preferred — when used as a split
  /// sub-view the placement (e.g., `.safeAreaInset`) decides whether
  /// to mount this view at all.
  ///
  /// Drift badge (#401): right-cluster, AFTER `Spacer(minLength:)`,
  /// AFTER tok/s. Subdued tone via `Color.headerMetaSubdued` matches
  /// tok/s — it's informational, not alarmist. ContentFilter (ADR-005)
  /// is a separate axis with its own UI treatment.
  @ViewBuilder
  var metaRow: some View {
    HStack(alignment: .center, spacing: Self.metaRowSpacing) {
      if let round {
        Text(Self.formatRoundLabel(current: round.current, total: round.total))
          .textStyle(Typography.metaRound)
          .foregroundStyle(Color.mossDark)
          .monospacedDigit()
        if phaseLabel != nil {
          Text(verbatim: "·")
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel(metaA11yLabel)
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

// Previews live in `GameHeader+Previews.swift` (sibling file) — the
// file_length cap was forcing a split after the row-split refactor.
