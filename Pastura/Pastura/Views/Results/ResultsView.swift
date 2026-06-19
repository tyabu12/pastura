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
          PasturaSection(section.title) {
            VStack(spacing: 0) {
              ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { PasturaRowDivider() }
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

  // Each row shows the simulation-time `variantName` (`.headline` font,
  // matching HomeView preset list role-weight) — the variant's un-translated
  // name (or the captured snapshot for a deleted scenario), kept consistent
  // with the run's recorded conversation content. Row body unchanged in P5;
  // the archetype-safe result summary + sheep avatars land in the follow-up.
  private func simulationRow(_ row: ResultsViewModel.SimulationRow) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.variantName)
        .font(.headline)
        .foregroundStyle(Color.ink)
      HStack {
        Text(row.item.createdAt, style: .date)
        Text(row.item.createdAt, style: .time)
        Spacer()
        statusBadge(row.item.simulationStatus)
      }
      .font(.subheadline)
      .foregroundStyle(Color.inkSecondary)

      // Top-3 score chips come pre-projected from the repository — the heavy
      // `stateJSON` is never decoded in the list (#586).
      if !row.item.topScores.isEmpty {
        HStack(spacing: 8) {
          ForEach(row.item.topScores, id: \.name) { score in
            Text(String(format: String(localized: "%@ (%lld)"), score.name, score.value))
              .textStyle(Typography.metaValue)
              .foregroundStyle(Color.muted)
          }
        }
      }
    }
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
