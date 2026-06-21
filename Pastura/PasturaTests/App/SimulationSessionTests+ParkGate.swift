import Foundation
import Testing

@testable import Pastura

// Phase B PR2 (ADR-017) park/resume gate + return routing + VM↔session gate
// routing. Split from `SimulationSessionTests.swift` to stay under the 400-line
// file_length cap — a sibling-file `extension` of the SAME suite (not a new
// `@Suite`), per `.claude/rules/testing.md`. Inherits the suite's `.serialized`
// + `@MainActor` isolation.
extension SimulationSessionTests {

  /// Starts a live session whose owned VM has `controller` attached as its
  /// suspend channel, without running a real `run()` (a no-op body keeps the
  /// slot occupied). Lets the gate be exercised against a real
  /// ``SuspendController`` rather than a full inference.
  private func makeLiveSession(
    controller: SuspendController,
    source: SimulationView.Source = .scenario(scenarioId: "test")
  ) throws -> SimulationSession {
    let session = SimulationSession()
    let (viewModel, _) = try makeViewModel()
    viewModel.suspendController = controller
    let scenario = makeTestScenario(agentNames: ["Alice"], rounds: 1)
    _ = session.startGuarded(
      source: source,
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { _ in })
    return session
  }

  // MARK: - Park / resume gate

  @Test func parkSuspendsOnFirstReasonAndResumesOnLast() throws {
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)

    #expect(controller.isSuspendRequested() == false, "a fresh run is not parked")

    session.requestPark(reason: .viewHide)
    #expect(controller.isSuspendRequested() == true, "first park suspends the run")
    #expect(session.parkReasons == [.viewHide])

    session.requestResume(reason: .viewHide)
    #expect(controller.isSuspendRequested() == false, "removing the only reason resumes")
    #expect(session.parkReasons.isEmpty)

    session.end()
  }

  @Test func parkStaysSuspendedWhileAnotherReasonHolds() throws {
    // Case (c): away + app-background. Foregrounding removes only
    // `.appBackground`; `.viewHide` remains, so the run stays parked.
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)

    session.requestPark(reason: .viewHide)
    session.requestPark(reason: .appBackground)
    #expect(controller.isSuspendRequested() == true)
    #expect(session.parkReasons == [.viewHide, .appBackground])

    // App returns to foreground — only the background reason clears.
    session.requestResume(reason: .appBackground)
    #expect(
      controller.isSuspendRequested() == true,
      "still parked: the view is still hidden")
    #expect(session.parkReasons == [.viewHide])

    // User returns to the screen — the last reason clears.
    session.requestResume(reason: .viewHide)
    #expect(controller.isSuspendRequested() == false)
    #expect(session.parkReasons.isEmpty)

    session.end()
  }

  @Test func userPauseResumeWhileViewHideHeldStaysParked() throws {
    // The reason `.userPause` exists so the pause button composes through the
    // gate: a user-resume while the run is still parked-away (`.viewHide` held)
    // must NOT un-park. A direct `controller.resume()` would desync.
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)

    session.requestPark(reason: .viewHide)  // left the screen
    session.requestPark(reason: .userPause)  // tapped pause on a re-adopted view
    #expect(controller.isSuspendRequested() == true)
    #expect(session.parkReasons == [.viewHide, .userPause])

    session.requestResume(reason: .userPause)  // tapped resume
    #expect(
      controller.isSuspendRequested() == true,
      "user-resume does not un-park while view-hide still holds")
    #expect(session.parkReasons == [.viewHide])

    session.requestResume(reason: .viewHide)
    #expect(controller.isSuspendRequested() == false)

    session.end()
  }

  @Test func bgExpirationPauseWhileParkedAwayStaysParked() throws {
    // Parked-away + app-background, then a BG-expiration `pauseSimulation`
    // (routed through `.userPause` in PR2). The extra reason must not resume;
    // the run stays parked until every reason clears.
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)

    session.requestPark(reason: .viewHide)
    session.requestPark(reason: .appBackground)
    session.requestPark(reason: .userPause)  // BG expiration → pauseSimulation
    #expect(controller.isSuspendRequested() == true)
    #expect(session.parkReasons == [.viewHide, .appBackground, .userPause])

    session.end()
  }

  @Test func viewHidePrecedenceQuery() throws {
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)

    #expect(session.isParkedForViewHide == false)
    session.requestPark(reason: .appBackground)
    #expect(
      session.isParkedForViewHide == false,
      "an app-background-only park does not suppress the CPU switch")
    session.requestPark(reason: .viewHide)
    #expect(
      session.isParkedForViewHide == true,
      "a view-hide park suppresses the background-continuation CPU switch")

    session.end()
  }

  // MARK: - Return routing (in-flight indicator)

  @Test func returnRouteDerivesFromSourceAndScenarioName() throws {
    let session = SimulationSession()
    #expect(session.returnRoute == nil, "no route when idle")
    #expect(session.tab == nil)

    let (viewModel, _) = try makeViewModel()
    let scenario = makeTestScenario(agentNames: ["Alice"], rounds: 1)
    _ = session.startGuarded(
      source: .scenario(scenarioId: "abc"),
      scenario: scenario,
      tab: .search,
      makeViewModel: { viewModel },
      body: { _ in })

    #expect(session.tab == .search, "the host tab is recorded")
    #expect(
      session.returnRoute == .simulation(scenarioId: "abc"),
      "a fresh run returns to .simulation (RouteHint title is identity-neutral)")

    session.end()
    #expect(session.returnRoute == nil, "cleared on end()")
    #expect(session.tab == nil)
  }

  @Test func returnRouteForResumeSource() throws {
    let session = SimulationSession()
    let (viewModel, _) = try makeViewModel()
    let scenario = makeTestScenario(agentNames: ["Alice"], rounds: 1)
    _ = session.startGuarded(
      source: .resume(runId: "run-1"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { _ in })

    #expect(
      session.returnRoute == .resumeSimulation(simulationId: "run-1"),
      "a resume run returns to .resumeSimulation")

    session.end()
  }

  // MARK: - VM ↔ session gate routing

  @Test func viewModelRoutesParkThroughSessionGate() throws {
    // A session-owned VM routes its non-terminal suspend/resume through the gate
    // (so user-pause / scene-phase compose with view-hide), not the controller.
    let controller = SuspendController()
    let session = try makeLiveSession(controller: controller)
    let viewModel = try #require(session.viewModel)

    viewModel.routePark(reason: .userPause)
    #expect(session.parkReasons == [.userPause], "routed through the gate, not direct")
    #expect(controller.isSuspendRequested() == true)

    viewModel.routeUnpark(reason: .userPause)
    #expect(session.parkReasons.isEmpty)
    #expect(controller.isSuspendRequested() == false)

    session.end()
  }

  @Test func viewModelFallsBackToControllerWithoutSession() throws {
    // A VM with no owning session (fixture tests) touches the controller
    // directly — preserving pre-Phase-B behaviour.
    let (viewModel, _) = try makeViewModel()
    let controller = SuspendController()
    viewModel.suspendController = controller
    #expect(viewModel.session == nil)

    viewModel.routePark(reason: .appBackground)
    #expect(controller.isSuspendRequested() == true)
    viewModel.routeUnpark(reason: .appBackground)
    #expect(controller.isSuspendRequested() == false)
  }

  @Test func backgroundActivationStaysParkedWhenLeftScreen() async throws {
    // Away-case precedence (critic Axis (b) / W②): a run parked because the user
    // left the screen must NOT switch to CPU and resume off-screen when the BG
    // task activates — ADR-017 Variant 3 keeps it parked in memory.
    let (viewModel, _) = try makeViewModel()
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let session = SimulationSession()
    _ = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { model in await model.run(scenario: scenario, llm: mock) })

    while viewModel.suspendController == nil {
      await Task.yield()
    }

    // The user leaves the screen with "keep running" → view-hide park.
    session.requestPark(reason: .viewHide)
    #expect(viewModel.suspendController?.isSuspendRequested() == true)

    // BG task activates while parked-away. Precedence: stay parked, no CPU switch.
    await viewModel.handleBackgroundActivation()

    #expect(
      viewModel.suspendController?.isSuspendRequested() == true,
      "view-hide-parked run stays parked through BG activation")
    #expect(viewModel.isOnCPU == false, "no off-screen CPU switch for a parked-away run")

    session.end()
    await viewModel.runTask?.value
  }

  // MARK: - Memory safety

  @Test func memoryWarningNoOpsWhenNoRunOwned() {
    // The away-case host can fire after a run ended; the session must no-op
    // rather than crash on a nil view model.
    let session = SimulationSession()
    session.handleMemoryWarning(isAppActive: true)
    session.resetMemoryThrottle()
    #expect(session.isLive == false)
  }

  @Test func memoryWarningPausesInFlightRun() async throws {
    // First foreground warning pauses (lossy-but-safe `.paused`), not cancels —
    // the single throttle's policy applied through the session.
    let (viewModel, _) = try makeViewModel()
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )

    let session = SimulationSession()
    _ = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { model in await model.run(scenario: scenario, llm: mock) })

    while viewModel.suspendController == nil {
      await Task.yield()
    }
    // Park the generate so the run holds in-flight (doesn't complete before the
    // warning), mirroring `endCancelsInFlightRunAndPersistsPaused`.
    session.requestPark(reason: .viewHide)
    try await Task.sleep(for: .milliseconds(50))
    #expect(viewModel.isRunning == true)
    #expect(viewModel.isPaused == false)

    session.handleMemoryWarning(isAppActive: true)
    #expect(viewModel.isPaused == true, "first foreground warning pauses, not cancels")
    #expect(viewModel.isCancelled == false)

    session.end()
    await viewModel.runTask?.value
  }

  /// Starts a real 1-round `speak_all` run and parks it away (`.viewHide`),
  /// returning once the run is genuinely held in-flight at its first generate
  /// (parked, not yet completed). Mirrors the inline setup of
  /// `memoryWarningPausesInFlightRun`; the two memory-warning-while-parked tests
  /// below share it. Uses `.milliseconds(50)` to settle, matching that test.
  ///
  /// The two `responses` are provisioned to mirror that inline setup but are
  /// never consumed by design: the run parks at its first generate and both
  /// callers tear it down (pause-compose / background-cancel → `end()`) before
  /// any generate completes, so `MockLLMService`'s exhaustion throw never fires.
  private func startParkedAwayRun() async throws -> (
    session: SimulationSession, viewModel: SimulationViewModel
  ) {
    let (viewModel, _) = try makeViewModel()
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#
    ])
    let scenario = makeTestScenario(
      agentNames: ["Alice", "Bob"],
      rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "Speak", outputSchema: ["statement": "string"])]
    )
    let session = SimulationSession()
    _ = session.startGuarded(
      source: .scenario(scenarioId: "test"),
      scenario: scenario,
      tab: .home,
      makeViewModel: { viewModel },
      body: { model in await model.run(scenario: scenario, llm: mock) })

    while viewModel.suspendController == nil {
      await Task.yield()
    }
    // The user left the screen with "keep running" → view-hide park.
    session.requestPark(reason: .viewHide)
    try await Task.sleep(for: .milliseconds(50))
    return (session, viewModel)
  }

  @Test func memoryWarningPauseComposesWithViewHidePark() async throws {
    // Parked-away (`.viewHide` held) + a FOREGROUND memory warning. The throttle
    // pauses (first warning), and `pauseSimulation` routes its suspend through the
    // gate as `.userPause` — so the run stays suspended and `parkReasons` composes
    // both reasons. Distinct from `memoryWarningPausesInFlightRun`, which pins only
    // the pause-not-cancel policy: this pins the park-gate composition (a
    // memory-warning pause must not desync the view-hide park).
    let (session, viewModel) = try await startParkedAwayRun()
    #expect(viewModel.isRunning == true)
    #expect(session.parkReasons == [.viewHide])

    session.handleMemoryWarning(isAppActive: true)
    #expect(viewModel.isPaused == true, "first foreground warning pauses, not cancels")
    #expect(viewModel.isCancelled == false)
    #expect(
      session.parkReasons == [.viewHide, .userPause],
      "the pause composes through the gate without un-parking the view-hide hold")
    #expect(viewModel.suspendController?.isSuspendRequested() == true)

    session.end()
    await viewModel.runTask?.value
  }

  @Test func memoryWarningCancelsParkedAwayRunInBackground() async throws {
    // Parked-away (`.viewHide` held) + a BACKGROUND memory warning. The throttle's
    // `!isActive` branch cancels immediately — a backgrounded run is jetsamed at a
    // much lower threshold, so preserving the terminal `.cancelled` status beats
    // losing the run silently. The view-hide park must not suppress that cancel.
    let (session, viewModel) = try await startParkedAwayRun()
    #expect(viewModel.isRunning == true)

    session.handleMemoryWarning(isAppActive: false)
    #expect(
      viewModel.isCancelled == true,
      "a background memory warning cancels even a view-hide-parked run")

    session.end()
    await viewModel.runTask?.value
  }
}
