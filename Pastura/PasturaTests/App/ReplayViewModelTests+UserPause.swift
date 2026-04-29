import Foundation
import Testing

@testable import Pastura

/// Tests pinning the user-driven pause / resume API and its coexistence
/// with scene-phase pause (`onBackground` / `onForeground`).
///
/// `.user` reason is **sticky**: scene-phase transitions never clear it.
/// Specifically, `onForeground()` resumes only from `.paused(.scenePhase)`,
/// not from `.paused(.user)`. The user must explicitly call `userResume()`
/// to leave a user-driven pause.
///
/// Tests live in a sibling `extension` per `.claude/rules/testing.md` —
/// adding a new `@Suite` would race the original on shared static fixtures
/// (scenario YAML, fastConfig).
extension ReplayViewModelTests {

  // MARK: - userPause from .playing

  @Test func userPauseFromPlayingTransitionsToPausedUser() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.userPause()
    if case .paused(_, _, _, let reason) = viewModel.state {
      #expect(reason == .user)
    } else {
      Issue.record("Expected .paused(.user), got \(viewModel.state)")
    }
  }

  @Test func userPausePreservesSourceAndCursorPosition() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    guard case .playing(let playingIdx, let playingCursor) = viewModel.state else {
      Issue.record("Expected .playing before userPause(), got \(viewModel.state)")
      return
    }
    viewModel.userPause()
    if case .paused(let pausedIdx, let pausedCursor, _, .user) = viewModel.state {
      #expect(pausedIdx == playingIdx)
      #expect(pausedCursor == playingCursor)
    } else {
      Issue.record("Expected .paused(.user) preserving position, got \(viewModel.state)")
    }
  }

  // MARK: - userResume from .paused(.user)

  @Test func userResumeFromPausedUserResumesPlayback() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.userPause()
    guard case .paused(let pausedIdx, let pausedCursor, _, .user) = viewModel.state
    else {
      Issue.record("Expected .paused(.user), got \(viewModel.state)")
      return
    }
    viewModel.userResume()
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == pausedIdx)
      #expect(rCursor == pausedCursor)
    } else {
      Issue.record("Expected .playing after userResume(), got \(viewModel.state)")
    }
  }

  // MARK: - .user is sticky across scene-phase transitions

  @Test func onForegroundFromPausedUserIsNoOp() async throws {
    // The user pauses, app goes background, then comes back to foreground.
    // Without the .user-sticky rule, onForeground() would auto-resume —
    // surprising the user who explicitly paused.
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.userPause()
    guard case .paused(_, _, _, .user) = viewModel.state else {
      Issue.record("Expected .paused(.user), got \(viewModel.state)")
      return
    }
    viewModel.onForeground()
    if case .paused(_, _, _, let reason) = viewModel.state {
      #expect(reason == .user)
    } else {
      Issue.record("Expected .paused(.user) preserved, got \(viewModel.state)")
    }
  }

  @Test func onBackgroundFromPausedUserIsNoOp() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.userPause()
    let stateBefore = viewModel.state
    viewModel.onBackground()
    #expect(viewModel.state == stateBefore)
  }

  // MARK: - userPause from .paused(.scenePhase) — race-safety override

  @Test func userPauseFromPausedScenePhaseOverridesToUser() async throws {
    // Scene-phase pause first (simulating background), then user calls
    // userPause(). Even though the UI is normally hidden during BG,
    // the race-safety override promotes reason to .user so the
    // subsequent foreground does NOT auto-resume.
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    guard case .paused(_, _, _, .scenePhase) = viewModel.state else {
      Issue.record("Expected .paused(.scenePhase), got \(viewModel.state)")
      return
    }
    viewModel.userPause()
    if case .paused(_, _, _, let reason) = viewModel.state {
      #expect(reason == .user)
    } else {
      Issue.record("Expected .paused(.user) after override, got \(viewModel.state)")
    }
    // Foreground arrives after the user-pause — must NOT auto-resume.
    viewModel.onForeground()
    if case .paused(_, _, _, .user) = viewModel.state {
      // expected
    } else {
      Issue.record("Expected .paused(.user) preserved, got \(viewModel.state)")
    }
  }

  // MARK: - Defensive no-ops on .paused(.scenePhase) / .idle / .transitioning

  @Test func userResumeFromPausedScenePhaseIsNoOp() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    let stateBefore = viewModel.state
    viewModel.userResume()
    #expect(viewModel.state == stateBefore)
  }

  @Test func userPauseFromIdleIsNoOp() throws {
    let viewModel = try Self.makeVM()
    viewModel.userPause()
    #expect(viewModel.state == .idle)
  }

  @Test func userResumeFromIdleIsNoOp() throws {
    let viewModel = try Self.makeVM()
    viewModel.userResume()
    #expect(viewModel.state == .idle)
  }

  @Test func userPauseFromTransitioningIsNoOp() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
    viewModel.userPause()
    #expect(viewModel.state == .transitioning)
  }

  @Test func userResumeFromTransitioningIsNoOp() async throws {
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.downloadComplete()
    #expect(viewModel.state == .transitioning)
    viewModel.userResume()
    #expect(viewModel.state == .transitioning)
  }

  // MARK: - isUserPaused observability

  @Test func isUserPausedTracksReasonAccurately() async throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.isUserPaused == false)  // .idle

    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    #expect(viewModel.isUserPaused == false)  // .playing

    viewModel.onBackground()
    guard case .paused(_, _, _, .scenePhase) = viewModel.state else {
      Issue.record("Expected .paused(.scenePhase), got \(viewModel.state)")
      return
    }
    #expect(viewModel.isUserPaused == false)  // .paused(.scenePhase)

    viewModel.onForeground()
    #expect(viewModel.isUserPaused == false)  // back to .playing

    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 2 }
    viewModel.userPause()
    #expect(viewModel.isUserPaused == true)  // .paused(.user)

    viewModel.userResume()
    #expect(viewModel.isUserPaused == false)  // back to .playing
  }

  // MARK: - Regression — existing scenePhase round-trip still works

  @Test func onForegroundFromPausedScenePhaseStillAutoResumes() async throws {
    // Critic Axis 5 regression coverage: confirms the unchanged
    // `.paused(.scenePhase) → onForeground → .playing` path survives the
    // PauseReason addition. Existing tests at ReplayViewModelTests.swift
    // (onForegroundResumesFromPausedPosition) cover the same path under
    // the renamed pattern; this one re-asserts it from the user-pause
    // suite for clarity.
    let viewModel = try Self.makeVM()
    viewModel.start()
    await Self.waitForState(viewModel) { _ in viewModel.agentOutputs.count >= 1 }
    viewModel.onBackground()
    guard case .paused(let idx, let cursor, _, .scenePhase) = viewModel.state else {
      Issue.record("Expected .paused(.scenePhase), got \(viewModel.state)")
      return
    }
    viewModel.onForeground()
    if case .playing(let rIdx, let rCursor) = viewModel.state {
      #expect(rIdx == idx)
      #expect(rCursor == cursor)
    } else {
      Issue.record("Expected .playing after onForeground(.scenePhase), got \(viewModel.state)")
    }
  }
}
