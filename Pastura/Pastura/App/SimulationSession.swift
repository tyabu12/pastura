import Foundation
import Observation

/// App-level owner of an in-flight simulation run.
///
/// Phase B (ADR-017) inverts run ownership: a run must be able to outlive the
/// ``SimulationView`` that displays it, so its driving `Task` and
/// ``SimulationViewModel`` move out of the view's `@State` and into this
/// session, held by ``AppDependencies``.
///
/// ## PR1 scope (this file)
///
/// PR1 is a behaviour-preserving refactor: ``SimulationView`` still calls
/// ``end()`` on `onDisappear`, reproducing today's cancel-on-disappear, so a
/// run stays confined to its view exactly as before. The session introduces two
/// seams that PR2 activates without re-touching the view's `.task` wiring:
///
/// - ``startGuarded(source:scenario:makeViewModel:body:)`` — the start-time
///   single-run guard. Lifting ownership (PR2) removes cancel-on-disappear as
///   the de-facto mutex, so the invariant ("one `run()` per shared `LLMService`
///   at a time") is promoted to this explicit guard.
/// - ``adoptIfMatching(source:)`` — instant reconnect. PR2 stops calling
///   ``end()`` under "keep running", so a returning view re-projects the live
///   view model instead of starting a fresh run. In PR1 the run never survives
///   `onDisappear`, so this always returns `nil`.
///
/// The park / resume API (view-hide ↔ `SuspendController`) lands in PR2.
@Observable
@MainActor
final class SimulationSession {
  /// Outcome of a guarded start attempt.
  enum StartDecision: Equatable {
    /// The run was started; the session now owns it.
    case started
    /// Refused: the session already owns a run. The caller should offer to
    /// return to the live run rather than start a second one (PR2 UI; PR1
    /// logs and no-ops because cancel-on-disappear makes a second start
    /// structurally unreachable).
    case refusedLiveRunExists
  }

  /// The view model driving the owned run, or `nil` when no run is owned.
  private(set) var viewModel: SimulationViewModel?

  /// The scenario the owned run executes against — kept so a returning
  /// ``SimulationView`` can re-project it on adopt without re-parsing (PR2).
  private(set) var scenario: Scenario?

  /// Identity of the owned run, used by ``adoptIfMatching(source:)`` to decide
  /// whether a returning view is the one this run belongs to.
  private(set) var source: SimulationView.Source?

  /// The unstructured task driving the run.
  ///
  /// Relocated from `SimulationView.drive(_:_:)`. An unstructured `Task` does
  /// not inherit `.task` cancellation, which is what lets the run outlive the
  /// view (PR2); ``end()`` is then the explicit cancellation point (reproducing
  /// cancel-on-disappear in PR1).
  private var driveTask: Task<Void, Never>?

  /// Whether the session currently owns a run.
  ///
  /// Defined as "a run is owned" (`viewModel != nil`), deliberately **not**
  /// `viewModel?.isRunning`: `isRunning` is set asynchronously inside `run()`,
  /// so a guard keyed on it would race — a second ``startGuarded(source:scenario:makeViewModel:body:)``
  /// issued before the run task first executes would observe `isRunning == false`
  /// and wrongly allow a concurrent run. Occupancy is set synchronously by
  /// ``startGuarded(source:scenario:makeViewModel:body:)`` and cleared by
  /// ``end()``, so the single-run guard is race-free.
  var isLive: Bool { viewModel != nil }

  init() {}

  /// Returns the owned view model iff it matches `source`, else `nil`.
  ///
  /// Lets a returning ``SimulationView`` reconnect to a still-owned run (PR2)
  /// instead of starting a fresh one. PR1 always returns `nil` because the run
  /// is ended on `onDisappear`.
  func adoptIfMatching(source: SimulationView.Source) -> SimulationViewModel? {
    guard isLive, self.source == source else { return nil }
    return viewModel
  }

  /// Starts a run under the single-run guard.
  ///
  /// Refuses with ``StartDecision/refusedLiveRunExists`` when the session
  /// already owns a run (``isLive``). On ``StartDecision/started`` the session
  /// adopts the freshly-built view model, records the run identity, and spawns
  /// the driving task; the view model's `runTask` is pointed at the same task so
  /// the existing `cancelSimulation()` / memory-warning paths still reach it.
  ///
  /// - Parameters:
  ///   - source: The run's identity (fresh scenario vs. resume).
  ///   - scenario: The parsed scenario the run executes against.
  ///   - makeViewModel: Builds the view model; invoked only when the guard
  ///     passes, so a refused start does not construct a throwaway VM.
  ///   - body: The async work driving the run (typically `vm.run(...)` /
  ///     `vm.resume(...)`).
  /// - Returns: Whether the run started or was refused.
  func startGuarded(
    source: SimulationView.Source,
    scenario: Scenario,
    makeViewModel: () -> SimulationViewModel,
    body: @escaping (SimulationViewModel) async -> Void
  ) -> StartDecision {
    if isLive { return .refusedLiveRunExists }
    let viewModel = makeViewModel()
    self.viewModel = viewModel
    self.scenario = scenario
    self.source = source
    let task = Task { await body(viewModel) }
    // Intentional dual assignment of the SAME task: `driveTask` is the
    // session's cancellation handle (``end()``), and `viewModel.runTask` is the
    // VM's (`cancelSimulation()` — user cancel, memory warning). Two independent
    // cancellation entry points onto one task; `Task.cancel()` is idempotent, so
    // there is no double-cancel hazard. Not a duplicate to "clean up".
    viewModel.runTask = task
    driveTask = task
    return .started
  }

  /// Ends the owned run: cancels the driving task and releases all references.
  ///
  /// Cancelling `driveTask` unwinds `run()` through its terminal ladder, which
  /// persists a resumable `.paused` row for a mid-flight teardown (the lossless
  /// safety net — see `SimulationViewModel.finalizeRun(llm:)`). In PR1 this is
  /// called from `SimulationView.onDisappear`, exactly reproducing today's
  /// cancel-on-disappear behaviour.
  func end() {
    driveTask?.cancel()
    driveTask = nil
    viewModel = nil
    scenario = nil
    source = nil
  }
}
