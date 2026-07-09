import SwiftUI

/// A landscape "catalog card" row for the さがす (Browse / Shared Scenarios)
/// tab — a leading ``ScenarioArtTile`` plus a body of title (+ optional badge),
/// an inline category chip, a 2-line description, and a `N agents · N rounds`
/// footer. Introduced for the tab-identity redesign (PR2, #777) so Browse reads
/// as a spaced card catalog, visually distinct from the Home compact rows and
/// the Past Results timeline.
///
/// Presentation-only: it takes already-resolved values (``Model``), never the
/// `GalleryScenario` domain type, so it stays unit-testable (ADR-009) and
/// SPM-extraction-safe — the caller maps its record into the model. Mirrors
/// ``ScenarioSummaryRow`` (which Home still uses; Browse moves to this card,
/// and the shared row's retirement is deferred to PR3).
struct GalleryCatalogRow: View {
  /// Resolved, display-ready values for one catalog card.
  ///
  /// Intentionally **not** `Equatable` — auto-synthesized `Equatable` on a
  /// default-MainActor value type makes its conformance lookup MainActor-bound,
  /// which would force any future `nonisolated` comparator to a `@MainActor`
  /// test suite (swift-isolation.md Pattern 5). The change-detector test asserts
  /// ``GalleryCatalogMetrics`` / ``GalleryCatalogRowFormat`` instead.
  struct Model {
    let title: String
    let badge: ScenarioBadge?
    /// Already-localized category name shown in the inline chip (e.g. "Ethics").
    let category: String
    let description: String?
    let agentCount: Int?
    let rounds: Int?
    /// Already-resolved signature phase for the art-tile glyph badge, or `nil`
    /// for no badge. Resolved at the mapping boundary (the Model carries
    /// display-ready values, never the raw `phases` array).
    let signature: ScenarioSignaturePhase?

    init(
      title: String,
      badge: ScenarioBadge? = nil,
      category: String,
      description: String? = nil,
      agentCount: Int? = nil,
      rounds: Int? = nil,
      signature: ScenarioSignaturePhase? = nil
    ) {
      self.title = title
      self.badge = badge
      self.category = category
      self.description = description
      self.agentCount = agentCount
      self.rounds = rounds
      self.signature = signature
    }
  }

  let model: Model

  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: GalleryCatalogMetrics.cardCornerRadius, style: .continuous)
    return HStack(alignment: .top, spacing: GalleryCatalogMetrics.cardSpacing) {
      ScenarioArtTile(agentCount: model.agentCount, signature: model.signature)
      bodyColumn
    }
    .padding(GalleryCatalogMetrics.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.bubbleBackground, in: shape)
    .overlay(shape.stroke(Color.rule, lineWidth: PasturaCardMetrics.borderWidth))
    .shadow(
      color: PasturaShadows.tight.color.color, radius: PasturaShadows.tight.radius,
      x: PasturaShadows.tight.x, y: PasturaShadows.tight.y
    )
    // Full-card hit target (the prior `galleryRow` carried this via
    // `.contentShape`; the catalog card drops the chevron, so re-assert it).
    .contentShape(Rectangle())
    // Announce the card as one actionable cell (title + badge + category +
    // meta), matching the prior row's single-tap-target VoiceOver semantics.
    .accessibilityElement(children: .combine)
  }

  private var bodyColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(model.title)
          .font(.headline)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        if let badge = model.badge {
          badgeView(badge)
        }
      }
      categoryChip
      if let description = model.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(GalleryCatalogMetrics.descriptionLineLimit)
          .truncationMode(.tail)
          .padding(.top, GalleryCatalogMetrics.descriptionTopPadding)
      }
      // Push the footer to the card's bottom edge so cards of differing
      // description length keep a consistent footer baseline (lookbook
      // `margin-top:auto`).
      Spacer(minLength: 0)
      footer
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Inline category chip — mossDark text on the moss `selected` wash, mirroring
  /// the filter-chip accent without the capsule (a quieter inline tag).
  private var categoryChip: some View {
    Text(model.category)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(Color.mossDark)
      .padding(.horizontal, GalleryCatalogMetrics.catchipHorizontalPadding)
      .padding(.vertical, GalleryCatalogMetrics.catchipVerticalPadding)
      .background(
        Color.selected,
        in: RoundedRectangle(
          cornerRadius: GalleryCatalogMetrics.catchipCornerRadius, style: .continuous)
      )
      .padding(.top, GalleryCatalogMetrics.titleChipSpacing)
  }

  @ViewBuilder private var footer: some View {
    let segments = GalleryCatalogRowFormat.footerSegments(
      agentCount: model.agentCount, rounds: model.rounds)
    if !segments.isEmpty {
      HStack(spacing: 6) {
        // Already-localized strings (+ the verbatim dot) — verbatim init so
        // they are not re-interpreted as LocalizedStringKey lookups.
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
          Text(verbatim: segment)
        }
      }
      .font(.caption)
      .foregroundStyle(Color.muted)
      .padding(.top, GalleryCatalogMetrics.footerTopPadding)
    }
  }

  /// Title-trailing provenance / update badge. Replicates
  /// ``ScenarioSummaryRow``'s badge styling minimally (rather than sharing a
  /// component) to keep this PR scoped to Browse — PR3's shared-row retirement
  /// is the right place to consolidate the two badge renderers.
  private func badgeView(_ badge: ScenarioBadge) -> some View {
    let isTint = badge.style == .tint
    return Text(badge.label)
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

/// Pure display-formatting helpers for ``GalleryCatalogRow`` / ``ScenarioArtTile``.
/// Side-effect-free and `nonisolated` so the non-trivial footer-assembly and
/// cluster-count logic are unit-testable without rendering (ADR-009 /
/// `.claude/rules/view-testing.md`).
nonisolated enum GalleryCatalogRowFormat {
  /// The ordered footer segments — `N agents` and `N rounds`, joined with a `·`
  /// **only when both are present**. Returns `[]` when neither exists so the
  /// caller renders no footer, and never emits a dangling separator (mirrors
  /// ``ScenarioSummaryRowFormat/captionSegments``). Reuses the existing
  /// `"%lld agents"` / `"%lld rounds"` catalog keys (Form B per i18n.md).
  static func footerSegments(agentCount: Int?, rounds: Int?) -> [String] {
    let agents = agentCount.map { String(format: String(localized: "%lld agents"), $0) }
    let roundsText = rounds.map { String(format: String(localized: "%lld rounds"), $0) }
    switch (agents, roundsText) {
    case (let agents?, let roundsText?): return [agents, "·", roundsText]
    case (let agents?, nil): return [agents]
    case (nil, let roundsText?): return [roundsText]
    case (nil, nil): return []
    }
  }

  /// The title-trailing badge for a Browse catalog card, resolved from the
  /// scenario's engine-compatibility and local install state (ADR-020 D4).
  ///
  /// An **incompatible** scenario always shows ``ScenarioBadge/updateRequired``
  /// — it can't run on this build, so the "installed" / "update-available"
  /// provenance signals are irrelevant and suppressed. A **compatible**
  /// scenario surfaces the update-available badge over installed (an updatable
  /// row is installed too, but the "changed" signal is the more useful one),
  /// or no badge when it is neither installed nor updatable.
  static func badge(
    compatible: Bool, hasUpdate: Bool, isInstalled: Bool
  ) -> ScenarioBadge? {
    guard compatible else { return .updateRequired }
    if hasUpdate { return .update }
    if isInstalled { return .installed }
    return nil
  }

  /// Number of sheep the ``ScenarioArtTile`` cluster should draw: clamped to
  /// `[0, maxClusterSheep]`. Unknown (`nil`) or non-positive counts return `0`
  /// — the catalog never fabricates agent data the rest of the app hides
  /// (mirrors `HomeScenarioRowFormat`'s unknown-count handling).
  static func clusterSheepCount(agentCount: Int?) -> Int {
    guard let agentCount, agentCount > 0 else { return 0 }
    return min(agentCount, GalleryCatalogMetrics.maxClusterSheep)
  }

  /// The headline phase the art tile surfaces as its glyph badge, picked from
  /// `phases` by a **fixed, corpus-independent** priority order
  /// (``ScenarioSignaturePhase/priorityOrder``). Scans that order top-down and
  /// returns the first kind present; if the scenario carries only scaffolding
  /// (or unknown) phases, falls back to ``ScenarioSignaturePhase/discuss``.
  /// Returns `nil` — no badge — only when `phases` is absent / empty (an older
  /// feed predating the key), mirroring the unknown-`agentCount` "draw nothing"
  /// posture.
  ///
  /// The order is a property of the phase *vocabulary* (how strongly each kind
  /// defines the scenario's mechanic), NOT the gallery's current distribution,
  /// so a scenario's badge never shifts as the gallery grows.
  static func signaturePhase(phases: [String]?) -> ScenarioSignaturePhase? {
    guard let phases, !phases.isEmpty else { return nil }
    let present = Set(phases.compactMap(ScenarioSignaturePhase.init(phaseRawValue:)))
    for candidate in ScenarioSignaturePhase.priorityOrder where present.contains(candidate) {
      return candidate
    }
    return .discuss
  }
}

/// The "headline" mechanic a Browse art tile surfaces as a single glyph badge —
/// the one phase kind that most defines how a scenario is played. Derived from a
/// scenario's phase list by ``GalleryCatalogRowFormat/signaturePhase(phases:)``.
///
/// `nonisolated` so the pure-logic derivation + its change-detector test read
/// the cases from a non-`@MainActor` context (swift-isolation.md Pattern 5 —
/// without it the auto-synth `Equatable` conformance lookup would be
/// MainActor-bound and the nonisolated test couldn't compare cases).
nonisolated enum ScenarioSignaturePhase: CaseIterable {
  case eliminate
  case choose
  case conditional
  case eventInject
  case vote
  case scoreCalc
  /// Fallback for scaffolding-only / unknown-phase scenarios — never mapped
  /// from a phase raw value, so it is absent from ``priorityOrder``.
  case discuss

  /// Fixed scan order (highest mechanic-salience first). `discuss` is the
  /// fallback and is intentionally excluded. event_inject ranks above vote so a
  /// disruption-driven scenario reads by its real hook rather than its (common)
  /// vote step.
  static let priorityOrder: [ScenarioSignaturePhase] = [
    .eliminate, .choose, .conditional, .eventInject, .vote, .scoreCalc
  ]

  /// Maps a ``PhaseType`` to its signature kind, or `nil` for the
  /// signature-less scaffolding / interaction kinds (`speak_all` /
  /// `speak_each` / `reflect` / `whisper` / `assign` / `summarize` /
  /// `relationship_update`) — none of which contribute a headline.
  ///
  /// `raw` is parsed through ``PhaseType`` first, so an unknown raw value (a
  /// gallery feed newer than this build) returns `nil` and the caller's
  /// `compactMap` drops it — preserving ADR-020's forward-compat grey-out
  /// posture. The `switch` is then **no-default exhaustive over `PhaseType`**
  /// (ADR-022 D2): a future phase kind breaks this file's compile until its
  /// headline decision is made here, instead of silently falling through to
  /// `nil`.
  init?(phaseRawValue raw: String) {
    guard let phaseType = PhaseType(rawValue: raw) else { return nil }
    switch phaseType {
    case .eliminate: self = .eliminate
    case .choose: self = .choose
    case .conditional: self = .conditional
    case .eventInject: self = .eventInject
    case .vote: self = .vote
    case .scoreCalc: self = .scoreCalc
    // Signature-less kinds — no headline glyph; a scenario carrying only these
    // falls back to `discuss` in `signaturePhase(phases:)`.
    case .speakAll, .speakEach, .reflect, .whisper, .assign, .summarize,
      .relationshipUpdate:
      return nil
    }
  }

  /// SF Symbol name for the glyph badge (visual reference: the lookbook
  /// `docs/design/tab-identity/scenario-tile-lookbook.html` 案A legend).
  var sfSymbolName: String {
    switch self {
    case .eliminate: return "xmark.circle"
    case .choose: return "arrow.triangle.branch"
    case .conditional: return "diamond"
    case .eventInject: return "bolt.fill"
    case .vote: return "checkmark.square"
    case .scoreCalc: return "chart.bar"
    case .discuss: return "bubble.left.and.bubble.right"
    }
  }
}
