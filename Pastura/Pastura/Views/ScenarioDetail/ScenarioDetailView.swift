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
          ProgressView("Loading...")
        } else if let scenario = viewModel.scenario {
          scenarioContent(scenario: scenario, viewModel: viewModel)
        } else if let error = viewModel.errorMessage {
          ContentUnavailableView(
            "Error",
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
    .toolbar {
      if let record = viewModel?.record, !record.isPreset {
        ToolbarItem(placement: .destructiveAction) {
          Button("Delete", role: .destructive) {
            showDeleteConfirm = true
          }
        }
      }
    }
    .confirmationDialog("Delete Scenario?", isPresented: $showDeleteConfirm) {
      Button("Delete", role: .destructive) {
        Task {
          if let viewModel, await viewModel.deleteScenario() {
            dismiss()
          }
        }
      }
    }
    .task {
      // Defer assignment until both `load()` and `refreshGalleryStatus()`
      // complete so the gallery banner never flips from
      // "From Share Board (read-only)" to "Update available" mid-render.
      // Guard prevents re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
      let newViewModel = ScenarioDetailViewModel(
        repository: dependencies.scenarioRepository)
      await newViewModel.load(scenarioId: scenarioId)
      await newViewModel.refreshGalleryStatus(using: dependencies.galleryService)
      viewModel = newViewModel
    }
  }

  private func scenarioContent(
    scenario: Scenario,
    viewModel: ScenarioDetailViewModel
  ) -> some View {
    List {
      galleryBannerSection(viewModel: viewModel)
      overviewSection(scenario: scenario, viewModel: viewModel)
      contextSection(scenario: scenario)
      personasSection(scenario: scenario)
      phasesSection(scenario: scenario)
      validationSection(viewModel: viewModel)
      actionsSection(viewModel: viewModel)
    }
  }

  @ViewBuilder
  private func galleryBannerSection(viewModel: ScenarioDetailViewModel) -> some View {
    if viewModel.hasGalleryUpdate, let entry = viewModel.galleryScenario {
      Section {
        NavigationLink(value: Route.galleryScenarioDetail(scenario: entry)) {
          Label(
            "Update available from Share Board",
            systemImage: "arrow.down.circle.fill"
          )
          .foregroundStyle(.tint)
        }
      }
    } else if viewModel.isGallerySourced {
      Section {
        Label("From Share Board (read-only)", systemImage: "square.and.arrow.down.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func overviewSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    Section("Overview") {
      LabeledContent("Agents", value: "\(scenario.agentCount)")
      LabeledContent("Rounds", value: "\(scenario.rounds)")
      LabeledContent("Est. Inferences", value: "\(viewModel.estimatedInferences)")
      if !scenario.description.isEmpty {
        Text(scenario.description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func contextSection(scenario: Scenario) -> some View {
    Section("Context") {
      Text(scenario.context)
        .font(.subheadline)
    }
  }

  private func personasSection(scenario: Scenario) -> some View {
    Section("Personas (\(scenario.personas.count))") {
      ForEach(scenario.personas, id: \.name) { persona in
        VStack(alignment: .leading, spacing: 4) {
          Text(persona.name)
            .font(.headline)
          Text(persona.description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
      }
    }
  }

  private func phasesSection(scenario: Scenario) -> some View {
    Section("Phases (\(scenario.phases.count))") {
      ForEach(Array(scenario.phases.enumerated()), id: \.offset) { index, phase in
        HStack {
          Text("\(index + 1).")
            .foregroundStyle(.secondary)
            .monospacedDigit()
          Text(phase.type.rawValue)
            .font(.subheadline.monospaced())
          if phase.type.requiresLLM {
            // `info` here is a quiet category badge for LLM-required phases, not a
            // notification — see design-system §2.6 for the alert-family scope.
            Image(systemName: "brain")
              .font(.caption)
              .foregroundStyle(Color.info)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func validationSection(viewModel: ScenarioDetailViewModel) -> some View {
    if let error = viewModel.validationError {
      Section {
        Label(error, systemImage: "xmark.circle.fill")
          .foregroundStyle(Color.dangerInk)
      }
    }
  }

  private func actionsSection(viewModel: ScenarioDetailViewModel) -> some View {
    Section {
      NavigationLink(value: Route.simulation(scenarioId: scenarioId)) {
        Label("Run Simulation", systemImage: "play.fill")
      }
      .disabled(!viewModel.canRun)
      .accessibilityIdentifier("scenarioDetail.runSimulationButton")

      NavigationLink(value: Route.results(scenarioId: scenarioId)) {
        Label("Past Results", systemImage: "clock.arrow.circlepath")
      }

      if let record = viewModel.record {
        if record.isPreset || viewModel.isGallerySourced {
          // Preset and gallery rows are read-only; offer a clone-as-template
          // action instead of direct edit so users can customize safely.
          NavigationLink(
            value: Route.editor(templateYAML: record.yamlDefinition)
          ) {
            Label("Use as Template", systemImage: "doc.on.doc")
          }
        } else {
          NavigationLink(
            value: Route.editor(editingId: scenarioId)
          ) {
            Label("Edit", systemImage: "pencil")
          }
        }
      }
    }
  }
}
