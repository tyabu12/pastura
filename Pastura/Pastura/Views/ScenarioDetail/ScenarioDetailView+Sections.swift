import SwiftUI

// Section builders for ScenarioDetailView, split into a sibling-file
// extension to keep the main view under SwiftLint type_body_length.
extension ScenarioDetailView {
  // MARK: - Section scaffolding

  func infoRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(Color.ink)
      Spacer(minLength: 8)
      Text(value).foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 14)
  }

  // MARK: - Sections

  @ViewBuilder
  func galleryBannerSection(viewModel: ScenarioDetailViewModel) -> some View {
    if viewModel.hasGalleryUpdate, let entry = viewModel.galleryScenario {
      PasturaSection {
        NavigationLink(value: Route.galleryScenarioDetail(scenario: entry)) {
          PasturaRowLabel(
            title: String(localized: "Update available from Shared Scenarios"),
            systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.plain)
      }
    } else if viewModel.isGallerySourced {
      PasturaSection {
        HStack(spacing: 10) {
          Image(systemName: "square.and.arrow.down.fill")
            .foregroundStyle(Color.moss)
          Text(String(localized: "From Shared Scenarios (read-only)"))
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
      }
    }
  }

  func overviewSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    PasturaSection(String(localized: "Overview")) {
      VStack(spacing: 0) {
        infoRow(String(localized: "Agents"), value: "\(scenario.agentCount)")
        PasturaRowDivider()
        infoRow(String(localized: "Rounds"), value: "\(scenario.rounds)")
        PasturaRowDivider()
        infoRow(
          String(localized: "Est. Inferences"),
          value: "\(viewModel.estimatedInferences)")
        if !scenario.description.isEmpty {
          PasturaRowDivider()
          Text(scenario.description)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
        }
      }
    }
  }

  func contextSection(scenario: Scenario) -> some View {
    PasturaSection(String(localized: "Context")) {
      Text(scenario.context)
        .font(.subheadline)
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }
  }

  func personasSection(scenario: Scenario) -> some View {
    PasturaSection(String(localized: "Personas (\(scenario.personas.count))")) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.personas.enumerated()), id: \.element.name) { index, persona in
          if index > 0 { PasturaRowDivider() }
          VStack(alignment: .leading, spacing: 4) {
            Text(persona.name)
              .font(.headline)
              .foregroundStyle(Color.ink)
            Text(persona.description)
              .font(.caption)
              .foregroundStyle(Color.inkSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 17)
          .padding(.vertical, 12)
        }
      }
    }
  }

  func phasesSection(scenario: Scenario) -> some View {
    PasturaSection(String(localized: "Phases (\(scenario.phases.count))")) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.phases.enumerated()), id: \.offset) { index, phase in
          if index > 0 { PasturaRowDivider() }
          HStack {
            Text("\(index + 1).")
              .foregroundStyle(Color.muted)
              .monospacedDigit()
            Text(phase.type.rawValue)
              .font(.subheadline.monospaced())
              .foregroundStyle(Color.ink)
            if phase.type.requiresLLM {
              // `info` here is a quiet category badge for LLM-required phases, not a
              // notification — see design-system §2.6 for the alert-family scope.
              Image(systemName: "brain")
                .font(.caption)
                .foregroundStyle(Color.info)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 17)
          .padding(.vertical, 13)
        }
      }
    }
  }

  @ViewBuilder
  func validationSection(viewModel: ScenarioDetailViewModel) -> some View {
    if let error = viewModel.validationError {
      PasturaSection {
        HStack(spacing: 8) {
          Image(systemName: "xmark.circle.fill")
          Text(error)
          Spacer(minLength: 0)
        }
        .foregroundStyle(Color.dangerInk)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
      }
    }
  }

  func actionsSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    PasturaSection {
      VStack(spacing: 0) {
        // initialName supplies the scenario name to SimulationView's
        // navigationTitle from the first frame, before loadAndRun()
        // re-parses the YAML. Identity-neutral via RouteHint (ADR-008).
        NavigationLink(
          value: Route.simulation(
            scenarioId: scenarioId,
            initialName: .init(scenario.name)
          )
        ) {
          PasturaRowLabel(
            title: String(localized: "Run Simulation"), systemImage: "play.fill")
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canRun)
        .opacity(viewModel.canRun ? 1 : 0.4)
        .accessibilityIdentifier("scenarioDetail.runSimulationButton")

        PasturaRowDivider()
        NavigationLink(value: Route.results(scenarioId: scenarioId)) {
          PasturaRowLabel(
            title: String(localized: "Past Results"),
            systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(.plain)

        siblingLanguageLink(scenario: scenario, viewModel: viewModel)

        if let record = viewModel.record {
          PasturaRowDivider()
          if record.isPreset || viewModel.isGallerySourced {
            // Preset and gallery rows are read-only; offer a clone-as-template
            // action instead of direct edit so users can customize safely.
            NavigationLink(value: Route.editor(templateYAML: record.yamlDefinition)) {
              PasturaRowLabel(
                title: String(localized: "Use as Template"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
          } else {
            NavigationLink(value: Route.editor(editingId: scenarioId)) {
              PasturaRowLabel(title: String(localized: "Edit"), systemImage: "pencil")
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  /// Cross-language affordance per ADR-010 D6 — surfaces the sibling
  /// variant when one exists (Step D ships sibling pairs for the 4
  /// bundled presets). Hidden when no sibling is loaded.
  ///
  /// Label is the *destination* language name, resolved in the UI
  /// locale: "View in English" / "View in Japanese". Step D only
  /// ships ja↔en pairs — when a future language ships, the
  /// `default` arm becomes a generic fallback.
  @ViewBuilder
  func siblingLanguageLink(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    if let sibling = viewModel.siblingVariant {
      let label: String =
        scenario.language == "ja"
        ? String(localized: "View in English")
        : String(localized: "View in Japanese")
      PasturaRowDivider()
      NavigationLink(
        value: Route.scenarioDetail(
          scenarioId: sibling.id,
          initialName: .init(sibling.name)
        )
      ) {
        PasturaRowLabel(title: label, systemImage: "globe")
      }
      .buttonStyle(.plain)
    }
  }
}
