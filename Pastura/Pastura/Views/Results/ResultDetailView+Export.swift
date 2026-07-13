import SwiftUI
import UIKit

// Export flows split out of ResultDetailView (file_length ceiling). These are
// called from the actions Menu in the main file's `body`, so they are internal
// (not `private`) — sibling-file extensions can't see `private` members.
extension ResultDetailView {

  func triggerExport() async {
    guard let simulation, let scenario else { return }
    isExporting = true
    defer { isExporting = false }

    let env = ResultMarkdownExporter.ExportEnvironment(
      deviceModel: UIDevice.current.model,
      osVersion: ResultMarkdownExporter.ExportEnvironment.normalizeOSVersion(
        ProcessInfo.processInfo.operatingSystemVersionString))
    let exporter = ResultMarkdownExporter(
      contentFilter: contentFilter,
      environment: env)
    let state = decodeState(from: simulation) ?? SimulationState()
    let input = ResultDetailExportAssembler.assemble(
      simulation: simulation, scenario: scenario,
      turns: turns, events: events, state: state)

    do {
      let result = try exporter.export(input)
      self.exportPayload = result
    } catch {
      self.exportError = error.localizedDescription
    }
  }

  /// Runs the demo-replay YAML exporter and hands the result to a
  /// separate Share Sheet. Parallel to ``triggerExport`` (Markdown)
  /// but emits `docs/specs/demo-replay-spec.md` §3.2 schema for
  /// curator ingestion into `Resources/DemoReplays/`.
  func triggerYAMLExport() async {
    guard let simulation, let scenario else { return }
    isExportingYAML = true
    defer { isExportingYAML = false }

    let exporter = YAMLReplayExporter(contentFilter: contentFilter)
    let input = YAMLReplayExporter.Input(
      simulation: simulation, scenario: scenario,
      turns: turns, codePhaseEvents: events)

    do {
      let result = try exporter.export(input)
      self.yamlExportPayload = result
    } catch {
      self.yamlExportError = error.localizedDescription
    }
  }
}
