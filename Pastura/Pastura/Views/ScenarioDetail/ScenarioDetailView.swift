import SwiftUI

/// Displays scenario metadata, personas, phases, and a launch button.
struct ScenarioDetailView: View {
  let scenarioId: String

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
    .navigationTitle(viewModel?.scenario?.name ?? "Scenario")
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
      let vm = ScenarioDetailViewModel(repository: dependencies.scenarioRepository)
      viewModel = vm
      await vm.load(scenarioId: scenarioId)
    }
  }

  private func scenarioContent(
    scenario: Scenario,
    viewModel: ScenarioDetailViewModel
  ) -> some View {
    List {
      // Overview
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

      // Context
      Section("Context") {
        Text(scenario.context)
          .font(.subheadline)
      }

      // Personas
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

      // Phases
      Section("Phases (\(scenario.phases.count))") {
        ForEach(Array(scenario.phases.enumerated()), id: \.offset) { index, phase in
          HStack {
            Text("\(index + 1).")
              .foregroundStyle(.secondary)
              .monospacedDigit()
            Text(phase.type.rawValue)
              .font(.subheadline.monospaced())
            if phase.type.requiresLLM {
              Image(systemName: "brain")
                .font(.caption)
                .foregroundStyle(.purple)
            }
          }
        }
      }

      // Validation
      if let error = viewModel.validationError {
        Section {
          Label(error, systemImage: "xmark.circle.fill")
            .foregroundStyle(.red)
        }
      }

      // Actions
      Section {
        NavigationLink(value: Route.simulation(scenarioId: scenarioId)) {
          Label("Run Simulation", systemImage: "play.fill")
        }
        .disabled(!viewModel.canRun)

        NavigationLink(value: Route.results(scenarioId: scenarioId)) {
          Label("Past Results", systemImage: "clock.arrow.circlepath")
        }
      }
    }
  }
}
