import SwiftUI

/// Displays scenario metadata, personas, phases, and a contextual bottom
/// action bar (Run / Edit·Template / Delete) that replaces the tab bar.
struct ScenarioDetailView: View {
  let scenarioId: String
  /// Render-time hint for the navigation title — supplied by callers
  /// that already have the scenario name in memory (e.g., HomeView's
  /// list rows, GalleryScenarioDetailView post-install) so the title
  /// is correct from the first frame of the push, before the view
  /// model finishes loading. `nil` falls back to the empty-string
  /// placeholder. See ADR-008.
  var initialName: String?

  @Environment(AppDependencies.self) private var dependencies
  @Environment(\.dismiss) private var dismiss
  // Not `private`: the sibling-file `+Sections.swift` extension reads it for
  // the language-toggle `replaceTop` (private is file-scoped). The bottom
  // action bar navigates via its own `NavigationLink`s, so it doesn't need
  // this router.
  @Environment(AppRouter.self) var router
  @State private var viewModel: ScenarioDetailViewModel?
  @State private var showDeleteConfirm = false
  /// Drives the scenario-level share sheet (link + X post + copy) from the
  /// toolbar. Distinct from the per-utterance card share on Results/Simulation.
  @State private var scenarioShareContext: ScenarioShareContext?

  /// Drives the content scroll position so a cross-language swap can reset
  /// to the top edge (see `scenarioContent`'s `.onChange`).
  @State private var scrollPosition = ScrollPosition()

  var body: some View {
    Group {
      if let viewModel {
        if viewModel.isLoading {
          ProgressView(String(localized: "Loading..."))
        } else if let scenario = viewModel.scenario {
          scenarioContent(scenario: scenario, viewModel: viewModel)
        } else if let error = viewModel.errorMessage {
          ContentUnavailableView(
            String(localized: "Error"),
            systemImage: "exclamationmark.triangle",
            description: Text(error)
          )
        }
      } else {
        ProgressView()
      }
    }
    // 3-tier fallback (ADR-008): loaded scenario name (authoritative,
    // wins after VM load completes) → push-time `initialName` hint
    // (covers the ~30–80ms load window when callers supplied it) →
    // empty string (defensive default for callers that didn't supply
    // a hint; "Scenario" would be a misleading flash).
    .navigationTitle(viewModel?.scenario?.name ?? initialName ?? "")
    .navigationBarTitleDisplayMode(.large)
    // Hide the system back button to escape iOS 26's Liquid Glass capsule
    // styling on the chevron. `.navigationBarBackButtonHidden` ALSO
    // disables the `interactivePopGestureRecognizer` on iOS 26 (verified
    // by `BackGestureTests` — see PasturaBackButton's UIKit bridge for
    // why), so we pair it with `.preservesPasturaSwipeBackGesture()`
    // which mounts an invisible probe to reinstall the gesture.
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    // Replace the tab bar with a contextual bottom action bar
    // (`scenarioContent`'s `.safeAreaInset` → `ScenarioDetailActionBar`):
    // tab-bar-style Run / Edit·Template / Delete with iOS 26 Liquid Glass, so
    // the tab bar reads as "changing" into these actions. Tab-switching to
    // other sections isn't a real use case from a scenario detail. Precedent
    // for the hide: SimulationView focus mode (ADR-017), different rationale
    // (ADR-016 § contextual action bar). (A native `.bottomBar` renders
    // icon-only on iOS 26 with no icon-over-label form — hence the custom bar.)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
      // Scenario-level share (link) — only once the scenario has loaded, so the
      // link/name are available. The per-utterance card share lives elsewhere.
      if let scenario = viewModel?.scenario {
        ToolbarItem(placement: .primaryAction) {
          Button {
            scenarioShareContext = ScenarioShareContext(
              scenarioName: scenario.name,
              link: LocalizedPublicPages.sharedScenario(id: scenario.id))
          } label: {
            Label(String(localized: "Share Scenario"), systemImage: "square.and.arrow.up")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(PasturaToolbarButtonStyle(variant: .secondary))
          .accessibilityIdentifier("scenarioDetail.shareButton")
        }
        .hidingPasturaSharedBackground()
      }
    }
    .scenarioShareSheet(context: $scenarioShareContext)
    // `.alert` (not `.confirmationDialog`): iOS 26 renders a body-attached
    // confirmationDialog as a popover whose arrow anchors to the body
    // centre, not the triggering control. A centred alert avoids that.
    // Alerts don't auto-add a Cancel button, so it's added explicitly.
    .alert(
      String(localized: "Delete Scenario?"),
      isPresented: $showDeleteConfirm
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        Task {
          if let viewModel, await viewModel.deleteScenario() {
            dismiss()
          }
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
    // Keyed on `scenarioId` so the cross-language toggle reloads: tapping
    // "View in English/Japanese" calls `AppRouter.replaceTop`, which swaps
    // the top route in place — NavigationStack reuses this leaf by stack
    // position, so a plain `.task` (load-once) would keep the prior
    // language. `.task(id:)` re-fires when `scenarioId` changes; on first
    // appear it also runs once. Building the new VM fully before assigning
    // keeps the sections from popping in piecemeal — the gallery banner,
    // the cross-language affordance, and the scenario content stabilise
    // together (the old VM stays shown during the brief reload, no
    // ProgressView flash).
    .task(id: scenarioId) {
      let newViewModel = ScenarioDetailViewModel(
        repository: dependencies.scenarioRepository)
      await newViewModel.load(scenarioId: scenarioId)
      await newViewModel.refreshGalleryStatus(using: dependencies.galleryService)
      await newViewModel.loadSibling()
      viewModel = newViewModel
    }
  }

  private func scenarioContent(
    scenario: Scenario,
    viewModel: ScenarioDetailViewModel
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        galleryBannerSection(viewModel: viewModel)
        summaryStrip(scenario: scenario, viewModel: viewModel)
        contextSection(scenario: scenario)
        personasSection(scenario: scenario)
        phasesSection(scenario: scenario)
        validationSection(viewModel: viewModel)
        actionsSection(scenario: scenario, viewModel: viewModel)
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Post-load anchor: this ScrollView only exists once the scenario
    // content has resolved, so ScreenshotTourTests / NavigationRegressionTests
    // can wait on it instead of sleeping. MUST come before `.safeAreaInset`:
    // applied after, its identifier scopes the inset's Run button too and
    // overrides the button's own `scenarioDetail.runSimulationButton` id
    // (id-scope trap, swiftui-traps.md).
    .accessibilityIdentifier("scenarioDetail.list")
    // Contextual bottom action bar (replaces the tab bar — see `body`).
    .safeAreaInset(edge: .bottom) {
      ScenarioDetailActionBar(
        scenarioId: scenarioId,
        scenarioName: scenario.name,
        canRun: viewModel.canRun,
        record: viewModel.record,
        isGallerySourced: viewModel.isGallerySourced,
        onDelete: { showDeleteConfirm = true })
    }
    .scrollPosition($scrollPosition)
    // A cross-language toggle reuses this leaf (replaceTop swaps the top
    // route in place), so the ScrollView keeps its prior offset — which
    // would leave the new variant's large title above the fold. Reset to
    // the top *edge* (offset 0) so the swapped-in scenario reads from its
    // title and the `.large` nav title re-expands. `scrollTo(edge:)` lands
    // at true offset 0 — unlike `ScrollViewReader.scrollTo(_:anchor:.top)`,
    // which aligns the first item one title-height below 0 and collapses
    // the large title to inline (#830).
    .onChange(of: scenarioId) {
      scrollPosition.scrollTo(edge: .top)
    }
  }

}
