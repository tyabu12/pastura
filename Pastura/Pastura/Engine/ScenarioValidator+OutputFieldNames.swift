import Foundation

// `nonisolated` on the extension is load-bearing: `ScenarioValidator` is a
// `nonisolated` Engine type, and a plain sibling-file `extension` would inherit
// the project's default MainActor isolation — breaking `nonisolated` callers in
// the main file (`validatePhases` / `validateBranch`). See
// `.claude/rules/swift-isolation.md` Pattern 3.
nonisolated extension ScenarioValidator {
  /// Rejects any `output:` field name that is not an ASCII identifier
  /// (``ScenarioConventions/isValidFieldName(_:)``).
  ///
  /// Every output key is emitted verbatim as a JSON-key literal
  /// (`"\"<name>\""`) into the LLM-phase GBNF grammar by ``GBNFGrammarBuilder``.
  /// A non-ASCII / multi-byte key reaches llama.cpp's sampler as a literal and
  /// crashes it at accept-time on-device — an uncatchable SIGABRT, the same
  /// mechanism that forced CJK choose-option *values* out of the grammar in
  /// #599 (#607). Surfacing it here (run-gate + editor) gives a clear load-time
  /// error instead of a mid-run ``LLMError/invalidGrammar``; the builder's own
  /// check stays as the unconditional backstop for paths that skip this gate.
  ///
  /// Validates **every** key, not just the canonical primary — all output keys
  /// reach the grammar, so a CJK *secondary* key (`inner_thought` / `reason`)
  /// is just as dangerous as the primary. Keys are sorted so the surfaced error
  /// is deterministic across runs.
  func validateOutputFieldNames(in phase: Phase, label: String) throws {
    guard let schema = phase.outputSchema else { return }
    for name in schema.keys.sorted() where !ScenarioConventions.isValidFieldName(name) {
      throw SimulationError.scenarioValidationFailed(
        ScenarioValidationMessage.outputFieldNameInvalid(label: label, name: name).localized)
    }
  }
}
