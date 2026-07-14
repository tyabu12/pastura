import Foundation

/// A single automatic share-highlight candidate surfaced at simulation end
/// (#1070 Stage 2): one notable agent utterance the viewer can turn into a
/// share card with a tap.
///
/// Carries the resolved `TurnOutput` (already `ContentFilter`-applied at the
/// VM boundary) plus its `phaseType` so the end-of-run section can both show
/// a preview excerpt and hand the same `(agent, output, phaseType)` triple to
/// the existing Stage-1 `shareHighlight` path — no re-derivation. `id` is the
/// source `LogEntry` id, so the section's `ForEach` / de-dup stays stable
/// across re-projection.
struct HighlightCandidate: Identifiable, Equatable, Sendable {
  let id: UUID
  let agent: String
  let output: TurnOutput
  let phaseType: PhaseType
  let reason: HighlightReason

  /// The quotable statement shown as the row's excerpt — the same primary
  /// text `shareHighlight` puts on the card. Non-optional: the VM only builds
  /// a candidate when this is non-empty (dead-tap guard), so the row and the
  /// card can never disagree on shareability.
  var previewText: String {
    output.primaryText(for: phaseType) ?? ""
  }
}
