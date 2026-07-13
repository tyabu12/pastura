import Foundation

/// Decodes a persisted ``TurnRecord``'s output back to a display-ready
/// ``TurnOutput``, applying ``ContentFilter`` at read time.
///
/// **Content-safety invariant (ADR-005 §5.1).** `parsedOutputJSON` and
/// `rawOutput` are persisted UNFILTERED — they are structured / literal mirrors
/// of the raw LLM emission (see `TurnRecord.parsedOutputJSON`'s contract note).
/// Every user-visible display surface that reconstructs a turn from persistence
/// (the past-results viewer, the D8 resume-replay log) MUST route through this
/// decoder so the filter is applied on read. Centralising the decode here keeps
/// that invariant single-sourced: a future display surface that decodes
/// `parsedOutputJSON` directly with `JSONDecoder` would re-open the #1075
/// filter-bypass.
///
/// Lives in `App/` because ``ContentFilter`` is an App/-layer type; the two
/// past-results / resume callers are also App/ or Views/. `nonisolated` (like
/// ``ContentFilter``) — a pure decode helper touching only nonisolated types,
/// so nonisolated callers (e.g. tests) reach it without a MainActor hop.
nonisolated enum PersistedTurnDecoder {
  /// Decodes `turn.parsedOutputJSON` to a ``TurnOutput`` and returns it filtered.
  ///
  /// Falls back to a single `raw` field carrying `turn.rawOutput` when the
  /// stored JSON can't be parsed (legacy / malformed payload) so the row still
  /// renders something — and the filter is applied to that fallback too.
  static func decodeFiltered(
    _ turn: TurnRecord,
    contentFilter: ContentFilter
  ) -> TurnOutput {
    let decoded: TurnOutput
    if let data = turn.parsedOutputJSON.data(using: .utf8),
      let output = try? JSONDecoder().decode(TurnOutput.self, from: data) {
      decoded = output
    } else {
      decoded = TurnOutput(fields: ["raw": turn.rawOutput])
    }
    return contentFilter.filter(decoded)
  }
}
