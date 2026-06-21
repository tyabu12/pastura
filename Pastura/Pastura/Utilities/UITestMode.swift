import Foundation

/// Single source of truth for "is this process running under the XCUITest
/// harness?" — i.e. launched with the `--ui-test` argument that
/// `PasturaApp.setupUITestState()` keys its in-memory bootstrap off.
///
/// Used to suppress *continuous* animations (indeterminate `ProgressView`,
/// repeating `symbolEffect`, `repeatForever` pulses) while UI tests run. Such
/// animations never let XCUITest reach "idle", so every subsequent element
/// query stalls for the full idle-wait — on the GPU-less CI simulator this
/// inflates each heavy `SimulationView` test from seconds to minutes (#728).
///
/// `#if DEBUG`-gated: in Release the `--ui-test` arg is never passed, so
/// `isActive` folds to a constant `false` and the `CommandLine` read is
/// compiled out entirely. Production behavior is therefore unchanged.
nonisolated enum UITestMode {
  /// `true` only when the process was launched with `--ui-test` (DEBUG builds).
  static var isActive: Bool {
    #if DEBUG
      return CommandLine.arguments.contains("--ui-test")
    #else
      return false
    #endif
  }
}
