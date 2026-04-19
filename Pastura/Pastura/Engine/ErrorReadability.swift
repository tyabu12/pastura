import Foundation

/// Returns the most human-readable description of an arbitrary `Error`.
///
/// Prefers ``LocalizedError/errorDescription`` when the error conforms,
/// falling back to `String(describing:)` otherwise. Used at the Engine wrap
/// points where foreign errors (typically `LLMError` or validator throws)
/// are bridged into ``SimulationError``-typed associated-value strings. Using
/// `"\(error)"` there loses the inner message because it stringifies the
/// whole enum case (`generationFailed(description: "...")`) instead of just
/// the meaningful text.
///
/// Foundation-only — Engine layer dependency rules (depends on LLM + Models)
/// are preserved.
nonisolated func readableDescription(_ error: Error) -> String {
  if let localized = (error as? LocalizedError)?.errorDescription {
    return localized
  }
  return String(describing: error)
}
