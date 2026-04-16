import Foundation

/// Builds a `ResultMarkdownExporter.Input` from past-results data so the
/// past-results export path matches the live-simulation export path.
///
/// Extracted from `ResultDetailView.triggerExport()` so the assembly is
/// testable without standing up a SwiftUI host. PR #98 added
/// `codePhaseEvents` and `personas` to `ResultMarkdownExporter.Input` but
/// only updated the live-simulation path; this helper closes that gap and
/// guards against the same drift recurring (the test suite would catch
/// future omissions).
///
/// Persona extraction uses `try?` with an empty fallback — mirrors
/// `SimulationViewModel.fetchExportPayload` (`SimulationViewModel.swift:592-597`)
/// so that a stored scenario with broken YAML degrades the Final Scores /
/// Roster Status section instead of failing the whole export.
nonisolated enum ResultDetailExportAssembler {
  static func assemble(
    simulation: SimulationRecord,
    scenario: ScenarioRecord,
    turns: [TurnRecord],
    events: [CodePhaseEventRecord],
    state: SimulationState
  ) -> ResultMarkdownExporter.Input {
    let personas: [String] = {
      guard let parsed = try? ScenarioLoader().load(yaml: scenario.yamlDefinition)
      else { return [] }
      return parsed.personas.map(\.name)
    }()

    return ResultMarkdownExporter.Input(
      simulation: simulation,
      scenario: scenario,
      turns: turns,
      codePhaseEvents: events,
      personas: personas,
      state: state)
  }
}
