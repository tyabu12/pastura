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
        } else {
          resultsList(viewModel: viewModel)
        }
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Past Results"))
    // Inline title to match the other tab roots (design-system § 5.11);
    // "Past Results" is a generic label, so inline is consistent for the
    // History-tab-root and the pushed-detail variant alike.
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

  /// Centered "N records" count under the screen title (観察履歴 → "12 回の記録",
  /// P5 mock). Full-width so it centers within the card column.
  private func recordCountSubtitle(_ count: Int) -> some View {
    Text(String(format: String(localized: "%lld records"), count))
      .textStyle(Typography.metaValue)
      .foregroundStyle(Color.muted)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
      .accessibilityIdentifier("results.recordCount")
  }

  private func resultsList(viewModel: ResultsViewModel) -> some View {
    ScrollView {
      // LazyVStack so off-screen rows don't decode/materialize eagerly and the
      // bottom load-more sentinel only fires once scrolled into view (#586).
      LazyVStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        // Screen-title subtitle "N records" — aggregate root only (a pushed
        // per-scenario detail shows one scenario, so a global count is
        // meaningless there). Sits above the first date section (P5 mock).
        if !scope.isPushedDetail {
          recordCountSubtitle(viewModel.totalRunCount)
        }
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
  private func loadMoreSentinel(viewModel: ResultsViewModel) -> some View {
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

  // Each row stacks: the simulation-time `variantName` (`.headline`, the
  // variant's un-translated name or the deleted-scenario snapshot); a sheep
  // avatar per agent (clamped); the archetype-safe result summary (P5 PR2,
  // replacing the raw score chips); and a relative timestamp (#712) at the
  // bottom, left-aligned.
  private func simulationRow(_ row: ResultsViewModel.SimulationRow) -> some View {
    let item = row.item
    let sheepCount = ResultsRowFormat.rowSheepCount(agentCount: row.agentCount)
    // Resolved in the View (not the VM) so all display formatting stays in the
    // Views layer — the VM carries only the resolved agentCount / totalRounds.
    let summary = ResultsRowFormat.resultSummary(
      status: item.simulationStatus, topScores: item.topScores,
      currentRound: item.currentRound, totalRounds: row.totalRounds)
    return VStack(alignment: .leading, spacing: 4) {
      Text(row.variantName)
        .font(.headline)
        .foregroundStyle(Color.ink)
      // Sheep avatars only — the timestamp moved to the bottom line. Guard the
      // whole row so an unknown agent count (sheepCount 0) leaves no empty gap.
      if sheepCount > 0 {
        sheepCluster(count: sheepCount, agentCount: row.agentCount)
      }

      // The scenario's 1-line description (#747) — the only scenario-context
      // field on this otherwise result-centric row. Resolved snapshot-first by
      // the VM; absent (deleted / pre-v7 / empty) → no line, like the rest of
      // the row's graceful degrade. Styling mirrors the shared `ScenarioSummaryRow`
      // description line; not String(localized:)-wrapped — it is dynamic scenario
      // content, not UI chrome. `description` is already empty-normalized to nil
      // by the resolver; the `!isEmpty` re-guard mirrors `ScenarioSummaryRow`.
      if let description = row.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      // The archetype-safe result summary — or, when no summary applies
      // (running / failed / cancelled), the status badge as a fallback so the
      // run's state is never silent.
      if let summary {
        Text(summary)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.muted)
      } else {
        statusBadge(item.simulationStatus)
      }

      // Relative timestamp (X / Instagram-style), below the summary/status.
      // Computed in the View off the live clock — formatting stays in the Views
      // layer, like the summary above.
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

  @ViewBuilder
  private func statusBadge(_ status: SimulationStatus?) -> some View {
    // Pastura tokens (§2.3): completed = moss-dark（ステータスラベル用途、§2.3
    // で "ステータスラベル（Completed 等）" と enumerate）、paused / default
    // は ink-secondary / muted の neutral。`.green / .orange / .secondary`
    // は §1 飽和色禁則・パレット非準拠で置換。SimulationView ヘッダーの
    // Completed ラベルとも揃えてある。
    //
    // Label font も同時に `Typography.metaLabel` 化（隣接トークンの一貫性
    // — `.caption` だけ残ると section 内で system font / Pastura token が
    // 混在するため）。
    //
    // Structured as individual cases (not a 3-tuple) to stay within
    // SwiftLint's `large_tuple` limit of 2 members.
    switch status {
    case .completed:
      Label(String(localized: "Completed"), systemImage: "checkmark.circle.fill")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.mossDark)
    case .paused:
      Label(String(localized: "Paused"), systemImage: "pause.circle.fill")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.inkSecondary)
    case .running:
      Label(String(localized: "Running"), systemImage: "play.circle.fill")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.inkSecondary)
    case .failed:
      Label(String(localized: "Failed"), systemImage: "exclamationmark.circle.fill")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.muted)
    case .cancelled:
      Label(String(localized: "Cancelled"), systemImage: "xmark.circle.fill")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.muted)
    case .none:
      Label(String(localized: "Unknown"), systemImage: "questionmark.circle")
        .textStyle(Typography.metaLabel).foregroundStyle(Color.muted)
    }
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
