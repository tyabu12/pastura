import SwiftUI

/// Lists past simulation runs. The aggregate History-tab root groups runs into
/// date sections (Today / This Week / …, P5); the pushed per-scenario detail
/// shows one scenario's runs under a single section.
struct ResultsView: View {
  let scope: ResultsScope

  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: ResultsViewModel?
  /// Gates the reappear refresh so it doesn't double-load on first
  /// appearance: `.onAppear` fires before `.task`, so until `.task` has
  /// created the view model and finished the first load this stays
  /// `false` and `onAppear` is a no-op.
  @State private var didInitialLoad = false
  /// Free-text scenario-name filter (aggregate root only — see
  /// ``AggregateSearchable``). Pushed into SQL via `applyFilter` so it reaches
  /// runs not yet on a loaded page.
  @State private var searchText = ""

  var body: some View {
    Group {
      if let viewModel {
        if viewModel.isLoading {
          ProgressView(String(localized: "Loading..."))
        } else if viewModel.sections.isEmpty {
          ContentUnavailableView(
            String(localized: "No Results"),
            systemImage: "tray",
            description: Text(String(localized: "Run a simulation to see results here"))
          )
          // Anchor for the empty-results screenshot-tour capture
          // (plain --ui-test without --ui-test-seed-results, #811).
          .accessibilityIdentifier("results.emptyState")
        } else if scope.isPushedDetail {
          // Pushed per-scenario detail keeps the grouped list — it is a single
          // section, not a tab root, so the timeline's rail + editorial header
          // would be noise. The tab-identity timeline (#767) is aggregate-only.
          resultsList(viewModel: viewModel)
        } else {
          timelineList(viewModel: viewModel)
        }
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Past Results"))
    // Inline title for both the History-tab root and the pushed detail, matching
    // the other tab roots (design-system § 5.11). The timeline's identity comes
    // from its rail/node shape — NOT a custom big in-scroll header — so the
    // familiar inline title stays and the `.searchable` field sits under it as
    // before (an in-scroll big title would push the search drawer above it, #767).
    .navigationBarTitleDisplayMode(.inline)
    // Back chrome only for the pushed-detail variant (`.scenario`); as the
    // History tab root (`.aggregate`) there is no parent to pop to. See
    // ``PushBackChrome``.
    .modifier(PushBackChrome(isPushed: scope.isPushedDetail))
    // Scenario-name filter — aggregate root only (a pushed per-scenario detail
    // already shows a single scenario, so it has nothing to filter).
    .modifier(AggregateSearchable(enabled: !scope.isPushedDetail, text: $searchText))
    .onChange(of: searchText) { _, newValue in
      guard let viewModel, !scope.isPushedDetail else { return }
      Task { await viewModel.applyFilter(newValue) }
    }
    .task {
      viewModel = ResultsViewModel(
        scenarioRepository: dependencies.scenarioRepository,
        simulationRepository: dependencies.simulationRepository,
        turnRepository: dependencies.turnRepository
      )
      await viewModel?.load(scope: scope)
      didInitialLoad = true
    }
    // Re-fetch when the list reappears (e.g. after a per-run delete in
    // ResultDetailView pops back) so the deleted run drops out. Incremental:
    // the aggregate path re-reads only the loaded depth from the top (keyset),
    // preserving scroll position; detail does a silent full reload (#586).
    .onAppear {
      guard didInitialLoad, let viewModel else { return }
      Task { await viewModel.refreshOnReappear(scope: scope) }
    }
  }

  private func resultsList(viewModel: ResultsViewModel) -> some View {
    ScrollView {
      // LazyVStack so off-screen rows don't decode/materialize eagerly and the
      // bottom load-more sentinel only fires once scrolled into view (#586).
      LazyVStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        ForEach(viewModel.sections) { section in
          PasturaSection(section.title, style: .grouped) {
            VStack(spacing: 0) {
              ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                  PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
                }
                NavigationLink(value: Route.resultDetail(simulationId: row.item.id)) {
                  resultRow(row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("results.row.\(row.item.id)")
              }
            }
          }
        }
        if viewModel.hasMore {
          loadMoreSentinel(viewModel: viewModel)
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Post-load anchor: only rendered once groups resolve non-empty, so
    // ScreenshotTourTests can wait on it instead of sleeping.
    .accessibilityIdentifier("results.list")
  }

  /// Bottom-of-list affordance that pages in the next window when scrolled
  /// into view. The `isLoadingMore` guard inside `loadMore()` makes a repeated
  /// `onAppear` (e.g. from a group reorder) a no-op.
  ///
  /// Internal (not private) so the timeline rendering in `ResultsView+Timeline`
  /// can reuse it — both the grouped list and the timeline share this sentinel.
  func loadMoreSentinel(viewModel: ResultsViewModel) -> some View {
    // Fixed height keeps the sentinel materializable (so `onAppear` fires) and
    // gives a stable hit area; the spinner shows only while a fetch is actually
    // in flight rather than spinning idly whenever more pages remain.
    HStack {
      Spacer()
      if viewModel.isLoadingMore {
        ProgressView()
      }
      Spacer()
    }
    .frame(height: 44)
    .accessibilityIdentifier("results.loadMore")
    .onAppear {
      Task { await viewModel.loadMore() }
    }
  }

  /// Wraps ``simulationRow`` with a trailing chevron + full-row hit target,
  /// restoring the disclosure affordance the `List` `NavigationLink` row
  /// supplied before the ScrollView conversion.
  private func resultRow(_ row: ResultsViewModel.SimulationRow) -> some View {
    HStack(spacing: 10) {
      simulationRow(row)
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  // Each row stacks: line 1 = the simulation-time `variantName` (`.headline`,
  // the variant's un-translated name or the deleted-scenario snapshot) with the
  // result status pill trailing (#747); then a sheep avatar per agent (clamped);
  // the scenario's 1-line description (#747); and a relative timestamp (#712) at
  // the bottom. The result rides line 1 (next to the name) rather than between
  // the scenario-info rows, so the scenario context (sheep · description) stays
  // one visually-grouped block beneath the title.
  // Internal (not private) so `ResultsView+Timeline` reuses the exact row
  // content — the timeline changes only the section chrome, not the row body.
  func simulationRow(_ row: ResultsViewModel.SimulationRow) -> some View {
    let item = row.item
    let sheepCount = ResultsRowFormat.rowSheepCount(agentCount: row.agentCount)
    // Resolved in the View (not the VM) so all display formatting stays in the
    // Views layer — the VM carries only the resolved agentCount / totalRounds.
    let pill = ResultsRowFormat.resultPill(
      status: item.simulationStatus, topScores: item.topScores,
      currentRound: item.currentRound, totalRounds: row.totalRounds)
    // Gallery category caption (#748), resolved in the View from the run's
    // snapshot raw value. nil for local / pre-v10 runs ⇒ the line is omitted.
    let categoryCaption = ResultsRowFormat.categoryCaption(for: row.category)
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(row.variantName)
          .font(.headline)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
          .truncationMode(.tail)
          // Greedy so the name takes the row and yields (truncates) to the pill
          // when both are long — the result stays readable (favoured over name).
          .frame(maxWidth: .infinity, alignment: .leading)
        resultPill(pill)
      }
      // Gallery category caption (#748) — a small scenario-type label under the
      // title, part of the scenario-context block (category · sheep ·
      // description) beneath the name+result header. Omitted (nil) for local /
      // pre-v10 runs.
      if let categoryCaption {
        Text(categoryCaption)
          .font(.caption)
          .foregroundStyle(Color.muted)
      }
      // Sheep avatars only — the timestamp moved to the bottom line. Guard the
      // whole row so an unknown agent count (sheepCount 0) leaves no empty gap.
      if sheepCount > 0 {
        sheepCluster(count: sheepCount, agentCount: row.agentCount)
      }

      // The scenario's 1-line description (#747). Resolved snapshot-first by the
      // VM; absent (deleted / pre-v7 / empty) → no line, like the rest of the
      // row's graceful degrade. Font / color / truncation mirror the shared
      // `ScenarioSummaryRow` description line, but lineLimit is a deliberate
      // hard 1 here (vs the shared row's Dynamic-Type-aware limit) to keep the
      // results row compact — do not "restore" parity. Not String(localized:)-
      // wrapped: dynamic scenario content, not UI chrome. `description` is
      // already empty-normalized to nil by the resolver; the `!isEmpty` re-guard
      // is harmless defense-in-depth for parity with `ScenarioSummaryRow`.
      if let description = row.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      // Relative timestamp (X / Instagram-style), at the bottom. Computed in the
      // View off the live clock — formatting stays in the Views layer.
      Text(
        ResultsRowFormat.relativeTimestamp(
          for: item.createdAt, now: Date(), calendar: .current)
      )
      .font(.caption)
      .foregroundStyle(Color.muted)
    }
    // Fill the row width so every row's title/meta left-aligns at the same x.
    // Without this the VStack sizes to its content and the enclosing
    // `resultRow` HStack (no Spacer) centers the group, so each row's left edge
    // drifts with its content width. The chevron then rides the trailing edge.
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The trailing result status pill (#747) — one capsule for every run state,
  /// replacing the former result-summary text + `statusBadge` fallback. The
  /// label comes from ``ResultsRowFormat/resultPill(status:topScores:currentRound:totalRounds:)``;
  /// the tint is mapped here (App keeps the color choice in the Views layer, as
  /// the old `statusBadge` did). Tokens are §1-palette-compliant (moss / neutral
  /// / muted) — no saturated status colors.
  private func resultPill(_ pill: ResultPill) -> some View {
    Text(pill.label)
      .font(.caption)
      .fontWeight(.semibold)
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(pillForeground(pill.style))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(pillBackground(pill.style), in: Capsule())
      .layoutPriority(1)
  }

  // Internal (not private) so the timeline node reuses the pill tint as its
  // dot color (single source — see `ResultsView+Timeline.timelineRow`).
  func pillForeground(_ style: ResultPill.Style) -> Color {
    switch style {
    case .completed: Color.mossInk
    case .paused: Color.inkSecondary
    case .pending: Color.muted
    }
  }

  private func pillBackground(_ style: ResultPill.Style) -> Color {
    switch style {
    case .completed: Color.moss.opacity(0.16)
    case .paused: Color.inkSecondary.opacity(0.12)
    case .pending: Color.muted.opacity(0.14)
    }
  }

  /// One sheep avatar per agent (clamped via ``ResultsRowFormat/rowSheepCount``).
  /// The sheep are decorative (``SheepAvatar`` is `.accessibilityHidden`); the
  /// true agent count is announced to VoiceOver via the group's `%lld agents`
  /// label so the visual clamp never hides it (mirrors ``HomeScenarioMetaLine``).
  private func sheepCluster(count: Int, agentCount: Int?) -> some View {
    HStack(spacing: 2) {
      ForEach(0..<count, id: \.self) { index in
        SheepAvatar(character: .forAgent("", position: index), size: SheepAvatar.rowSize)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(format: String(localized: "%lld agents"), agentCount ?? 0))
  }
}

/// Attaches the scenario-name `.searchable` field, but only for the aggregate
/// History-tab root — a pushed per-scenario detail already scopes to a single
/// scenario, so filtering there is meaningless. `enabled` is derived from a
/// `let` scope, so the branch is constant per instance (no view-identity churn,
/// same rationale as ``PushBackChrome``).
private struct AggregateSearchable: ViewModifier {
  let enabled: Bool
  @Binding var text: String

  func body(content: Content) -> some View {
    if enabled {
      content.searchable(
        text: $text,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: Text(String(localized: "Filter by scenario name")))
    } else {
      content
    }
  }
}

/// Applies the root-stack push chrome — custom back button, hidden system
/// back, preserved swipe-back gesture — only when ``ResultsView`` is a
/// pushed detail (``ResultsScope/scenario(_:)``, entered from a scenario's
/// detail screen).
///
/// As the History tab root (``ResultsScope/aggregate``) the view sits at the
/// bottom of its tab's `NavigationStack`, so there is nothing to pop to; a
/// `PasturaBackButton` there would be a dead chevron whose `router.pop()`
/// fires on an empty path (ADR-016 D4). The three push modifiers are applied
/// as one unit per the load-bearing pairing in `.claude/rules/navigation.md`.
/// `scope` is a `let`, so `isPushed` is constant per instance — the branch
/// never toggles at runtime, so this adds no view-identity churn.
private struct PushBackChrome: ViewModifier {
  let isPushed: Bool

  func body(content: Content) -> some View {
    if isPushed {
      content
        .navigationBarBackButtonHidden(true)
        .preservesPasturaSwipeBackGesture()
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            PasturaBackButton()
          }
          .hidingPasturaSharedBackground()
        }
    } else {
      content
    }
  }
}
