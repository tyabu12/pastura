import SwiftUI

/// Root of the "Browse" (さがす) tab — a curated gallery of scenarios
/// (Shared Scenarios). As a tab root it carries no back chrome; it
/// pushes ``Route/galleryScenarioDetail(scenario:)`` onto its own tab
/// stack (ADR-016 D4).
struct SharedScenariosListView: View {
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: SharedScenariosViewModel?

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Browse Shared Scenarios"))
    // Inline title to match the other tab roots (design-system § 5.11).
    .navigationBarTitleDisplayMode(.inline)
    // Attach `.searchable` at the body boundary (mirroring ResultsView's
    // `AggregateSearchable`), NOT inside `scenarioList`'s ScrollView — so the
    // field is owned by the tab root's NavigationStack bar and is stable
    // across `state` transitions. Gated to the loaded states: searching the
    // loading / network-unavailable / error screens is meaningless.
    .modifier(GallerySearchable(enabled: isSearchEnabled, text: searchQueryBinding))
    .task {
      let newViewModel = SharedScenariosViewModel(
        galleryService: dependencies.galleryService,
        repository: dependencies.scenarioRepository)
      viewModel = newViewModel
      await newViewModel.load()
    }
  }

  /// True only in the states that render a searchable scenario list.
  private var isSearchEnabled: Bool {
    guard let viewModel else { return false }
    switch viewModel.state {
    case .loaded, .offlineWithCache: return true
    case .idle, .loading, .empty, .error: return false
    }
  }

  /// Bridges the `.searchable` field to the optional ViewModel's
  /// `searchQuery` (the VM is created lazily in `.task`).
  private var searchQueryBinding: Binding<String> {
    Binding(
      get: { viewModel?.searchQuery ?? "" },
      set: { viewModel?.searchQuery = $0 })
  }

  @ViewBuilder
  private func content(viewModel: SharedScenariosViewModel) -> some View {
    switch viewModel.state {
    case .idle, .loading:
      loadingView
    case .empty:
      emptyState(viewModel: viewModel)
    case .error(let message):
      errorState(message: message, viewModel: viewModel)
    case .loaded, .offlineWithCache:
      scenarioList(viewModel: viewModel)
    }
  }

  // MARK: - States

  private var loadingView: some View {
    ProgressView(String(localized: "Loading gallery…"))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func emptyState(viewModel: SharedScenariosViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Gallery Unavailable"), systemImage: "wifi.slash")
    } description: {
      Text(
        String(
          localized: "Could not reach Shared Scenarios and no cached content is available."))
    } actions: {
      Button(String(localized: "Retry")) {
        Task { await viewModel.refresh() }
      }
      .buttonStyle(PasturaPrimaryButtonStyle())
    }
  }

  private func errorState(message: String, viewModel: SharedScenariosViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button(String(localized: "Retry")) { Task { await viewModel.refresh() } }
        .buttonStyle(PasturaPrimaryButtonStyle())
    }
  }

  // MARK: - Scenario list

  @ViewBuilder
  private func scenarioList(viewModel: SharedScenariosViewModel) -> some View {
    @Bindable var bindable = viewModel
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        if case .offlineWithCache = viewModel.state {
          offlineBanner
        }
        categoryChips(selection: $bindable.selectedCategory)
        scenariosCard(viewModel: viewModel)
        if let updated = viewModel.updatedAt {
          Text(String(format: String(localized: "Last updated: %@"), updated))
            .font(.caption)
            .foregroundStyle(Color.muted)
            .padding(.leading, PasturaCardMetrics.horizontalMargin + 6)
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    .refreshable {
      await viewModel.refresh()
    }
  }

  @ViewBuilder
  private func scenariosCard(viewModel: SharedScenariosViewModel) -> some View {
    if viewModel.visibleScenarios.isEmpty {
      PasturaSection(style: .grouped) {
        Text(emptyResultsMessage(viewModel: viewModel))
          .foregroundStyle(Color.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 17)
          .padding(.vertical, 14)
      }
    } else {
      let scenarios = viewModel.visibleScenarios
      PasturaSection(style: .grouped) {
        VStack(spacing: 0) {
          ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
            if index > 0 {
              PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
            }
            NavigationLink(value: Route.galleryScenarioDetail(scenario: scenario)) {
              galleryRow(scenario: scenario, viewModel: viewModel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sharedScenarios.galleryCell.\(scenario.id)")
          }
        }
      }
    }
  }

  /// Context-accurate copy for the empty scenarios card — distinguishes
  /// "no search match" (with the query echoed), "category is empty", and
  /// "gallery shipped nothing". The query echo uses the `String(format:)`
  /// form (i18n Form B), never `\(query)` interpolation, which would
  /// silently fall back to English on a ja device (.claude/rules/i18n.md).
  private func emptyResultsMessage(viewModel: SharedScenariosViewModel) -> String {
    switch viewModel.emptyReason {
    case .noMatchingQuery:
      return String(
        format: String(localized: "No scenarios match \"%@\"."), viewModel.searchQuery)
    case .emptyCategory:
      return String(localized: "No scenarios in this category.")
    case .galleryEmpty:
      return String(localized: "No scenarios available yet.")
    }
  }

  private var offlineBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "wifi.exclamationmark")
        .foregroundStyle(Color.warning)
      Text(String(localized: "Offline — showing cached content"))
        .font(.footnote)
        .foregroundStyle(Color.inkSecondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
  }

  /// Wraps ``scenarioRow`` with a trailing chevron + full-row hit target,
  /// restoring the List disclosure affordance after the ScrollView move.
  private func galleryRow(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    HStack(spacing: 10) {
      scenarioRow(scenario: scenario, viewModel: viewModel)
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  // MARK: - Category filter chips
  //
  // `categoryChips` / `categoryChip` / `chipTitle` live in
  // `SharedScenariosListView+CategoryChips.swift` (split out for the
  // type_body_length budget, #731).

  private func scenarioRow(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    // hasUpdate wins over isInstalled — an updatable scenario is installed too,
    // but the "changed" signal is the more useful one to surface.
    let badge: ScenarioBadge? =
      viewModel.hasUpdate(for: scenario)
      ? .update
      : (viewModel.isInstalled(scenario) ? .installed : nil)
    return ScenarioSummaryRow(
      model: ScenarioSummaryRow.Model(
        title: scenario.title,
        badge: badge,
        agentCount: scenario.agentCount,
        rounds: scenario.rounds,
        description: scenario.description,
        descriptionLineLimit: 2,
        captionLeading: scenario.category.displayName,
        captionTrailing: String(
          format: String(localized: "~%lld inferences"), scenario.estimatedInferences)
      )
    )
  }
}

/// Attaches the scenario `.searchable` field to the Browse tab, but only when
/// a list is actually on screen (`enabled`). Mirrors ResultsView's
/// `AggregateSearchable`: applied at the `body` boundary so the field lives on
/// the tab root's NavigationStack bar rather than inside a state-specific
/// subtree, keeping it stable across `LoadState` transitions.
private struct GallerySearchable: ViewModifier {
  let enabled: Bool
  @Binding var text: String

  func body(content: Content) -> some View {
    if enabled {
      // Always-visible field in the nav-bar drawer on all OS. (The さがす
      // tab is a grouped regular tab, not `Tab(role:.search)`, so there is
      // no iOS 26 bar→search morph to feed a default placement.)
      content.searchable(
        text: $text,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: Text(String(localized: "Search scenarios")))
    } else {
      content
    }
  }
}
