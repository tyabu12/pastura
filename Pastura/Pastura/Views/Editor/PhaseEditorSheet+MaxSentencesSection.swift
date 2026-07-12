import SwiftUI

// Per-phase `max_sentences` brevity-override UI for `PhaseEditorSheet` (#881
// Stage 2 PR-B). The control is a Toggle ("override the global default") plus a
// conditional Stepper (1…6), shown only for phases that emit an LLM statement.
// Split out from `PhaseEditorSheet.swift` to keep that file under SwiftLint's
// `file_length` limit. Accesses `phase` from the parent struct.
//
// The pure decision helpers below carry the testable logic (ADR-009); the View
// section only wires SwiftUI bindings to them.

extension PhaseEditorSheet {

  // MARK: - Pure decision helpers (unit-tested)

  /// Whether the `max_sentences` control is shown for `type`. Gated to phases
  /// that emit an LLM statement (`requiresLLM`) — the exact set the semantic
  /// linter's R18 `max-sentences-no-op` rule treats as effective — so an author
  /// cannot set a silent no-op override on a code / control phase from the
  /// visual editor.
  static func showsMaxSentencesControl(for type: PhaseType) -> Bool {
    type.requiresLLM
  }

  /// The accepted `max_sentences` range. MUST match the range enforced by
  /// `ScenarioValidator.validateMaxSentences` (1…6); a UI value outside it would
  /// fail commit-time validation.
  static let maxSentencesRange = 1...6

  /// The global default statement cap surfaced when the override is unset.
  /// Sourced from the Engine so the editor default never drifts from the
  /// prompt-builder default (Views may depend on Engine).
  static var defaultMaxSentences: Int { PromptBuilder.defaultStatementMaxSentences }

  /// Maps the override Toggle to the stored value: on → seed with the global
  /// default (an explicit value the author can then adjust); off → nil (inherit
  /// the global default). Deliberately not the `subRounds` `== 1 ? nil` collapse
  /// trick — the default (3) lies inside the range, so "explicit 3" and "unset"
  /// must stay distinguishable.
  static func maxSentencesToggled(enabled: Bool) -> Int? {
    enabled ? defaultMaxSentences : nil
  }

  /// Clamps a Stepper value into the accepted range.
  static func clampedMaxSentences(_ value: Int) -> Int {
    min(max(value, maxSentencesRange.lowerBound), maxSentencesRange.upperBound)
  }

  /// The value the Stepper displays: the override if set, else the global
  /// default.
  static func maxSentencesDisplayValue(_ value: Int?) -> Int {
    value ?? defaultMaxSentences
  }
}
