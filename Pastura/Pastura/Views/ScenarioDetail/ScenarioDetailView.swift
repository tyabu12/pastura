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
      if let record = viewModel?.record, !record.isPreset {
        ToolbarItem(placement: .destructiveAction) {
          Button(String(localized: "Delete"), role: .destructive) {
            showDeleteConfirm = true
          }
          .buttonStyle(PasturaToolbarButtonStyle(variant: .destructive))
        }
        .hidingPasturaSharedBackground()
      }
    }
    .confirmationDialog(
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
    // Post-load anchor: this ScrollView only exists once the scenario
    // content has resolved, so ScreenshotTourTests / NavigationRegressionTests
    // can wait on it instead of sleeping.
    .accessibilityIdentifier("scenarioDetail.list")
  }
}
