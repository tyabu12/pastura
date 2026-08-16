import SwiftUI

/// Recommended-model affordances split out of `GalleryScenarioDetailView`
/// to satisfy SwiftLint's `type_body_length` cap. See
/// `RecommendedModelStatus` for the pure-logic classifier these helpers
/// consume.
extension GalleryScenarioDetailView {
  /// Mismatch banner + optional Switch / Download button. Empty for
  /// `.matched` / `.unknownModel` / `.unsupportedDevice` so the gallery
  /// stays silent when there is no actionable mismatch (forward-compat
  /// for newer-id gallery feeds and 6 GB device suppression).
  @ViewBuilder
  var recommendedModelSection: some View {
    let status = recommendedModelStatus
    // Resolve once, at render time, and hand the same descriptor to the banner
    // and the buttons: the helper reads `state`, so a closure re-resolving at
    // tap time could act on a different build than the status it was rendered
    // from.
    let target = ModelRegistry.recommendationTarget(
      for: scenario.recommendedModel, state: modelManager.state)
    switch status {
    case .matched, .unknownModel, .unsupportedDevice:
      // `EmptyView()` collapses to nothing in the enclosing VStack — no
      // card, no spacing. The consuming site at
      // `GalleryScenarioDetailView.content(viewModel:)` always calls this
      // computed property, so the suppression must be at this layer.
      EmptyView()
    case .switchAvailable(let isLocked):
      PasturaSection {
        VStack(alignment: .leading, spacing: 12) {
          mismatchBanner(target: target)
          switchButton(target: target, isLocked: isLocked)
          if isLocked {
            // Gallery-specific single-sentence variant of the Settings copy.
            // The Settings version's second sentence ("Downloads and deletes
            // of other models remain available.") is contextual to the
            // Settings → Models section UX and dangles in gallery context.
            // `inkSecondary`, not §8's quietude tier — the reason the Switch
            // button is disabled is the only way to learn why it does nothing.
            // Audit class A1: `docs/design/muted-application-audit.md`.
            Text(
              String(localized: "Finish the current simulation before switching models.")
            )
            .font(.footnote)
            .foregroundStyle(Color.inkSecondary)
          }
        }
        .padding(17)
      }
    case .downloadAvailable(let otherDownloadInFlight):
      PasturaSection {
        VStack(alignment: .leading, spacing: 12) {
          mismatchBanner(target: target)
          downloadButton(target: target, disabled: otherDownloadInFlight)
        }
        .padding(17)
      }
    case .downloading:
      PasturaSection {
        mismatchBanner(target: target)
          .padding(17)
      }
    }
  }

  /// Snapshot the inputs into the pure-logic classifier. Re-evaluated on
  /// every render — `ModelManager` is `@Observable`, so its `state` /
  /// `activeModelID` mutations invalidate this view automatically.
  var recommendedModelStatus: RecommendedModelStatus {
    // Sourced via `#if` rather than a hardcoded literal so simulator parity
    // is preserved without `#if`-stripping the affordance section. The
    // pure-logic helper accepts the parameter form so unit tests cover
    // both branches.
    #if targetEnvironment(simulator)
      let isSimulator = true
    #else
      let isSimulator = false
    #endif
    return RecommendedModelStatus.compute(
      recommendedID: scenario.recommendedModel,
      activeID: modelManager.activeModelID,
      state: modelManager.state,
      isSimulationActive: dependencies.simulationActivityRegistry.isActive,
      isSimulator: isSimulator)
  }

  fileprivate func mismatchBanner(target: ModelDescriptor?) -> some View {
    let recommendedDisplay = target?.displayName ?? scenario.recommendedModel
    let activeDisplay =
      ModelRegistry.lookup(id: modelManager.activeModelID)?.displayName
      ?? modelManager.activeModelID
    return Label {
      Text(
        String(
          format: String(
            localized: "Will run on %@, not the recommended %@"),
          activeDisplay, recommendedDisplay)
      )
      .font(.footnote)
      .foregroundStyle(Color.inkSecondary)
    } icon: {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(Color.warning)
    }
  }

  fileprivate func switchButton(target: ModelDescriptor?, isLocked: Bool) -> some View {
    Button {
      // Route through the shared switch entry point so the active-model id
      // and the LLM service stay in lockstep. Calling `setActiveModel` alone
      // (the prior code) updated the id but left the next run on the old
      // service — the #844 latent bug.
      //
      // `target` is the render-time resolution; `.switchAvailable` is only
      // emitted for a downloaded build, so the unwrap is a defensive no-op.
      guard let descriptor = target else { return }
      dependencies.switchActiveModel(to: descriptor, using: modelManager)
    } label: {
      Text(String(localized: "Switch to recommended model"))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .disabled(isLocked)
    .accessibilityIdentifier("galleryDetail.switchModelButton")
  }

  fileprivate func downloadButton(target: ModelDescriptor?, disabled: Bool) -> some View {
    Button {
      // Same render-time `target`. `.downloadAvailable` is only emitted when it
      // resolved, so the unwrap is a defensive no-op on unreachable paths, not
      // a user-visible branch.
      guard let descriptor = target else { return }
      // `startDownload` enforces cellular consent + sequential-DL
      // policy + per-state gating internally via `evaluateStartGates`;
      // do NOT duplicate those checks here.
      modelManager.startDownload(descriptor: descriptor)
    } label: {
      Text(String(localized: "Download recommended model"))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .disabled(disabled || isWorking)
    .accessibilityIdentifier("galleryDetail.downloadRecommendedButton")
  }
}
