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
    switch status {
    case .matched, .unknownModel, .unsupportedDevice:
      EmptyView()
    case .switchAvailable(let isLocked):
      Section {
        mismatchBanner
        switchButton(isLocked: isLocked)
      } footer: {
        if isLocked {
          // Gallery-specific single-sentence variant of the Settings copy.
          // The Settings version's second sentence ("Downloads and deletes
          // of other models remain available.") is contextual to the
          // Settings → Models section UX and dangles in gallery context.
          Text(
            String(localized: "Finish the current simulation before switching models."))
        }
      }
    case .downloadAvailable(let otherDownloadInFlight):
      Section {
        mismatchBanner
        downloadButton(disabled: otherDownloadInFlight)
      }
    case .downloading:
      Section {
        mismatchBanner
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

  fileprivate var mismatchBanner: some View {
    let recommendedDisplay =
      ModelRegistry.lookup(id: scenario.recommendedModel)?.displayName
      ?? scenario.recommendedModel
    let activeDisplay =
      ModelRegistry.lookup(id: modelManager.activeModelID)?.displayName
      ?? modelManager.activeModelID
    return Label {
      Text(
        String(
          localized:
            "Will run on \(activeDisplay), not the recommended \(recommendedDisplay)")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    } icon: {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(Color.warning)
    }
  }

  fileprivate func switchButton(isLocked: Bool) -> some View {
    Button {
      modelManager.setActiveModel(scenario.recommendedModel)
    } label: {
      Text(String(localized: "Switch to recommended model"))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .disabled(isLocked)
    .accessibilityIdentifier("galleryDetail.switchModelButton")
  }

  fileprivate func downloadButton(disabled: Bool) -> some View {
    Button {
      // Guarded by `.downloadAvailable` status, which is only emitted
      // when `ModelRegistry.lookup` resolves — so the lookup here is a
      // defensive no-op on unreachable paths, not a user-visible branch.
      guard let descriptor = ModelRegistry.lookup(id: scenario.recommendedModel) else {
        return
      }
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
