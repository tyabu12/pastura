import SwiftUI

/// Lists past simulation runs, grouped by scenario.
struct ResultsView: View {
  let scope: ResultsScope

  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: ResultsViewModel?
  /// Gates the reappear refresh so it doesn't double-load on first
  /// appearance: `.onAppear` fires before `.task`, so until `.task` has
  /// created the view model and finished the first load this stays
  /// `false` and `onAppear` is a no-op.
  @State private var didInitialLoad = false

  var body: some View {
    Group {
      if let viewModel {
        if viewModel.isLoading {
          ProgressView(String(localized: "Loading..."))
        } else if viewModel.groups.isEmpty {
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
    // ResultDetailView pops back) so the deleted run drops out. Silent
    // (`showLoading: false`) to avoid a spinner flash on every back-nav.
    // NOTE: the aggregate path (`.aggregate`) re-runs the unpaginated
    // N+1 aggregation each time — acceptable at current scale; pagination
    // is deferred (#545 stretch item / ADR-015 §4).
    .onAppear {
      guard didInitialLoad, let viewModel else { return }
      Task { await viewModel.load(scope: scope, showLoading: false) }
    }
  }

  private func resultsList(viewModel: ResultsViewModel) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        ForEach(viewModel.groups) { group in
          PasturaSection(group.sectionName) {
            VStack(spacing: 0) {
              ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { PasturaRowDivider() }
                NavigationLink(value: Route.resultDetail(simulationId: row.record.id)) {
                  resultRow(row, viewModel: viewModel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("results.row.\(row.record.id)")
              }
            }
          }
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Post-load anchor: only rendered once groups resolve non-empty, so
    // ScreenshotTourTests can wait on it instead of sleeping.
    .accessibilityIdentifier("results.list")
  }

  /// Wraps ``simulationRow`` with a trailing chevron + full-row hit target,
  /// restoring the disclosure affordance the `List` `NavigationLink` row
  /// supplied before the ScrollView conversion.
  private func resultRow(
    _ row: ResultsViewModel.SimulationRow,
    viewModel: ResultsViewModel
  ) -> some View {
    HStack(spacing: 10) {
      simulationRow(row, viewModel: viewModel)
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  // Each row repeats the simulation-time `variantName` (`.headline` font,
  // matching HomeView preset list role-weight) so the row's identity is
  // the variant's un-translated name even when Home aggregation surfaces
  // a sibling-language section header. Detail rows show the same name as
  // their section by design — keeping the row shape identical across
  // entry-points (#392).
  private func simulationRow(
    _ row: ResultsViewModel.SimulationRow,
    viewModel: ResultsViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.variantName)
        .font(.headline)
        .foregroundStyle(Color.ink)
      HStack {
        Text(row.record.createdAt, style: .date)
        Text(row.record.createdAt, style: .time)
        Spacer()
        statusBadge(row.record.simulationStatus)
      }
      .font(.subheadline)
      .foregroundStyle(Color.inkSecondary)

      if let state = viewModel.decodeState(from: row.record) {
        let top3 = state.scores.sorted(by: { $0.value > $1.value }).prefix(3)
        HStack(spacing: 8) {
          ForEach(Array(top3), id: \.key) { name, score in
            Text(String(format: String(localized: "%@ (%lld)"), name, score))
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
