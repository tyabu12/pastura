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
}
