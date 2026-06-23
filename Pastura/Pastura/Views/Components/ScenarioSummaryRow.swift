import SwiftUI

/// A single scenario-summary row used by the Shared Scenarios (Browse) and
/// Past Results tabs. Renders the inner label only — title (+ trailing badge) /
/// sheep · rounds meta line / description / an optional `leading · trailing`
/// caption. The enclosing chevron and row padding stay in the **caller**
/// (Shared Scenarios' `galleryRow`, etc.), which already wraps this label with
/// a `NavigationLink` + disclosure chevron; keeping that chrome out of the
/// component leaves a single owner for the hit target and avoids two chevrons.
///
/// (Home moved to the denser ``HomeCompactScenarioRow`` in the tab-identity
/// redesign — PR3; whether this shared row can be retired is revisited once
/// Search's catalog redesign also lands.)
///
/// The component is presentation-only: it takes already-resolved values
/// (``ScenarioSummaryRow/Model``), never the Engine/Data domain types, so it
/// stays unit-testable (ADR-009) and SPM-extraction-safe. Each tab maps its
/// own record (`ScenarioRecord` / `GalleryScenario`) into the model.
struct ScenarioSummaryRow: View {
  /// Presentation model — the resolved, display-ready values for one row.
  nonisolated struct Model {
    let title: String
    let badge: ScenarioBadge?
    let agentCount: Int?
    let rounds: Int?
    let description: String?
    /// `nil` means "no limit" (e.g. wrap freely at accessibility Dynamic Type
    /// sizes); a positive value truncates with a tail ellipsis.
    let descriptionLineLimit: Int?
    /// Leading caption half (e.g. gallery category). `nil` when the tab has no
    /// category to show (Home) — the `·` separator is then suppressed.
    let captionLeading: String?
    /// Trailing caption half (e.g. estimated inference count).
    let captionTrailing: String?

    init(
      title: String,
      badge: ScenarioBadge? = nil,
      agentCount: Int? = nil,
      rounds: Int? = nil,
      description: String? = nil,
      descriptionLineLimit: Int? = nil,
      captionLeading: String? = nil,
      captionTrailing: String? = nil
    ) {
      self.title = title
      self.badge = badge
      self.agentCount = agentCount
      self.rounds = rounds
      self.description = description
      self.descriptionLineLimit = descriptionLineLimit
      self.captionLeading = captionLeading
      self.captionTrailing = captionTrailing
    }
  }

  let model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(model.title)
          .font(.headline)
          .foregroundStyle(Color.ink)
        Spacer()
        if let badge = model.badge {
          badgeView(badge)
        }
      }
      // sheep ×N · N rounds — reuses the shared meta line. Guarded so a row
      // without agent_count/rounds (parse failure / older feed) hides the line
      // rather than reserving empty space or leaving a stray dot.
      if HomeScenarioRowFormat.showsMetaLine(
        agentCount: model.agentCount, rounds: model.rounds) {
        HomeScenarioMetaLine(agentCount: model.agentCount, rounds: model.rounds)
      }
      if let description = model.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(model.descriptionLineLimit)
          .truncationMode(.tail)
      }
      captionRow
    }
  }

  /// The `leading · trailing` caption. Only the non-nil halves render, and the
  /// `·` separator appears solely between two present halves — so Home (which
  /// passes `captionLeading == nil`) shows no dangling leading dot.
  @ViewBuilder private var captionRow: some View {
    let segments = ScenarioSummaryRowFormat.captionSegments(
      leading: model.captionLeading, trailing: model.captionTrailing)
    if !segments.isEmpty {
      HStack(spacing: 8) {
        // Already-localized strings (+ the verbatim dot) — verbatim init so
        // they are not re-interpreted as LocalizedStringKey lookups.
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
          Text(verbatim: segment)
        }
      }
      .font(.caption)
      .foregroundStyle(Color.muted)
    }
  }

  private func badgeView(_ badge: ScenarioBadge) -> some View {
    let isTint = badge.style == .tint
    return Text(badge.label)
      // .bold matches Shared Scenarios' existing Installed/Update badges
      // (3 of 4 badge instances pre-unification); Home's Preset badge gains
      // bold as part of aligning to that style.
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        isTint ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15),
        in: Capsule()
      )
      .foregroundStyle(isTint ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
  }
}

/// The badge shown next to a scenario title. Each tab surfaces a subset:
/// Home shows ``preset`` / ``update``; Shared Scenarios shows ``installed`` /
/// ``update``.
nonisolated enum ScenarioBadge {
  case preset
  case installed
  case update

  /// Localized badge label.
  var label: String {
    switch self {
    case .preset: return String(localized: "Preset")
    case .installed: return String(localized: "Installed")
    case .update: return String(localized: "Update")
    }
  }

  /// Visual emphasis. The "this scenario changed" `update` badge uses the
  /// accent tint; the provenance badges (`preset` / `installed`) are quieter.
  var style: ScenarioBadgeStyle {
    switch self {
    case .preset, .installed: return .secondary
    case .update: return .tint
    }
  }
}

/// Badge visual emphasis — kept separate from ``ScenarioBadge`` so the
/// case → emphasis mapping is unit-testable without rendering.
nonisolated enum ScenarioBadgeStyle: Equatable {
  case secondary
  case tint
}

/// Pure display-formatting helpers for ``ScenarioSummaryRow``. Side-effect-free
/// and `nonisolated` so the row's non-trivial caption-assembly logic is
/// unit-testable without rendering (ADR-009 / `.claude/rules/view-testing.md`).
nonisolated enum ScenarioSummaryRowFormat {
  /// The ordered caption segments to render, joining the two halves with a
  /// `·` **only when both are present**. Returns `[]` when neither half exists
  /// so the caller renders no caption row, and never emits a leading/trailing
  /// dangling separator (the same hazard ``HomeScenarioRowFormat/showsMetaLine``
  /// guards against for the meta line).
  static func captionSegments(leading: String?, trailing: String?) -> [String] {
    switch (leading, trailing) {
    case (let leading?, let trailing?): return [leading, "·", trailing]
    case (let leading?, nil): return [leading]
    case (nil, let trailing?): return [trailing]
    case (nil, nil): return []
    }
  }
}
