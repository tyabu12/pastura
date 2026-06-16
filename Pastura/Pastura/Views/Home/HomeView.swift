import SwiftUI

/// The main screen displaying all scenarios grouped by presets and user-created.
struct HomeView: View {
  @Environment(AppDependencies.self) private var dependencies
  @Environment(AppRouter.self) private var router
  // Drives the row description's line limit: 1 truncated line at normal
  // sizes (d3), unlimited wrap at accessibility sizes (HomeScenarioRowFormat).
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: HomeViewModel?
  @State private var pendingDeletion: PendingScenarioDeletion?

  /// A user-scenario deletion awaiting confirmation. Carries the target ids
  /// (an `.onDelete` swipe is normally one, but multi-select can batch) and
  /// the first scenario's name for the confirmation copy.
  private struct PendingScenarioDeletion: Identifiable {
    let ids: [String]
    let name: String
    var id: String { ids.joined(separator: ",") }
  }

  /// Confirmation copy for deleting a user scenario. Since v7 the scenario
  /// FK is `ON DELETE SET NULL`, so past runs are orphaned (kept), not
  /// cascade-deleted — the copy reassures the user their history survives.
  nonisolated static func scenarioDeletionMessage(name: String) -> String {
    String(
      format: String(
        localized: "“%@” will be deleted. Past simulation results are kept and stay viewable."),
      name)
  }

  var body: some View {
    // The Home tab's `NavigationStack` (and its `.navigationDestination`
    // registration via ``RouteResolver``) is owned by ``RootTabView`` so
    // every tab shares one Route universe (ADR-016 D3). This view is the
    // Home tab's root *content*; `router` (read below) is the Home tab's
    // `AppRouter`, injected per-tab by `RootTabView`.
    Group {
      if let viewModel {
        scenarioList(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // `.navigationTitle("Pastura")` is kept deliberately even though the
    // visible center is replaced by the `.principal` brand lockup below.
    // The nav bar's accessibility identity (`navigationBars["Pastura"]`,
    // asserted by NavigationRegression / EditorReload / BackGesture UI
    // tests) derives from the title string, and design-system § 5.11's
    // tab-root inline-title convention is satisfied by it. A `.principal`
    // item replaces the title *visual* without clearing the underlying
    // `UINavigationItem.title`, so both stay true at once.
    .navigationTitle("Pastura")
    .navigationBarTitleDisplayMode(.inline)
    // Hide the bar's backing material so the brand lockup reads against the
    // cream screen background (d3 design). This removes the bar material but
    // NOT the iOS 26 per-item Liquid Glass capsule — that needs the separate
    // `.hidingPasturaSharedBackground()` on each ToolbarItem below.
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        HStack(spacing: 9) {
          Image("BrandIcon")
            .resizable()
            .frame(width: 27, height: 27)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          // verbatim: "Pastura" is a brand name, never localized — keeps it
          // out of Localizable.xcstrings and past the i18n SwiftLint tripwire.
          Text(verbatim: "Pastura")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.brandWordmark")
      }
      .hidingPasturaSharedBackground()
    }
    .task {
      // Defer assignment until both `loadScenarios()` and
      // `refreshGalleryUpdateBadges()` complete so gallery update badges
      // appear together with the row that owns them — otherwise the list
      // shows first and badges pop in a frame later. Guard prevents
      // re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
      let newViewModel = HomeViewModel(
        repository: dependencies.scenarioRepository,
        simulationRepository: dependencies.simulationRepository)
      await newViewModel.loadScenarios()
      await newViewModel.refreshGalleryUpdateBadges(using: dependencies.galleryService)
      viewModel = newViewModel
    }
    // Refresh the list whenever the user navigates back to root.
    // `.task` only runs on initial mount; pushed views like the editor
    // don't re-trigger it on dismiss. D5.3: `router` is the Home tab's
    // `AppRouter` (per-tab injected), so this pop-reload stays Home-local.
    .onChange(of: router.path.count) { oldCount, newCount in
      if newCount < oldCount {
        Task {
          await viewModel?.loadScenarios()
          await viewModel?.refreshGalleryUpdateBadges(using: dependencies.galleryService)
        }
      }
    }
  }

  @ViewBuilder
  private func scenarioList(viewModel: HomeViewModel) -> some View {
    List {
      // The paused "resume" card sits above the scenario list (d3), shown
      // only when a paused run exists (d3-without otherwise).
      if let paused = viewModel.pausedSummary {
        pausedSection(paused)
      }
      scenariosSection(viewModel: viewModel)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    // `.alert`, not `.confirmationDialog`: on iOS 26 confirmationDialog
    // renders as a mis-anchored popover on iPhone (reference: iOS 26
    // confirmationDialog popover anchor). `.alert` supplies no implicit
    // Cancel, so `deleteConfirmationActions` carries an explicit one.
    .alert(
      String(localized: "Delete Scenario?"),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { presented in if !presented { pendingDeletion = nil } }),
      presenting: pendingDeletion
    ) { pending in
      deleteConfirmationActions(pending, viewModel: viewModel)
    } message: { pending in
      Text(Self.scenarioDeletionMessage(name: pending.name))
    }
    .refreshable {
      await viewModel.loadScenarios()
      await viewModel.refreshGalleryUpdateBadges(using: dependencies.galleryService)
    }
    .overlay {
      if let error = viewModel.errorMessage {
        ContentUnavailableView(
          String(localized: "Error"),
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      }
    }
  }

  /// Header for the unified scenario list — the "Scenarios" label plus the
  /// trailing "+" that opens the editor. The "+" moved here from the nav
  /// toolbar (d3 layout); its `home.newScenarioButton` identifier is
  /// preserved so EditorReloadTests / ScreenshotTourTests still find it.
  private func scenariosSectionHeader() -> some View {
    HStack {
      // textCase(nil) keeps the soft "Scenarios" label (d3) instead of the
      // grouped-list default all-caps.
      Text(String(localized: "Scenarios"))
        .textCase(nil)
      Spacer()
      NavigationLink(value: newScenarioRoute()) {
        Image(systemName: "plus")
          .font(.title3)
          .foregroundStyle(Color.ink)
          .accessibilityHidden(true)
      }
      .accessibilityIdentifier("home.newScenarioButton")
      .accessibilityLabel(String(localized: "New Scenario"))
    }
  }

  @ViewBuilder
  private func deleteConfirmationActions(
    _ pending: PendingScenarioDeletion, viewModel: HomeViewModel
  ) -> some View {
    Button(role: .destructive) {
      Task {
        for id in pending.ids {
          await viewModel.deleteScenario(id)
        }
        pendingDeletion = nil
      }
    } label: {
      Text(String(localized: "Delete"))
    }
    Button(role: .cancel) {
      pendingDeletion = nil
    } label: {
      Text(String(localized: "Cancel"))
    }
  }

  /// The paused "resume" card section (``HomePausedCard``). PasturaCard draws
  /// its own surface, so the row clears the List background and matches the
  /// horizontal margin / spacing used by `pasturaCardRow()`.
  @ViewBuilder
  private func pausedSection(_ summary: PausedScenarioSummary) -> some View {
    Section {
      HomePausedCard(summary: summary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(
          EdgeInsets(
            top: PasturaCardMetrics.interCardSpacing / 2,
            leading: PasturaCardMetrics.horizontalMargin,
            bottom: PasturaCardMetrics.interCardSpacing / 2,
            trailing: PasturaCardMetrics.horizontalMargin))
    } header: {
      Text(String(localized: "Interrupted Scenario"))
        .textCase(nil)
    }
  }

  /// The unified scenario list section — user scenarios first (deletable),
  /// then bundled presets (d3). `.onDelete` attaches to the user `ForEach`
  /// only, so presets stay non-deletable; the empty state shows when both
  /// lists are empty.
  @ViewBuilder
  private func scenariosSection(viewModel: HomeViewModel) -> some View {
    Section {
      if viewModel.presets.isEmpty && viewModel.userScenarios.isEmpty {
        ContentUnavailableView(
          String(localized: "No Scenarios"),
          systemImage: "doc.text",
          description: Text(String(localized: "Tap + to import a YAML scenario"))
        )
      } else {
        ForEach(viewModel.userScenarios, id: \.id) { scenario in
          HomeScenarioRow(
            scenario: scenario,
            metadata: viewModel.rowMetadata[scenario.id],
            hasGalleryUpdate: viewModel.galleryUpdateBadges.contains(scenario.id)
          )
          .pasturaCardRow()
          .accessibilityAction(named: Text(String(localized: "Delete"))) {
            // VoiceOver-reachable equivalent of the swipe-delete: swipe
            // actions aren't reliably surfaced to VoiceOver, so name it
            // explicitly. Opens the same confirmation alert.
            pendingDeletion = PendingScenarioDeletion(
              ids: [scenario.id], name: scenario.name)
          }
        }
        .onDelete { offsets in
          // Confirm before deleting — destructive and not obviously
          // recoverable. Past results survive (orphaned), but the scenario
          // itself is gone. A swipe deletes a single user row, so naming the
          // first scenario in the copy is accurate.
          let scenarios = offsets.map { viewModel.userScenarios[$0] }
          pendingDeletion = PendingScenarioDeletion(
            ids: scenarios.map(\.id),
            name: scenarios.first?.name ?? "")
        }
        ForEach(viewModel.presets, id: \.id) { scenario in
          HomeScenarioRow(scenario: scenario, metadata: viewModel.rowMetadata[scenario.id])
            .pasturaCardRow()
        }
      }
    } header: {
      scenariosSectionHeader()
    }
  }

}

// Toolbar route helper, split into an extension to keep the main
// `HomeView` body under SwiftLint's `type_body_length`. Root-stack route
// resolution itself was hoisted to ``RouteResolver`` (ADR-016 D3) so all
// four tab stacks share one Route universe.
extension HomeView {
  /// Resolves the destination for the toolbar "New Scenario" menu item.
  ///
  /// Under `--ui-test-editor-seed-yaml`, `AppDependencies.uiTestEditorSeedYAML`
  /// carries a pre-verified template so `EditorReloadTests` can exercise
  /// the editor → save → Home reload path without typing YAML through
  /// XCUITest. Production always returns the empty editor.
  func newScenarioRoute() -> Route {
    #if DEBUG
      if let seed = dependencies.uiTestEditorSeedYAML {
        return .editor(templateYAML: seed)
      }
    #endif
    return .editor()
  }
}

extension View {
  /// Renders a `List` row as a flat ``PasturaCard``: white
  /// ``PasturaCardSurface`` (1pt `rule` border, 14pt radius, no shadow),
  /// inset vertically by half ``PasturaCardMetrics/interCardSpacing`` so
  /// adjacent rows read as separate cards, separators hidden.
  ///
  /// Home stays on `List` (for swipe-`.onDelete`); this is the List-host
  /// counterpart to the `ScrollView` ``PasturaCard`` container used on the
  /// other browse screens, sharing the same metrics so the card form
  /// matches across hosts.
  fileprivate func pasturaCardRow() -> some View {
    self
      .listRowSeparator(.hidden)
      .listRowBackground(
        PasturaCardSurface()
          .padding(.vertical, PasturaCardMetrics.interCardSpacing / 2)
      )
  }
}
