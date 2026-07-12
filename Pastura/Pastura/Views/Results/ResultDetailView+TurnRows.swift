import SwiftUI

// Turn-row rendering split out of ResultDetailView (file_length ceiling).
// Members these helpers read are internal on the main struct — `private`
// is invisible to sibling-file extensions.
extension ResultDetailView {

  /// Resolves a tapped agent name to its persona for the detail sheet
  /// (#942). Only reached when ``personas`` is non-empty (``turnRow`` gates
  /// the tap out otherwise); returns `nil` defensively for an unmatched name.
  func personaItem(for agentName: String) -> PersonaSheetItem? {
    guard let persona = personas.first(where: { $0.name == agentName }) else { return nil }
    return PersonaSheetItem(
      persona: persona,
      position: agentOrder.firstIndex(of: agentName))
  }

  @ViewBuilder
  func turnRow(_ turn: TurnRecord) -> some View {
    if let agentName = turn.agentName, let phaseType = PhaseType(rawValue: turn.phaseType) {
      let output = decodeTurnOutput(turn)
      // Quiet Past Results treatment for the #916 badge: the declaration
      // row is decorated, but no reveal line is inserted (mirrors how the
      // prediction badge drops its streak here — the drama beat belongs to
      // the live transcript).
      VStack(alignment: .leading, spacing: 4) {
        AgentOutputRow(
          agent: agentName,
          output: output,
          phaseType: phaseType,
          showAllThoughts: showAllThoughts,
          agentPosition: agentOrder.firstIndex(of: agentName),
          // Gate at the run level, not per-tap: a run whose scenario couldn't
          // be decoded (pre-v7 deleted scenario, YAML drift) has no personas,
          // so the rows stay non-tappable rather than showing a dead affordance.
          onAvatarTap: personas.isEmpty ? nil : { selectedPersona = personaItem(for: $0) },
          onShareHighlight: {
            shareHighlight(agent: agentName, output: output, phaseType: phaseType)
          }
        )
        if contradictionBadgedTurnIDs.contains(turn.id) {
          ContradictionBadge()
            .padding(.leading, ChatBubbleLayout.avatarSize + ChatBubbleLayout.avatarTextGap)
        }
      }
    } else {
      // Pre-#92 fallback: TurnRecord without agentName. Newer code phases
      // emit CodePhaseEventRecord rows instead, so this path is only hit
      // by legacy data.
      HStack(spacing: 4) {
        Text(turn.phaseType)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
        Text(String(format: String(localized: "Round %lld"), turn.roundNumber))
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.inkSecondary)
      }
    }
  }

  func decodeTurnOutput(_ turn: TurnRecord) -> TurnOutput {
    guard let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data)
    else {
      return TurnOutput(fields: ["raw": turn.rawOutput])
    }
    return output
  }

  // Not `private`: read by the `+ResumeBanner.swift` sibling extension (D8
  // resume gate) and `triggerYAMLExport` — cross-file callers can't see
  // `private` members. Co-located with `decodeTurnOutput` as a decode helper.
  func decodeState(from record: SimulationRecord) -> SimulationState? {
    guard let data = record.stateJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SimulationState.self, from: data)
  }
}
