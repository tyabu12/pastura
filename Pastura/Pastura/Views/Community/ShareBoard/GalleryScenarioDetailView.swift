import SwiftUI

/// Detail view for a single gallery scenario. Renders the scenario metadata
/// and the primary action button (`Try` / `Update` / `Open` depending on
/// local install state).
struct GalleryScenarioDetailView: View {
  let scenario: GalleryScenario

  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: ShareBoardViewModel?
  @State private var isWorking = false
  @State private var outcomeAlert: OutcomeAlert?
  @State private var installedToken: InstalledToken?

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(scenario.title)
    .task {
      let newViewModel = ShareBoardViewModel(
        galleryService: dependencies.galleryService,
        repository: dependencies.scenarioRepository)
      viewModel = newViewModel
      await newViewModel.load()
    }
    .alert(item: $outcomeAlert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .navigationDestination(item: $installedToken) { token in
      ScenarioDetailView(scenarioId: token.id)
    }
  }

  // MARK: - Content

  @ViewBuilder
  private func content(viewModel: ShareBoardViewModel) -> some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(scenario.title).font(.title2.bold())
          Text(scenario.description)
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
      Section("Details") {
        LabeledContent("Category", value: scenario.category.displayName)
        LabeledContent("Author", value: scenario.author)
        LabeledContent("Recommended model", value: scenario.recommendedModel)
        LabeledContent("Est. inferences", value: "\(scenario.estimatedInferences)")
        LabeledContent("Added", value: scenario.addedAt)
      }
      Section {
        actionButton(viewModel: viewModel)
      } footer: {
        Text(
          "Gallery scenarios are read-only — "
            + "local edits are not permitted. Updates replace the stored YAML.")
      }
    }
  }

  private func actionButton(viewModel: ShareBoardViewModel) -> some View {
    let installed = viewModel.isInstalled(scenario)
    let hasUpdate = viewModel.hasUpdate(for: scenario)
    let title: String
    if !installed {
      title = "Try this scenario"
    } else if hasUpdate {
      title = "Update"
    } else {
      title = "Open local copy"
    }

    return Button {
      Task { await tap(viewModel: viewModel, installed: installed, hasUpdate: hasUpdate) }
    } label: {
      HStack {
        if isWorking { ProgressView() }
        Text(title)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .disabled(isWorking)
  }

  // MARK: - Actions

  private func tap(
    viewModel: ShareBoardViewModel, installed: Bool, hasUpdate: Bool
  ) async {
    if installed && !hasUpdate {
      // Already up to date — just navigate to the stored copy.
      installedToken = InstalledToken(id: scenario.id)
      return
    }
    isWorking = true
    defer { isWorking = false }
    let outcome = await viewModel.tryInstall(scenario)
    handle(outcome)
  }

  private func handle(_ outcome: ShareBoardViewModel.TryOutcome) {
    switch outcome {
    case .installed(let id), .updated(let id):
      installedToken = InstalledToken(id: id)
    case .conflict(let existingName, _):
      outcomeAlert = OutcomeAlert(
        title: "Cannot install",
        message:
          "A scenario named “\(existingName)” already uses this id. "
          + "Delete or rename it first, then try again.")
    case .hashMismatch:
      outcomeAlert = OutcomeAlert(
        title: "Integrity check failed",
        message:
          "The downloaded scenario does not match its expected signature. "
          + "The gallery may have been updated. Pull to refresh and try again.")
    case .networkError(let description):
      outcomeAlert = OutcomeAlert(title: "Download failed", message: description)
    }
  }
}

// MARK: - Navigation helpers

/// Wraps a scenario id so it can drive `navigationDestination(item:)`
/// without a retroactive `Identifiable` conformance on `String`.
private struct InstalledToken: Identifiable, Hashable {
  let id: String
}

private struct OutcomeAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
