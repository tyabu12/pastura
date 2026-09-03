import SwiftUI

/// Root of the "Browse" (さがす) tab — a curated gallery of scenarios
/// (Shared Scenarios). As a tab root it carries no back chrome; it
/// pushes ``Route/galleryScenarioDetail(scenario:)`` onto its own tab
/// stack (ADR-016 D4).
struct SharedScenariosListView: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(\.openURL) private var openURL
  @State private var viewModel: SharedScenariosViewModel?
  /// The ADR-020 D4 "update required" alert a greyed card presents on tap —
  /// the same `OutcomeAlert` the detail's D5 path builds, so both surfaces
  /// share copy and the App Store deep-link. One binding for every greyed
  /// row; the `.alert` modifier that observes it lives on `body`, not in the
  /// `ForEach` (see there).
  @State private var updateRequiredAlert: OutcomeAlert?

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    // Ground on the container, not the loaded arm — `loadingView` and the
    // `emptyState` (which persists whenever the gallery is unreachable) have to
    // render on it too. Frame first: `.background` sizes to the primary view, so
    // a small-intrinsic arm would otherwise get a patch behind its spinner
    // rather than a screen. ADR-028 § Amendment 2026-08-05 (#1336).
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.screenBackground.ignoresSafeArea())
    .navigationTitle(String(localized: "Browse Shared Scenarios"))
    // Inline title to match the other tab roots (design-system § 5.11).
    .navigationBarTitleDisplayMode(.inline)
    // Attach `.searchable` at the body boundary (mirroring ResultsView's
    // `AggregateSearchable`), NOT inside `scenarioList`'s ScrollView — so the
    // field is owned by the tab root's NavigationStack bar and is stable
    // across `state` transitions. Gated to the loaded states: searching the
    // loading / network-unavailable / error screens is meaningless.
    .modifier(GallerySearchable(enabled: isSearchEnabled, text: searchQueryBinding))
    // Grounded on the container like `.searchable`, NOT inside `galleryCell`:
    // every greyed row shares `updateRequiredAlert`, and N per-row `.alert`
    // modifiers on one non-nil binding is undefined presentation (an
    // arbitrary one wins, or none with an "already presenting" log). Latent
    // with a single incompatible entry, live the first time a floor greys
    // several rows at once.
    .alert(item: $updateRequiredAlert) { alert in alert.makeAlert(openURL: openURL) }
    .task {
      // Re-fires every time this tab root re-appears — measured on iOS 26.5
      // (#1565): pushing the detail route fires the root's onDisappear, and
      // the pop fires onAppear, so `.task` restarts. Rebuilding the VM here
      // swapped the `ScrollView` for `loadingView` (state → `.idle`), which
      // discarded the scroll offset, search text and chip selection and
      // re-fetched the index on every pop. Keep the VM (mirrors
      // `GalleryScenarioDetailView`) and only re-read the installed rows, so
      // an install done on the detail screen still updates its row. One
      // exception: a first `load()` cancelled mid-flight (tab switched while
      // the index was fetching) leaves the VM in `.idle` / `.loading`, whose
      // arm is a bare spinner with no Retry and no pull-to-refresh — so that
      // case must re-run `load()` rather than the cheap re-sync.
      if let viewModel {
        switch viewModel.state {
        case .loaded, .offlineWithCache, .empty:
          await viewModel.refreshInstalledSnapshot()
        case .idle, .loading:
          await viewModel.load()
        }
        return
      }
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
        // Language filter leads the category row, and only once the feed
        // carries ≥2 languages — dormant on today's all-Japanese gallery
        // (ADR-010 Step D surfaces it). Default-filtered to the device
        // language via the ViewModel seed.
        if viewModel.shouldShowLanguageFilter {
          languageChips(
            available: viewModel.availableLanguages,
            selection: $bindable.selectedLanguage)
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
          galleryCell(scenario: scenario, viewModel: viewModel)
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

  /// One catalog cell. A **compatible** scenario is a tappable
  /// ``Route/galleryScenarioDetail(scenario:)`` push; an **engine-incompatible**
  /// one (ADR-020 D4) is a dimmed card that does not navigate — tapping it
  /// presents the `.updateRequired` alert (explanation + "Open App Store",
  /// ADR-020 §12) instead of pushing a detail the user could not install from.
  /// It is a plain `Button` rather than a `.disabled` one so the whole card,
  /// badge included, keeps VoiceOver focus and reads its "update app" state.
  /// Its accessibility identifier carries an `.incompatible` suffix so the UI
  /// tests that tap `sharedScenarios.galleryCell.<id>` expecting a detail push
  /// can never retarget onto a greyed card. No UI test reads the suffixed
  /// identifier yet (the canary fixture is compatible), so a typo in it goes
  /// unnoticed until a greyed-row fixture exists — #1662 is the first.
  @ViewBuilder
  private func galleryCell(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    let compatible = viewModel.isCompatible(scenario)
    let row = GalleryCatalogRow(
      model: catalogModel(scenario: scenario, viewModel: viewModel, compatible: compatible))
    if compatible {
      NavigationLink(value: Route.galleryScenarioDetail(scenario: scenario)) {
        row
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("sharedScenarios.galleryCell.\(scenario.id)")
    } else {
      Button {
        updateRequiredAlert = GalleryScenarioDetailFormat.installAlert(for: .updateRequired)
      } label: {
        row.opacity(GalleryCatalogMetrics.incompatibleCardOpacity)
      }
      .buttonStyle(.plain)
      .accessibilityHint(
        Text(String(localized: "Needs a newer version of Pastura to run. Shows how to update."))
      )
      .accessibilityIdentifier("sharedScenarios.galleryCell.\(scenario.id).incompatible")
    }
  }

  /// Maps a ``GalleryScenario`` into the presentation-only
  /// ``GalleryCatalogRow/Model`` (tab-identity PR2, #777). The category moves
  /// to the card's inline chip and `agent_count · rounds` to its footer; the
  /// `~N inferences` caption from the old shared row is dropped under the
  /// catalog layout (matches the approved lookbook).
  private func catalogModel(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel, compatible: Bool
  ) -> GalleryCatalogRow.Model {
    let badge = GalleryCatalogRowFormat.badge(
      compatible: compatible,
      hasUpdate: viewModel.hasUpdate(for: scenario),
      isInstalled: viewModel.isInstalled(scenario),
      // `Date()` here is the "now" source; the pure recency logic lives in
      // `isNew(addedAt:referenceDate:)`, which the unit tests drive with a
      // fixed reference date.
      isNew: GalleryCatalogRowFormat.isNew(addedAt: scenario.addedAt, referenceDate: Date()))
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
