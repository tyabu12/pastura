import Foundation

// Split from `ParityFixtureEmitter.swift` when that file passed SwiftLint's
// `file_length` cap a second time (the first split sent the Kotlin rendering to
// `+KotlinSource.swift`). The error enum is the natural next boundary: it is a
// sibling type rather than a member, so nothing in it needs the emitter's
// private storage.

/// Why a parity fixture could not be produced.
package enum ParityFixtureError: Error, CustomStringConvertible {
  /// A scenario encoded to bytes that are not valid UTF-8.
  case notUTF8(String)
  /// A fixture contains bytes a Kotlin raw string cannot carry verbatim.
  case rawStringUnsafe(String, String)
  /// A scenario declares more than one distinct `choose` option menu, which
  /// the schema-only ``RecordingResponder`` cannot disambiguate.
  case ambiguousChoiceOptions(String, [[String]])
  /// A spec asked to cancel on a `phaseCompleted` path the run never emitted.
  ///
  /// Loud rather than silent because the failure is invisible in the artefact:
  /// the run simply completes, and the generated golden freezes a
  /// `simulation_completed` tail that looks like a healthy fixture while
  /// measuring no cancellation at all.
  case cancelTriggerNeverFired(String, [Int])

  package var description: String {
    switch self {
    case .notUTF8(let name):
      return "parity fixture '\(name)' encoded to non-UTF-8 bytes"
    case .rawStringUnsafe(let name, let reason):
      return
        "parity fixture '\(name)' cannot be embedded in a Kotlin raw string: it contains \(reason)"
    case .ambiguousChoiceOptions(let scenarioID, let menus):
      let rendered = menus.map { "[\($0.joined(separator: ", "))]" }.joined(separator: " vs ")
      return
        "scenario '\(scenarioID)' declares \(menus.count) distinct choose option menus (\(rendered)); "
        + "the parity responder reads only the schema, so it cannot tell which phase is calling"
    case .cancelTriggerNeverFired(let name, let path):
      return
        "parity fixture '\(name)' asked to cancel after phase_completed "
        + "[\(path.map(String.init).joined(separator: ", "))], but the run never emitted that "
        + "event — the fixture would freeze a completed run instead of a cancellation tail"
    }
  }
}
