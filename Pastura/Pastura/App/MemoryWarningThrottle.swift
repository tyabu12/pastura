import Foundation

/// Decides how to react to `UIApplication.didReceiveMemoryWarningNotification`
/// during a simulation, with a 2-strike escalation in the foreground.
///
/// Pure value type with a `mutating` decision step — extracted from
/// `SimulationView` so the policy is independently testable without
/// having to synthesize SwiftUI `@Environment(\.scenePhase)`.
///
/// Policy rationale (#84 / ADR-002 §7 follow-up):
/// - **Already paused**: ignore. The model is loaded but not generating;
///   no pressure relief to offer beyond a full cancel, which would be
///   punitive on a manually-paused user.
/// - **Background or transitioning out of active**: cancel immediately.
///   BG-task'd apps are jetsamed at much lower memory thresholds; pausing
///   without freeing risks losing the simulation with no chance to call
///   `setTaskCompleted(success: false)`. Cancel exits via `run()`'s defer
///   block, which calls `unloadModel` (frees ~5GB) and gracefully completes
///   the BG task.
/// - **Foreground first warning**: pause + log entry. Gives the user a
///   chance to read the message and decide whether to resume.
/// - **Foreground second warning within 30s**: escalate to cancel. Sustained
///   pressure that pause didn't relieve will eventually jetsam us anyway —
///   cancel preserves the terminal status (`.cancelled`) instead of losing
///   the run silently.
nonisolated struct MemoryWarningThrottle {
  /// Window within which a second warning escalates to cancel.
  static let escalationWindow: TimeInterval = 30

  enum Decision: Equatable {
    case ignore
    case pauseAndLog
    case cancelDueToBackground
    case cancelDueToEscalation
  }

  private var firstWarningAt: Date?
  private var warningCount: Int = 0

  mutating func decide(isActive: Bool, isPaused: Bool, now: Date) -> Decision {
    if isPaused { return .ignore }
    if !isActive { return .cancelDueToBackground }

    if let first = firstWarningAt, now.timeIntervalSince(first) <= Self.escalationWindow {
      warningCount += 1
    } else {
      warningCount = 1
      firstWarningAt = now
    }
    return warningCount >= 2 ? .cancelDueToEscalation : .pauseAndLog
  }

  /// Clears the throttle state. Call when the user resumes after a pause so
  /// a subsequent warning doesn't immediately escalate (the previous pressure
  /// is presumed to have subsided).
  mutating func reset() {
    warningCount = 0
    firstWarningAt = nil
  }
}
