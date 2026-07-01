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
    // The language filter lives in the nav bar (quiet, rarely touched) rather
    // than in a scroll-content chip row. Gated on ≥2 feed languages; the whole
    // toolbar item is absent while the gallery is single-language, so the
    // search drawer keeps the bar to itself.
    .toolbar {
      if let viewModel, viewModel.shouldShowLanguageFilter {
        ToolbarItem(placement: .topBarTrailing) {
          languageMenu(viewModel: viewModel)
        }
        // Opt out of the iOS 26 Liquid Glass toolbar capsule so the chip draws
        // its own soft moss capsule, matching the Home `ActiveModelChip`
        // (swiftui-traps § Liquid Glass toolbar capsule).
        .hidingPasturaSharedBackground()
      }
    }
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
    case .idle, .loading, .empty: return false
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
    // Anchor for the gallery offline / load-failure screenshot-tour capture
    // (--ui-test-seed-gallery-offline → `.empty`, #811).
    .accessibilityIdentifier("sharedScenarios.galleryUnavailable")
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
      // Anchor for the no-search-match (--ui-test-seed-empty-inventory + typed
      // query) and gallery-empty (--ui-test-seed-empty-gallery → .galleryEmpty)
      // screenshot-tour captures (#811). One anchor, two captures — only the
      // emptyResultsMessage copy differs by EmptyReason.
      .accessibilityIdentifier("sharedScenarios.emptyResultsCard")
    } else {
      // Spaced landscape catalog cards (tab-identity PR2, #777) — NOT a divided
      // `.grouped` band — so Browse reads as a card catalog, distinct from the
      // Home compact rows and the Past Results timeline.
      VStack(alignment: .leading, spacing: GalleryCatalogMetrics.listSpacing) {
        ForEach(viewModel.visibleScenarios, id: \.id) { scenario in
          NavigationLink(value: Route.galleryScenarioDetail(scenario: scenario)) {
            GalleryCatalogRow(model: catalogModel(scenario: scenario, viewModel: viewModel))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("sharedScenarios.galleryCell.\(scenario.id)")
        }
      }
      .padding(.horizontal, GalleryCatalogMetrics.listHorizontalMargin)
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
    case .emptyLanguage:
      return String(localized: "No scenarios in this language.")
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

  // MARK: - Category filter chips
  //
  // `categoryChips` / `categoryChip` / `chipTitle` live in
  // `SharedScenariosListView+CategoryChips.swift` (split out for the
  // type_body_length budget, #731).

  /// Maps a ``GalleryScenario`` into the presentation-only
  /// ``GalleryCatalogRow/Model`` (tab-identity PR2, #777). The category moves
  /// to the card's inline chip and `agent_count · rounds` to its footer; the
  /// `~N inferences` caption from the old shared row is dropped under the
  /// catalog layout (matches the approved lookbook).
  private func catalogModel(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> GalleryCatalogRow.Model {
    // hasUpdate wins over isInstalled — an updatable scenario is installed too,
    // but the "changed" signal is the more useful one to surface.
    let badge: ScenarioBadge? =
      viewModel.hasUpdate(for: scenario)
      ? .update
      : (viewModel.isInstalled(scenario) ? .installed : nil)
    return GalleryCatalogRow.Model(
      title: scenario.title,
      badge: badge,
      category: scenario.category.displayName,
      description: scenario.description,
      agentCount: scenario.agentCount,
      rounds: scenario.rounds,
      signature: GalleryCatalogRowFormat.signaturePhase(phases: scenario.phases))
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
