import Foundation
import Observation

/// Tracks whether a simulation is currently running in-process.
///
/// Owned by `AppDependencies`. UI observes `isActive` to guard against
/// state changes that would race with in-flight inference — today the
/// only consumer is the Settings Models section, which disables model
/// switching while a simulation is running. `AppDependencies.regenerateLLMService(for:)`
/// documents the symmetric invariant for direct callers.
///
/// ## Call sites
///
/// `enter()` and `leave()` must be called from `SimulationViewModel.run()`
/// only: `enter()` at the top, `leave()` in the existing `defer` block.
/// The `defer` already covers load-failure, cancellation, pause, and
/// completion paths, so one enter/leave pair per `run()` invocation
/// suffices. The background-mode extension (`SimulationViewModel+Background`)
/// operates *within* a running `run()`; it must not call `enter()` /
/// `leave()` itself.
///
/// ## Counter semantics
///
/// The registry is a signed counter so nested brackets compose. This
/// is a forward-compatibility affordance — no current caller nests —
/// and it means `isActive` stays `true` until *every* outstanding
/// `enter()` is matched. `leave()` without a matching `enter()` traps
/// via `precondition`; the counter is load-bearing for the UI guard
/// and silently clamping at 0 would mask the accounting bug.
@Observable
@MainActor
final class SimulationActivityRegistry {
  /// Number of unmatched `enter()` calls. Readable for tests and
  /// diagnostics only — callers should use `isActive` for decisions.
  private(set) var activeCount: Int = 0

  /// `true` iff at least one `enter()` has not been matched by a
  /// corresponding `leave()`.
  var isActive: Bool { activeCount > 0 }

  init() {}

  /// Register that a simulation has started. Must be matched by
  /// exactly one `leave()` call.
  func enter() {
    activeCount += 1
  }

  /// Register that a simulation has ended.
  ///
  /// - Precondition: A matching `enter()` must have been called. The
  ///   assertion traps instead of clamping because a missed `enter()`
  ///   here would leave `isActive` permanently stuck in a wrong
  ///   state on the next round — which silently disables or enables
  ///   the Settings model-switch UI.
  func leave() {
    precondition(
      activeCount > 0,
      "SimulationActivityRegistry.leave() called without matching enter()")
    activeCount -= 1
  }
}
