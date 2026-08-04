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

  /// A user-scenario deletion awaiting confirmation — the target scenario's id
  /// plus its name for the confirmation copy. The context-menu / accessibility
  /// "Delete" affordances each act on a single row.
  private struct PendingScenarioDeletion: Identifiable {
    let id: String
    let name: String
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
    // Frame before the ground: the ground was already on this container, but
    // `.background` sizes to the primary view, so the `ProgressView()` arm was
    // getting a patch behind the spinner while the loaded arm — a greedy
    // `ScrollView` — filled. ADR-028 § Amendment 2026-08-05.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      ToolbarItem(placement: .topBarTrailing) {
        ActiveModelChip()
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
    // Editorial Home layout (tab-identity PR3, 案C 中庸): a moss-gradient
    // resume hero (`HomePausedCard`) over a dense edge-to-edge stack of compact
    // icon rows (`HomeCompactScenarioRow`) — distinct from the catalog cards on
    // Search (`GalleryCatalogRow`) and the timeline on Past Results, which keep
    // the shared `PasturaCard` form. Delete stays a long-press context
    // menu (Apple's documented non-List alternative).
    ScrollView {
      LazyVStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        // The paused "resume" card sits above the scenario list (d3), shown
        // only when a paused run exists (d3-without otherwise).
        if let paused = viewModel.pausedSummary {
          pausedSection(paused)
        }
        if viewModel.presets.isEmpty && viewModel.userScenarios.isEmpty {
          ContentUnavailableView(
            String(localized: "No Scenarios"),
            systemImage: "doc.text",
            description: Text(String(localized: "Tap + to import a YAML scenario"))
          )
          .frame(maxWidth: .infinity)
          .padding(.top, 60)
          // Anchor for the empty-inventory screenshot-tour capture
          // (--ui-test-seed-empty-inventory, #811). The sibling error overlay
          // below (viewModel.errorMessage) is a distinct surface — keep ids apart.
          .accessibilityIdentifier("home.emptyState")
        } else {
          scenariosSection(viewModel: viewModel)
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
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
  /// trailing "+" that opens the editor, styled like a ``PasturaSection``
  /// header (muted subheadline, 6pt inset). Its `home.newScenarioButton`
  /// identifier is preserved so EditorReloadTests / ScreenshotTourTests find it.
  private func scenariosSectionHeader() -> some View {
    HStack {
      Text(String(localized: "Scenarios"))
        .font(.subheadline)
        .foregroundStyle(Color.muted)
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
    // .grouped sections sit edge-to-edge, so the header carries the screen-edge
    // inset itself (the section no longer pads horizontally).
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
  }

  @ViewBuilder
  private func deleteConfirmationActions(
    _ pending: PendingScenarioDeletion, viewModel: HomeViewModel
  ) -> some View {
    Button(role: .destructive) {
      Task {
        await viewModel.deleteScenario(pending.id)
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

  /// The paused "resume" hero section. ``HomePausedCard`` now renders the
  /// moss-gradient hero — eyebrow ("Interrupted Scenario") included — and
  /// carries its own screen-edge margin, so this section is just the hero. The
  /// muted header that used to sit above it moved into the hero's eyebrow.
  @ViewBuilder
  private func pausedSection(_ summary: PausedScenarioSummary) -> some View {
    HomePausedCard(summary: summary)
  }

  /// The editorial compact scenario list (tab-identity PR3) — user scenarios
  /// first (deletable via long-press context menu), then bundled presets, as a
  /// dense edge-to-edge stack of ``HomeCompactScenarioRow`` with full-width
  /// ``PasturaRowDivider`` hairlines between adjacent rows. Lighter than the
  /// catalog cards Search renders (``GalleryCatalogRow``).
  @ViewBuilder
  private func scenariosSection(viewModel: HomeViewModel) -> some View {
    let rows = viewModel.userScenarios + viewModel.presets
    VStack(alignment: .leading, spacing: 7) {
      scenariosSectionHeader()
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, scenario in
          if index > 0 {
            PasturaRowDivider()
          }
          scenarioRow(scenario, viewModel: viewModel)
        }
      }
    }
  }

  /// One compact scenario row. User scenarios (non-preset) carry a destructive
  /// "Delete" in both a long-press context menu and a VoiceOver-reachable
  /// accessibility action (swipe actions aren't reliably surfaced to
  /// VoiceOver); presets are non-deletable, so they get neither.
  @ViewBuilder
  private func scenarioRow(_ scenario: ScenarioRecord, viewModel: HomeViewModel) -> some View {
    let row = HomeCompactScenarioRow(
      scenario: scenario,
      metadata: viewModel.rowMetadata[scenario.id],
      hasGalleryUpdate: !scenario.isPreset && viewModel.galleryUpdateBadges.contains(scenario.id))
    if scenario.isPreset {
      row
    } else {
      row
        .contextMenu {
          Button(role: .destructive) {
            // Confirm before deleting — destructive and not obviously
            // recoverable. Past results survive (orphaned), but the scenario
            // itself is gone.
            pendingDeletion = PendingScenarioDeletion(
              id: scenario.id, name: scenario.name)
          } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
          }
        }
        .accessibilityAction(named: Text(String(localized: "Delete"))) {
          pendingDeletion = PendingScenarioDeletion(
            id: scenario.id, name: scenario.name)
        }
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
