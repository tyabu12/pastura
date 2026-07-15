import SwiftUI

// Variable-insert affordance for the prompt / summarize-template editors:
// the grouped token source (`PlaceholderAvailability`), the pure caret-splice
// helpers (unit-tested without rendering the sheet), the two insert actions,
// and the `VariablePickerSheet` builder. Split out of `PhaseEditorSheet.swift`
// to keep that file under SwiftLint's `file_length` limit.

extension PhaseEditorSheet {

  /// The phase-aware `{token}` groups shown in the variable-insert sheet
  /// (#920 B, ADR-024 D4). Reads the linter-owned ``PlaceholderAvailability``
  /// map: `thisPhase` is the tokens this phase's handler injects
  /// (``PlaceholderAvailability/supplied(for:chooseRoundRobin:)`` — a round-robin
  /// `choose` gains `{opponent_name}`, `vote` gains `{candidates}`), and
  /// `crossPhase` is the cross-phase state any prompt may read
  /// (``PlaceholderAvailability/crossPhaseStateReadable``) minus whatever this
  /// phase already supplies, so a token never appears in both groups. Both are
  /// sorted. `static` so it is unit-testable without rendering the sheet.
  static func promptVariableGroups(
    for phase: EditablePhase
  ) -> (thisPhase: [String], crossPhase: [String]) {
    let supplied = PlaceholderAvailability.supplied(
      for: phase.type, chooseRoundRobin: phase.pairing == .roundRobin)
    let crossPhase = PlaceholderAvailability.crossPhaseStateReadable.subtracting(supplied)
    return (thisPhase: supplied.sorted(), crossPhase: crossPhase.sorted())
  }

  /// Inserts `{token}` into `text` at `range` (the editor's current selection /
  /// caret), replacing any selected text, or appends it when `range` is `nil`
  /// (no known selection). Pure + `static` so it is unit-testable without the
  /// live `TextEditor`. Returns the new text.
  ///
  /// Defensive: also appends when `range` is out of bounds for `text` (a stale
  /// selection whose `String.Index`es point into a since-mutated string), so a
  /// future caller can't trap `replaceSubrange`. `String.Index` comparison is
  /// offset-based and never traps, so the guard itself is safe to evaluate.
  static func inserting(
    token: String, into text: String, at range: Range<String.Index>?
  ) -> String {
    let braced = "{\(token)}"
    guard let range,
      range.lowerBound >= text.startIndex,
      range.upperBound <= text.endIndex
    else { return text + braced }
    var result = text
    result.replaceSubrange(range, with: braced)
    return result
  }

  /// Extracts the single-selection `Range<String.Index>` from a `TextSelection`
  /// (an empty range = caret insertion point). A multi-selection (macOS only)
  /// uses its first range; an absent / unknown selection returns `nil`, so the
  /// caller falls back to append. `static` + pure for unit testing.
  static func selectedRange(from selection: TextSelection?) -> Range<String.Index>? {
    guard let selection else { return nil }
    switch selection.indices {
    case .selection(let range):
      return range
    case .multiSelection(let rangeSet):
      return rangeSet.ranges.first
    @unknown default:
      return nil
    }
  }

  func insertPromptVariable(_ token: String) {
    phase.prompt = Self.inserting(
      token: token, into: phase.prompt, at: Self.selectedRange(from: promptSelection))
    // Drop the stale selection — its String.Index values point into the
    // pre-mutation string and must not be reused against the new text.
    promptSelection = nil
  }

  func insertTemplateVariable(_ token: String) {
    phase.template = Self.inserting(
      token: token, into: phase.template, at: Self.selectedRange(from: templateSelection))
    templateSelection = nil
  }

  /// The variable-insert sheet for the given phase, wired to `insert`. A plain
  /// (non-`@ViewBuilder`) helper so the `let` binding is legal.
  func variablePicker(
    for phase: EditablePhase, insert: @escaping (String) -> Void
  ) -> some View {
    let groups = Self.promptVariableGroups(for: phase)
    return VariablePickerSheet(
      thisPhase: groups.thisPhase, crossPhase: groups.crossPhase, onInsert: insert)
  }
}
