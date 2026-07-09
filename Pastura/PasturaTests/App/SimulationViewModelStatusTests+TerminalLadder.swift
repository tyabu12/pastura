import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `SimulationViewModelStatusTests` (file_length cap).
// These are an `extension` of the SAME suite — NOT a new `@Suite` — so they
// stay `.serialized` with the rest (see `.claude/rules/testing.md`). Pure
// `SimulationViewModel.terminalStatus(...)` ladder assertions: deterministic,
// no run / DB / mock needed, so no file-scope helpers live here.

extension SimulationViewModelStatusTests {

  // MARK: - Pure terminal-status ladder (deterministic, no run needed)

  @Test func terminalStatusLeavesPausedWhenExplicitlyPaused() {
    // didPersistPaused wins over everything → nil (skip the write, keep .paused).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: true, errorMessage: "boom",
        isCancelled: true, isCompleted: false) == nil)
  }

  @Test func terminalStatusFailedBeatsCompletion() {
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: "boom",
        isCancelled: false, isCompleted: true) == .failed)
  }

  @Test func terminalStatusFailedBeatsTeardown() {
    // A real error on a not-yet-completed run still wins over the `.paused`
    // teardown branch — errorMessage is checked above `!isCompleted` (#673).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: "boom",
        isCancelled: false, isCompleted: false) == .failed)
  }

  @Test func terminalStatusCancelBeatsTeardownAndCompletion() {
    // User-cancel (`isCancelled`) is checked above `!isCompleted`, so a run
    // cancelled mid-flight records `.cancelled`, never the teardown `.paused`.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: true, isCompleted: false) == .cancelled)
  }

  @Test func terminalStatusTornDownMidFlightStaysPaused() {
    // #673 — a run torn down before completion (no pause/cancel/error) stays
    // resumable rather than being marked complete. Symmetric across fresh and
    // resumed runs: `isResumedRun` is no longer a discriminator here. This
    // replaces the prior fresh-vs-resumed asymmetry pin (the fresh case used
    // to write `.completed`, silently losing the run).
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: false, isCompleted: false) == .paused)
  }

  @Test func terminalStatusCompletedRunWritesCompleted() {
    // The only path to `.completed`: `.simulationCompleted` set isCompleted, and
    // no higher-precedence terminal flag fired.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: false, isCompleted: true) == .completed)
  }

  // MARK: - ADR-021 D6: status taxonomy unchanged by turn degradation

  @Test func terminalStatusIgnoresDegradationARunWithSkipsStaysCompleted() {
    // ADR-021 D6 — a run that reached `.simulationCompleted` with skipped
    // turns persists as `.completed`; the skip count is metadata
    // (`degradedTurnCount`), NOT a lifecycle state. `terminalStatus` takes no
    // degradation input, so this is a taxonomy-invariance pin: if a future
    // change routed skips into a new status (e.g. `completedWithGaps`), the
    // no-error completed path must still resolve to `.completed` here.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: nil,
        isCancelled: false, isCompleted: true) == .completed)
  }

  @Test func terminalStatusBreakerAbortMapsToFailed() {
    // ADR-021 D4/D6 — a circuit-breaker abort (3 consecutive skips) throws
    // `SimulationError.turnFailureLimitReached`, which surfaces through the
    // existing error path and sets `errorMessage`. That maps to `.failed`
    // exactly as any other run-fatal error — the breaker introduces no new
    // terminal status.
    #expect(
      SimulationViewModel.terminalStatus(
        didPersistPaused: false, errorMessage: "Too many turns were skipped in a row",
        isCancelled: false, isCompleted: false) == .failed)
  }
}
