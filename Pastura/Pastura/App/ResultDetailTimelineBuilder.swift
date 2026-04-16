import Foundation

/// Builds the merge-sorted display timeline shown in `ResultDetailView`.
///
/// Combines `TurnRecord` (agent outputs) and `CodePhaseEventRecord`
/// (deterministic phase results: elimination / scoreUpdate / summary /
/// voteResults / pairingResult / assignment) into a single chronological
/// stream keyed by `sequenceNumber`, then inserts `roundSeparator` items
/// at every round boundary.
///
/// **Ordering rationale**: items are sorted strictly by `sequenceNumber`
/// across all phaseTypes within a round — chronological order, NOT the
/// phaseType-grouped layout used by `ResultMarkdownExporter` (which renders
/// `#### Phase: <type>` blocks). The view should read like a replay of
/// "what happened next"; the exporter is a structured document.
///
/// **Decoding**: `CodePhaseEventPayload` is decoded once here so the view
/// can switch on a typed value rather than re-parse JSON on every body
/// re-render. Malformed payloads fall back to `.summary("(unreadable
/// payload)")` (mirrors the defensive handling in
/// `ResultMarkdownExporter`).
nonisolated enum ResultDetailTimelineBuilder {
  enum Item: Identifiable, Sendable, Equatable {
    case roundSeparator(round: Int)
    case turn(TurnRecord)
    case codePhase(CodePhaseEventRecord, CodePhaseEventPayload)

    var id: String {
      switch self {
      case .roundSeparator(let round): "sep-\(round)"
      case .turn(let record): record.id
      case .codePhase(let record, _): record.id
      }
    }

    fileprivate var sequenceNumber: Int {
      switch self {
      case .roundSeparator: Int.min
      case .turn(let r): r.sequenceNumber
      case .codePhase(let r, _): r.sequenceNumber
      }
    }

    fileprivate var roundNumber: Int {
      switch self {
      case .roundSeparator(let r): r
      case .turn(let t): t.roundNumber
      case .codePhase(let r, _): r.roundNumber
      }
    }
  }

  static func build(
    turns: [TurnRecord], events: [CodePhaseEventRecord]
  ) -> [Item] {
    let codeItems: [Item] = events.map { record in
      let payload = decodePayload(record) ?? .summary(text: "(unreadable payload)")
      return .codePhase(record, payload)
    }
    let turnItems: [Item] = turns.map { .turn($0) }

    // Both repositories already order by `(sequenceNumber asc, createdAt asc)`,
    // and Swift's sort is stable — sorting on `sequenceNumber` alone preserves
    // any tiebreaker order the caller passed in.
    let merged = (turnItems + codeItems).sorted { $0.sequenceNumber < $1.sequenceNumber }

    // Round 0 sentinel matches the previous `ResultDetailView.displayItems`
    // behavior: rounds start at 1 in practice, so 0 means "haven't seen one yet".
    var result: [Item] = []
    var lastRound = 0
    for item in merged {
      let round = item.roundNumber
      if round != lastRound {
        lastRound = round
        result.append(.roundSeparator(round: round))
      }
      result.append(item)
    }
    return result
  }

  private static func decodePayload(
    _ record: CodePhaseEventRecord
  ) -> CodePhaseEventPayload? {
    guard let data = record.payloadJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CodePhaseEventPayload.self, from: data)
  }
}
