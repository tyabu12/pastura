import Foundation
import Testing

@testable import Pastura

// MARK: - Background continuation tests

/// Tests the public API that gates background continuation. Does NOT exercise
/// the full BGTaskScheduler lifecycle — that requires a real iOS background
/// transition which cannot be simulated in unit tests. The reload-between-
/// inferences safety is covered indirectly by SimulationRunnerTests
/// (pausesBetweenPhasesNotOnlyBetweenRounds) and LlamaCppServiceTests
/// (reloadModelFailureKeepsNotLoaded).
@Suite(.serialized)
@MainActor
struct SimulationViewModelBackgroundTests {

  private func makeSUT(
    backgroundManager: BackgroundSimulationManager? = nil
  ) throws -> SimulationViewModel {
    let db = try DatabaseManager.inMemory()
    return SimulationViewModel(
      simulationRepository: GRDBSimulationRepository(dbWriter: db.dbWriter),
      turnRepository: GRDBTurnRepository(dbWriter: db.dbWriter),
      backgroundManager: backgroundManager
    )
  }

  // MARK: - canEnableBackgroundContinuation gating

  @Test func cannotEnableWhenBackgroundManagerIsNil() throws {
    let sut = try makeSUT(backgroundManager: nil)
    #expect(sut.canEnableBackgroundContinuation == false)
  }

  @Test func cannotEnableWhenLLMIsNotLlamaCppService() async throws {
    // MockLLMService is not LlamaCppService → feature should be gated off
    // even with a background manager present.
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    // Without a currentLLM set (before run() is called), it's also false.
    #expect(sut.canEnableBackgroundContinuation == false)
  }

  // MARK: - Scene phase handlers are safe when not running

  @Test func scenePhaseBackgroundIsNoOpWhenNotRunning() throws {
    let sut = try makeSUT()
    let controller = SuspendController()
    sut.suspendController = controller
    #expect(sut.isRunning == false)

    sut.handleScenePhaseBackground()

    #expect(sut.isPaused == false, "Should not pause when simulation is not running")
    #expect(
      controller.isSuspendRequested() == false,
      "Should not signal suspend when simulation is not running"
    )
  }

  @Test func willResignActiveIsNoOpWhenNotRunning() throws {
    let sut = try makeSUT()
    let controller = SuspendController()
    sut.suspendController = controller
    #expect(sut.isRunning == false)

    sut.handleWillResignActive()

    #expect(
      controller.isSuspendRequested() == false,
      "Should not signal suspend when simulation is not running"
    )
  }

  @Test func scenePhaseForegroundIsNoOpWhenNotRunning() async throws {
    let sut = try makeSUT()
    // Controller is pre-suspended to detect a spurious resume.
    let controller = SuspendController()
    controller.requestSuspend()
    sut.suspendController = controller
    #expect(sut.isRunning == false)

    await sut.handleScenePhaseForeground()

    #expect(sut.isPaused == false)
    #expect(
      controller.isSuspendRequested() == true,
      "Should not resume a parked controller when simulation is not running"
    )
  }

  // MARK: - Disable is safe

  @Test func disableBackgroundContinuationIsSafeWhenNeverEnabled() throws {
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    // Should not throw, should not crash.
    sut.disableBackgroundContinuation()
    #expect(sut.isBackgroundContinuationEnabled == false)
  }

  @Test func disableBackgroundContinuationIsIdempotent() throws {
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    sut.disableBackgroundContinuation()
    sut.disableBackgroundContinuation()
    #expect(sut.isBackgroundContinuationEnabled == false)
  }

  // MARK: - BG task expiration

  /// `handleBackgroundExpiration` may fire after `run()` has already exited
  /// (e.g., user cancelled, then iOS expired the BG task shortly after).
  /// `pauseSimulation`'s `isRunning` guard must short-circuit the entire
  /// callback path — no spurious log entry, no stale paused state.
  @Test func backgroundExpirationIgnoredWhenNotRunning() throws {
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    #expect(sut.isRunning == false)
    #expect(sut.isPaused == false)

    sut.handleBackgroundExpiration()

    #expect(sut.isPaused == false, "Guard should prevent isPaused mutation")
    #expect(sut.logEntries.isEmpty, "Guard should prevent reason log entry")
    #expect(sut.errorMessage == nil, "Expiration must never set errorMessage")
  }

  // MARK: - Toggle OFF invariants

  /// Toggle OFF means `isBackgroundContinuationEnabled` stays false and the
  /// BG task is never scheduled. The scene-phase handlers must still function
  /// (they signal the SuspendController regardless of toggle), but no reload
  /// or completeTask activity should fire in the absence of a scheduled task.
  @Test func toggleOFFDisableIsSafeWithoutSchedule() throws {
    let bgManager = BackgroundSimulationManager()
    let sut = try makeSUT(backgroundManager: bgManager)
    #expect(sut.isBackgroundContinuationEnabled == false)

    // With no pending BG task and no LLM, both paths must be safe.
    sut.disableBackgroundContinuation()
    #expect(sut.isBackgroundContinuationEnabled == false)
  }

  // MARK: - BG expiration FG gate

  /// The FG gate on `handleBackgroundExpiration` must short-circuit before
  /// `pauseSimulation` when the app is foregrounded. Without this gate, a
  /// race between BG expiration and FG return can strand the user with
  /// `runner.isPaused = true` plus a misleading "Background time exceeded"
  /// log appearing after they've already foregrounded.
  ///
  /// Limitation: `isRunning` is `private(set)` and only flipped by a real
  /// `run()` call, so this test cannot distinguish "gate fired" from "the
  /// pre-existing `isRunning` guard inside `pauseSimulation` fired". It
  /// does lock the default value of `isAppBackgrounded` (must be `false`,
  /// matching a foregrounded app) and the no-state-mutation contract.
  @Test func backgroundExpirationSkippedWhenAppIsForegrounded() throws {
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    #expect(sut.isAppBackgrounded == false, "Default must reflect foregrounded app.")

    sut.handleBackgroundExpiration()

    #expect(sut.isPaused == false, "Gate must skip pause when foregrounded.")
    #expect(sut.logEntries.isEmpty, "Gate must short-circuit before pauseSimulation logs.")
    #expect(sut.errorMessage == nil, "Expiration must never set errorMessage.")
  }

  // MARK: - BG activation flag

  /// The activation flag must be set BEFORE the `isRunning / !isCompleted /
  /// !isCancelled` guard inside `handleBackgroundActivation`, because the OS
  /// consumes the one-shot scheduled request on the activation callback
  /// regardless of whether the VM does useful work with it. Guarding the
  /// flag-set below would leave the toggle stuck armed on the next FG return
  /// after a cancelled simulation.
  @Test func bgActivationSetsFlagEvenWhenGuardFails() async throws {
    let sut = try makeSUT(backgroundManager: BackgroundSimulationManager())
    #expect(sut.isRunning == false)
    #expect(sut.didActivateBGTask == false)

    await sut.handleBackgroundActivation()

    #expect(
      sut.didActivateBGTask == true,
      "Flag must record activation even when the VM guard short-circuits.")
  }

  // Note: the positive path (scene-phase handler signals requestSuspend /
  // resume against an in-flight run) is exercised end-to-end by Step 18's
  // integration test, which drives a full MockLLMService run and verifies the
  // simulation survives a suspend/resume cycle mid-round.
}
