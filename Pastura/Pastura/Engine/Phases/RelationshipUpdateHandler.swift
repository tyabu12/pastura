import Foundation
import os

/// Handles `relationship_update` phases — a zero-inference code phase that
/// deterministically maintains a per-agent affinity matrix and injects a
/// natural-language summary into each agent's prompt (#910).
///
/// Signals are read from state the surrounding phases already populated:
/// - **Votes**: `state.lastOutputs[voter].vote` (who voted for whom). Applied
///   with the `vote_against` delta on the *target's* view of the voter.
/// - **Choose actions**: `state.pairings` (`action1` / `action2`). Applied with
///   the `action_deltas` map on each partner's view of the other.
///
/// **Ordering constraints** (documented, not enforced — a violation is a silent
/// no-op, not an error):
/// - Place this phase *after* the vote / choose phase that produces its signals
///   and *before* `score_calc` — `PrisonersDilemmaLogic` clears `state.pairings`
///   after scoring, so a relationship_update placed after it sees no actions.
/// - A `lastOutputs`-writing LLM phase (speak / vote / choose) between a vote and
///   this phase overwrites `lastOutputs[voter].vote`, losing the vote signal;
///   `reflect` / `whisper` do NOT write `lastOutputs`, so they are safe to
///   interleave. When neither a vote nor a pairing signal is present the handler
///   emits a `.debug` diagnostic so a misordered scenario is discoverable.
///
/// The raw matrix accumulates across rounds in the reserved `relationships_raw_<name>`
/// `state.variables` key (JSON); the prose summary lands in `relationships_<name>`
/// (surfaced to only that agent via `PromptBuilder.injectRelationships`). Eliminated
/// agents are skipped as perceivers — they neither act nor receive an injected summary.
nonisolated struct RelationshipUpdateHandler: PhaseHandler {
  private let logger = Logger(subsystem: "app.pastura.Pastura", category: "RelationshipUpdate")

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let active = context.scenario.personas.filter { state.eliminated[$0.name] != true }
    let activeNames = Set(active.map(\.name))

    // Seed from the accumulated matrix so scores persist across rounds.
    var matrix: [String: [String: Int]] = [:]
    for persona in active {
      let row = decodeRow(state.variables["relationships_raw_\(persona.name)"])
      if !row.isEmpty { matrix[persona.name] = row }
    }

    // Evaluate BOTH before combining — each mutates `matrix` via `inout`, so a
    // short-circuiting `||` would drop the action signal whenever a vote signal
    // is also present (a phase may declare both rules; e.g. choose → vote →
    // relationship_update leaves pairings AND lastOutputs.vote populated).
    let sawVotes = applyVotes(
      context: context, state: state, activeNames: activeNames, into: &matrix)
    let sawActions = applyActions(
      context: context, state: state, activeNames: activeNames, into: &matrix)
    let sawSignal = sawVotes || sawActions

    if !sawSignal {
      // Most likely a placement mistake: this phase ran with no fresh vote /
      // pairing signal in state (e.g. after `score_calc` cleared pairings, or
      // with no preceding vote/choose this round). Not user content.
      logger.debug("relationship_update found no vote/pairing signal — check phase ordering")
    }

    persist(
      active: active, activeNames: activeNames, matrix: matrix,
      language: context.scenario.engineLanguage, state: &state)
    context.emitter(.relationshipUpdate(relationships: matrix))
  }

  /// Applies the `vote_against` delta for every voter→target pair readable from
  /// `lastOutputs`. Returns `true` if any vote input was present.
  private func applyVotes(
    context: PhaseContext, state: SimulationState, activeNames: Set<String>,
    into matrix: inout [String: [String: Int]]
  ) -> Bool {
    var sawVote = false
    for voter in activeNames {
      guard let target = state.lastOutputs[voter]?.vote, !target.isEmpty else { continue }
      sawVote = true
      // Self-votes and hallucinated / eliminated targets carry no affinity.
      guard target != voter, activeNames.contains(target) else { continue }
      if let delta = context.phase.voteAgainst {
        // The target grows wary of whoever voted against them.
        matrix[target, default: [:]][voter, default: 0] += delta
      }
    }
    return sawVote
  }

  /// Applies the `action_deltas` map for every choose pairing. Each partner's
  /// view of the other moves by the delta for the other's action. Returns
  /// `true` if any pairing input was present.
  private func applyActions(
    context: PhaseContext, state: SimulationState, activeNames: Set<String>,
    into matrix: inout [String: [String: Int]]
  ) -> Bool {
    guard !state.pairings.isEmpty else { return false }
    guard let deltas = context.phase.actionDeltas else { return true }
    for pairing in state.pairings {
      guard activeNames.contains(pairing.agent1), activeNames.contains(pairing.agent2) else {
        continue
      }
      if let action = pairing.action2, let delta = deltas[action] {
        matrix[pairing.agent1, default: [:]][pairing.agent2, default: 0] += delta
      }
      if let action = pairing.action1, let delta = deltas[action] {
        matrix[pairing.agent2, default: [:]][pairing.agent1, default: 0] += delta
      }
    }
    return true
  }

  /// Writes each active perceiver's non-empty row back as the accumulated raw
  /// matrix plus its prose summary.
  ///
  /// The raw matrix keeps the full history (cross-round accumulation + the event
  /// payload / Phase-3 viz), but the injected prose mentions only agents still in
  /// play — an eliminated agent should not surface in "you are wary of X".
  private func persist(
    active: [Persona], activeNames: Set<String>, matrix: [String: [String: Int]], language: String,
    state: inout SimulationState
  ) {
    for persona in active {
      guard let row = matrix[persona.name], !row.isEmpty else { continue }
      state.variables["relationships_raw_\(persona.name)"] = encodeRow(row)
      let visibleRow = row.filter { activeNames.contains($0.key) }
      state.variables["relationships_\(persona.name)"] =
        RelationshipVerbalizer.summarize(visibleRow, language: language)
    }
  }

  private func encodeRow(_ row: [String: Int]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(row), let string = String(data: data, encoding: .utf8)
    else { return "{}" }
    return string
  }

  private func decodeRow(_ raw: String?) -> [String: Int] {
    guard let raw, let data = raw.data(using: .utf8),
      let row = try? JSONDecoder().decode([String: Int].self, from: data)
    else { return [:] }
    return row
  }
}
