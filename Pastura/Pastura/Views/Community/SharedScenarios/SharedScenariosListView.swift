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
        recommendedHeader
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
      PasturaSection {
        Text(emptyResultsMessage(viewModel: viewModel))
          .foregroundStyle(Color.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 17)
          .padding(.vertical, 14)
      }
    } else {
      let scenarios = viewModel.visibleScenarios
      PasturaSection {
        VStack(spacing: 0) {
          ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
            if index > 0 { PasturaRowDivider() }
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

  /// Horizontal, scrollable category-filter chip row (ADR-016 P4). Replaces
  /// the menu `Picker`: every category is one tap inline, matching the D3
  /// Browse mock. Drives the existing `selectedCategory` binding (nil =
  /// "All"); `visibleScenarios` still owns the actual filtering.
  private func categoryChips(selection: Binding<GalleryCategory?>) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(GalleryCategoryFilter.options, id: \.self) { option in
          categoryChip(option, selection: selection)
        }
      }
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    }
  }

  private func categoryChip(
    _ option: GalleryCategoryFilter, selection: Binding<GalleryCategory?>
  ) -> some View {
    let isSelected = option.selectedCategory == selection.wrappedValue
    return Button {
      selection.wrappedValue = option.selectedCategory
    } label: {
      Text(chipTitle(option))
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        // Selected uses `mossDark`, not base `moss`: white-on-mossDark clears
        // WCAG AA (≈4.76:1) whereas white-on-moss is only ≈3.0:1
        // (PasturaPrimaryButtonStyle §2.3). White-on-accent is the
        // contrast-passing pair, distinct from §1's avoid-white-surfaces rule.
        .foregroundStyle(isSelected ? Color.white : Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected ? Color.mossDark : Color.bubbleBackground, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Color.clear : Color.rule,
            lineWidth: PasturaCardMetrics.borderWidth))
    }
    .buttonStyle(.plain)
    // The menu Picker announced its selection for free; rebuild that on the
    // hand-rolled chips so VoiceOver still reads which filter is active.
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private func chipTitle(_ option: GalleryCategoryFilter) -> String {
    switch option {
    case .all: return String(localized: "All")
    case .category(let category): return category.displayName
    }
  }

  /// "Recommended" section header above the scenarios card (D3 Browse mock),
  /// styled like a ``PasturaSection`` header (muted subheadline).
  private var recommendedHeader: some View {
    Text(String(localized: "Recommended Scenarios"))
      .font(.subheadline)
      .foregroundStyle(Color.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
      .accessibilityAddTraits(.isHeader)
  }

  private func scenarioRow(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(scenario.title).font(.headline).foregroundStyle(Color.ink)
        Spacer()
        if viewModel.hasUpdate(for: scenario) {
          badge(text: String(localized: "Update"), style: .tint)
        } else if viewModel.isInstalled(scenario) {
          badge(text: String(localized: "Installed"), style: .secondary)
        }
      }
      // sheep ×N · N rounds — reuses the Home/Past Results meta line
      // (HomeScenarioMetaLine). Guarded so a feed entry without
      // agent_count/rounds (older feed, forward-compat) hides the line
      // rather than reserving empty space.
      if HomeScenarioRowFormat.showsMetaLine(
        agentCount: scenario.agentCount, rounds: scenario.rounds) {
        HomeScenarioMetaLine(agentCount: scenario.agentCount, rounds: scenario.rounds)
      }
      Text(scenario.description)
        .font(.subheadline)
        .foregroundStyle(Color.inkSecondary)
        .lineLimit(2)
      HStack(spacing: 8) {
        Text(scenario.category.displayName)
        Text(verbatim: "·")
        Text(
          String(format: String(localized: "~%lld inferences"), scenario.estimatedInferences))
      }
      .font(.caption)
      .foregroundStyle(Color.muted)
    }
  }

  private enum BadgeStyle { case tint, secondary }

  private func badge(text: String, style: BadgeStyle) -> some View {
    Text(text)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        style == .tint
          ? Color.accentColor.opacity(0.2)
          : Color.secondary.opacity(0.15),
        in: Capsule()
      )
      .foregroundStyle(style == .tint ? Color.accentColor : .secondary)
  }
}

extension GalleryCategory {
  /// Human-readable display name for the UI picker.
  public var displayName: String {
    switch self {
    case .socialPsychology: return String(localized: "Social Psychology")
    case .gameTheory: return String(localized: "Game Theory")
    case .ethics: return String(localized: "Ethics")
    case .roleplay: return String(localized: "Roleplay")
    case .creative: return String(localized: "Creative")
    case .experimental: return String(localized: "Experimental")
    }
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
