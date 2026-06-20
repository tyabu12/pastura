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
/// - ``adoptIfMatching(source:)`` — instant reconnect. Under "keep running"
///   (PR2) the view stops calling ``end()`` on disappear, so a returning view
///   re-projects the live view model instead of starting a fresh run.
///
/// ## PR2 scope (park / resume gate)
///
/// PR2 adds the view-hide ↔ ``SuspendController`` park API
/// (``requestPark(reason:)`` / ``requestResume(reason:)``) and the
/// return-routing info (``tab`` / ``returnRoute``) the in-flight indicator uses
/// to re-surface a parked-away run.
@Observable
@MainActor
final class SimulationSession {
  /// Outcome of a guarded start attempt.
  enum StartDecision: Equatable {
    /// The run was started; the session now owns it.
    case started
    /// Refused: the session already owns a run. The caller should offer to
    /// return to the live run rather than start a second one — surfaced as the
    /// "already running" + Return-to-run state on ``SimulationView`` and the
    /// in-flight indicator (PR2).
    case refusedLiveRunExists
  }

  /// A reason the owned run is currently parked (suspended off-screen).
  ///
  /// Phase B (ADR-017) introduces a second suspend trigger (view-hide)
  /// alongside the existing app-background one (ADR-003), and routes the
  /// user-pause button through the same gate. All three share the run's single
  /// ``SuspendController`` — `requestSuspend()` / `resume()` are idempotent but
  /// not *logically* safe to interleave (a resume for one reason while another
  /// still holds would wrongly un-park an off-screen run). ``parkReasons`` gates
  /// that: ``requestPark(reason:)`` suspends only on the empty→non-empty edge,
  /// ``requestResume(reason:)`` resumes only on the non-empty→empty edge.
  enum ParkReason: Hashable {
    /// The user left the simulation screen with "keep running" enabled (PR2).
    case viewHide
    /// The app moved to the background (ADR-003 scene-phase path).
    case appBackground
    /// The user tapped the pause button.
    case userPause
  }

  /// The view model driving the owned run, or `nil` when no run is owned.
  private(set) var viewModel: SimulationViewModel?

  /// The scenario the owned run executes against — kept so a returning
  /// ``SimulationView`` can re-project it on adopt without re-parsing (PR2).
  private(set) var scenario: Scenario?

  /// Identity of the owned run, used by ``adoptIfMatching(source:)`` to decide
  /// whether a returning view is the one this run belongs to.
  private(set) var source: SimulationView.Source?

  /// The tab whose stack hosted the run when it started.
  ///
  /// Captured at ``startGuarded(source:scenario:tab:makeViewModel:body:)`` time
  /// (focus mode pins the run to whichever tab was selected, so the selected
  /// tab at start *is* the host tab). Once the user leaves with "keep running",
  /// the sim route is popped off that tab's stack, so the route no longer exists
  /// anywhere — the in-flight indicator must re-select this tab and re-push
  /// ``returnRoute`` to bring the parked run back. `nil` when no run is owned.
  private(set) var tab: AppTab?

  /// The reasons the owned run is currently parked. Empty ⇒ running (or no run
  /// owned). See ``ParkReason`` for the gate contract.
  private(set) var parkReasons: Set<ParkReason> = []

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

  /// Whether the run is parked because the user left the screen (view-hide).
  ///
  /// Read by the background-continuation path: a view-hide park **suppresses**
  /// the CPU-inference switch on background-task activation — an away+backgrounded
  /// run stays parked in memory rather than burning CPU off-screen (ADR-017
  /// Variant 3 rejects off-screen inference). See
  /// `SimulationViewModel.handleBackgroundActivation()`.
  var isParkedForViewHide: Bool { parkReasons.contains(.viewHide) }

  /// The route that re-surfaces the owned run, or `nil` when no run is owned.
  ///
  /// Derived from ``source`` (identity) with the scenario name as the
  /// identity-neutral title hint (``RouteHint``), so a re-push during return
  /// shows the correct title from the first frame. The in-flight indicator
  /// selects ``tab`` and pushes this onto that tab's stack.
  var returnRoute: Route? {
    guard let source else { return nil }
    let hint = RouteHint(scenario?.name)
    switch source {
    case .scenario(let scenarioId):
      return .simulation(scenarioId: scenarioId, initialName: hint)
    case .resume(let runId):
      return .resumeSimulation(simulationId: runId, initialName: hint)
    }
  }

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
  ///   - tab: The tab whose stack hosts the run (the selected tab at start —
  ///     stored on ``tab`` for the in-flight indicator's return routing).
  ///   - makeViewModel: Builds the view model; invoked only when the guard
  ///     passes, so a refused start does not construct a throwaway VM.
  ///   - body: The async work driving the run (typically `vm.run(...)` /
  ///     `vm.resume(...)`).
  /// - Returns: Whether the run started or was refused.
  func startGuarded(
    source: SimulationView.Source,
    scenario: Scenario,
    tab: AppTab,
    makeViewModel: () -> SimulationViewModel,
    body: @escaping (SimulationViewModel) async -> Void
  ) -> StartDecision {
    if isLive { return .refusedLiveRunExists }
    let viewModel = makeViewModel()
    self.viewModel = viewModel
    self.scenario = scenario
    self.source = source
    self.tab = tab
    parkReasons = []
    let task = Task { await body(viewModel) }
    // Back-reference (weak on the VM) so the VM's non-terminal suspend/resume
    // (user-pause, scene-phase) route through this session's park gate instead
    // of touching the SuspendController directly — see `routePark(reason:)`.
    viewModel.session = self
    // Intentional dual assignment of the SAME task: `driveTask` is the
    // session's cancellation handle (``end()``), and `viewModel.runTask` is the
    // VM's (`cancelSimulation()` — user cancel, memory warning). Two independent
    // cancellation entry points onto one task; `Task.cancel()` is idempotent, so
    // there is no double-cancel hazard. Not a duplicate to "clean up".
    viewModel.runTask = task
    driveTask = task
    return .started
  }

  // MARK: - Park / resume gate

  /// Records `reason` as a park trigger and, on the empty→non-empty edge,
  /// suspends the run's in-flight generate.
  ///
  /// Idempotent per reason: re-parking an already-held reason is a no-op, and
  /// while *any* reason is held the controller stays suspended. The
  /// ``SuspendController`` is `nil` before `run()` attaches it (or after the run
  /// ends), in which case this is a harmless no-op.
  func requestPark(reason: ParkReason) {
    let wasEmpty = parkReasons.isEmpty
    parkReasons.insert(reason)
    if wasEmpty {
      viewModel?.suspendController?.requestSuspend()
    }
  }

  /// Clears `reason` as a park trigger and, on the non-empty→empty edge, resumes
  /// the run's parked generate.
  ///
  /// Resumes **only** when no other reason still holds the run parked — e.g. a
  /// user-pause resume on a re-adopted view while the run is still parked for
  /// ``ParkReason/viewHide`` leaves it parked (the run is still off-screen). This
  /// is why ``ParkReason/userPause`` routes through the gate rather than calling
  /// the controller directly: a direct `resume()` would desync ``parkReasons``
  /// from the controller and wrongly un-park.
  func requestResume(reason: ParkReason) {
    parkReasons.remove(reason)
    if parkReasons.isEmpty {
      viewModel?.suspendController?.resume()
    }
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
    tab = nil
    parkReasons = []
  }
}
