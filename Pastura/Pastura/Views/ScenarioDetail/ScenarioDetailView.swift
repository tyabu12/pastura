import SwiftUI

/// Displays scenario metadata, personas, phases, and a launch button.
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
  // Programmatic push for the overflow-menu Edit / Use-as-Template actions:
  // a `NavigationLink` inside a `Menu` does not reliably push, so these go
  // through the current tab's router (navigation.md § "When to use what").
  @Environment(AppRouter.self) private var router
  @State private var viewModel: ScenarioDetailViewModel?
  @State private var showDeleteConfirm = false

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
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
      // Low-frequency scenario-management actions (edit / clone / delete)
      // live in a `⋯` overflow menu rather than a pinned top-right slot —
      // the prime real estate is reserved for the primary Run CTA (now a
      // bottom-pinned button). Mirrors `ResultDetailView`'s ellipsis idiom.
      if let record = viewModel?.record {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            // Read-only sources (preset / installed gallery copy) get a
            // clone-as-template action; user scenarios get direct edit.
            if record.isPreset || (viewModel?.isGallerySourced ?? false) {
              Button {
                router.push(.editor(templateYAML: record.yamlDefinition))
              } label: {
                Label(String(localized: "Use as Template"), systemImage: "doc.on.doc")
              }
            } else {
              Button {
                router.push(.editor(editingId: scenarioId))
              } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
              }
            }
            // Delete is gated EXACTLY as the prior toolbar button (`!isPreset`),
            // so an installed gallery copy (`isPreset == false`) stays deletable
            // — gallery read-only blocks edit/overwrite, not deleting the copy.
            if !record.isPreset {
              Button(role: .destructive) {
                showDeleteConfirm = true
              } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityIdentifier("scenarioDetail.actionsMenu")
        }
        .hidingPasturaSharedBackground()
      }
    }
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
    .task {
      // Defer assignment until `load()`, `refreshGalleryStatus()`, and
      // `loadSibling()` all complete so the rendered sections don't
      // pop in piecemeal — the gallery banner, the cross-language
      // affordance, and the scenario content stabilise together.
      // Guard prevents re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
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
        overviewSection(scenario: scenario, viewModel: viewModel)
        contextSection(scenario: scenario)
        personasSection(scenario: scenario)
        phasesSection(scenario: scenario)
        validationSection(viewModel: viewModel)
        actionsSection(scenario: scenario, viewModel: viewModel)
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Primary CTA pinned to the bottom safe-area edge so the app's core
    // action stays in the thumb zone regardless of scroll position; content
    // scrolls under the band. The tab bar sits below this (focus mode hides
    // the tab bar only during a run, ADR-017 — not here).
    .safeAreaInset(edge: .bottom) {
      runSimulationCTA(scenario: scenario, viewModel: viewModel)
    }
    // Post-load anchor: this ScrollView only exists once the scenario
    // content has resolved, so ScreenshotTourTests / NavigationRegressionTests
    // can wait on it instead of sleeping.
    .accessibilityIdentifier("scenarioDetail.list")
  }

  /// Bottom-pinned primary call-to-action. Uses `PasturaPrimaryButtonStyle`
  /// (mossDark fill, WCAG-AA, no capsule / scale animation — design-system
  /// §1 static voice). Stays a `NavigationLink` pushing onto the current
  /// tab's stack (no `navigationDestination(item:)` — navigation.md).
  private func runSimulationCTA(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    // initialName supplies the scenario name to SimulationView's
    // navigationTitle from the first frame, before loadAndRun() re-parses
    // the YAML. Identity-neutral via RouteHint (ADR-008).
    NavigationLink(
      value: Route.simulation(
        scenarioId: scenarioId,
        initialName: .init(scenario.name)
      )
    ) {
      Label(String(localized: "Run Simulation"), systemImage: "play.fill")
    }
    .buttonStyle(PasturaPrimaryButtonStyle())
    .frame(maxWidth: .infinity)
    .disabled(!viewModel.canRun)
    .opacity(viewModel.canRun ? 1 : 0.4)
    .accessibilityIdentifier("scenarioDetail.runSimulationButton")
    .padding(.horizontal, PasturaCardMetrics.interCardSpacing)
    .padding(.vertical, 12)
    // Opaque band + top hairline so scroll content reads as passing *under*
    // a distinct footer, not blending into the last card. If device QA shows
    // a colour seam against the tab bar, bleed the band background down with
    // `.ignoresSafeArea(.container, edges: .bottom)` (background only).
    .background(alignment: .top) {
      Color.screenBackground
        .overlay(alignment: .top) { Color.rule.frame(height: 0.5) }
    }
  }
}
