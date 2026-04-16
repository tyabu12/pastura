// BGContinuedProcessingTask is not Sendable-annotated in SDK yet (iOS 26.4);
// preconcurrency downgrades the warnings to allow us to store the task reference
// under our own lock discipline.
@preconcurrency import BackgroundTasks
import Foundation
import os

/// Manages BGContinuedProcessingTask lifecycle for background simulation continuation.
///
/// This is iOS 26+ only — `BGContinuedProcessingTask` is a new API that lets an app
/// continue CPU-bound work in the background when the user has explicitly opted in
/// (e.g., by tapping a button). The system shows a Live Activity-like UI with
/// progress and a Stop button.
///
/// Flow:
/// 1. App launch: `register()` registers the task handler with `BGTaskScheduler`.
/// 2. User taps "Background continuation" toggle in the simulation view.
/// 3. VM calls `scheduleRequest(...)` with the activation callback.
/// 4. App is backgrounded; the system activates the task and calls the registered
///    handler, which invokes `onActivation`.
/// 5. VM handles activation: reload model on CPU, resume the suspended generate.
/// 6. VM periodically calls `updateProgress(...)` so the system doesn't auto-expire.
/// 7. On foreground return / completion, VM calls `completeTask(success:)`.
/// 8. On expiration (resource/time pressure), the manager's internal expiration
///    handler synchronously calls `setTaskCompleted(success: false)` and clears
///    state — the VM is NOT notified. This prevents any expiration-triggered
///    resume() from racing with the normal scenePhase-driven resume path.
///
/// - Important: All methods are no-ops before iOS 26. Check `isSupported` before use.
nonisolated public final class BackgroundSimulationManager: @unchecked Sendable {
  // @unchecked Sendable: internal state protected by OSAllocatedUnfairLock.

  /// The BG task identifier, must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
  public static let taskIdentifier = "com.tyabu12.Pastura.simulation-continuation"

  private let logger = Logger(subsystem: "com.pastura", category: "BGSimManager")
  private let state = OSAllocatedUnfairLock(initialState: State())

  // @unchecked Sendable: `activeTask` is a non-Sendable system type (BGContinuedProcessingTask),
  // but all access is serialized through the enclosing OSAllocatedUnfairLock.
  private struct State: @unchecked Sendable {
    // Use `Any` to avoid compile-time dependency on iOS 26 types in the struct —
    // actual type is `BGContinuedProcessingTask` when set (only on iOS 26+).
    var activeTask: Any?
    var onActivation: (@Sendable () -> Void)?
  }

  public init() {}

  /// Whether background continuation is supported on this device and OS.
  public var isSupported: Bool {
    if #available(iOS 26, *) {
      return true
    }
    return false
  }

  /// Registers the BG task handler with the system.
  ///
  /// Must be called once during app launch, before the first scene activates.
  /// No-op on iOS < 26.
  public func register() {
    guard #available(iOS 26, *) else { return }
    let registered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.taskIdentifier,
      using: nil
    ) { [weak self] task in
      self?.handleTaskLaunch(task)
    }
    if !registered {
      logger.error("Failed to register BG task handler for \(Self.taskIdentifier)")
    }
  }

  /// Schedules a background continuation request.
  ///
  /// Must be called in response to an explicit user action (BGContinuedProcessingTask
  /// requires user initiation). `onActivation` is invoked when the system
  /// activates the task after the app backgrounds.
  ///
  /// Expiration is handled internally: when the system expires the task, the
  /// manager synchronously calls `setTaskCompleted(success: false)` and clears
  /// state. The caller is **not** notified — the SuspendController remains
  /// paused until `scenePhase = .active` triggers the foreground-resume path.
  /// This avoids any possibility of expiration racing with resume.
  ///
  /// - Parameters:
  ///   - title: Short title shown in the system UI (e.g., "Simulation running").
  ///   - subtitle: Subtitle with more detail (e.g., scenario title).
  ///   - onActivation: Called when the task becomes active after backgrounding.
  ///     This is where the VM should switch from GPU to CPU inference.
  /// - Throws: `BGTaskScheduler.Error` if the request is rejected.
  @available(iOS 26, *)
  public func scheduleRequest(
    title: String,
    subtitle: String,
    onActivation: @escaping @Sendable () -> Void
  ) throws {
    state.withLock { state in
      state.onActivation = onActivation
    }

    let request = BGContinuedProcessingTaskRequest(
      identifier: Self.taskIdentifier,
      title: title,
      subtitle: subtitle
    )
    // Fail fast if the system can't start it right away — we don't want
    // a queued task activating unexpectedly long after the user tapped the toggle.
    request.strategy = .fail

    do {
      try BGTaskScheduler.shared.submit(request)
      logger.info("Scheduled BG continuation request: \(title)")
    } catch {
      // Clear the callback we just stored so a retry with different callbacks
      // doesn't leave a stale closure around.
      state.withLock { state in
        state.onActivation = nil
      }
      throw error
    }
  }

  /// Updates the progress shown in the system UI.
  ///
  /// Must be called periodically while the task is active, or the system will
  /// auto-expire the task for inactivity. Call after each inference completes.
  ///
  /// - Parameters:
  ///   - completed: Completed unit count (e.g., inferences done).
  ///   - total: Total unit count (e.g., estimated total inferences).
  @available(iOS 26, *)
  public func updateProgress(completed: Int64, total: Int64) {
    state.withLock { state in
      guard let task = state.activeTask as? BGContinuedProcessingTask else { return }
      task.progress.totalUnitCount = total
      task.progress.completedUnitCount = completed
    }
  }

  /// Marks the currently active background task as complete.
  ///
  /// Safe to call even if no task is active (no-op). Clears any stored callbacks.
  ///
  /// - Parameter success: Whether the work completed successfully.
  public func completeTask(success: Bool) {
    guard #available(iOS 26, *) else { return }
    let task = state.withLock { state -> BGContinuedProcessingTask? in
      let active = state.activeTask as? BGContinuedProcessingTask
      state.activeTask = nil
      state.onActivation = nil
      return active
    }
    task?.setTaskCompleted(success: success)
    if task != nil {
      logger.info("Completed BG continuation task (success: \(success))")
    }
  }

  /// Cancels any pending (not-yet-activated) background request.
  ///
  /// Use when the user disables the BG continuation toggle before the app
  /// is backgrounded.
  public func cancelPendingRequest() {
    guard #available(iOS 26, *) else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    state.withLock { state in
      state.onActivation = nil
    }
  }

  // MARK: - Private

  @available(iOS 26, *)
  private func handleTaskLaunch(_ task: BGTask) {
    guard let continuedTask = task as? BGContinuedProcessingTask else {
      logger.error("BG task handler received unexpected task type")
      task.setTaskCompleted(success: false)
      return
    }

    // Expiration handling is fully contained here: we complete the task
    // synchronously and clear state, with no out-bound callback. The VM's
    // SuspendController stays paused until scenePhase = .active drives a
    // normal foreground resume. Rationale: late-firing expiration must not
    // race with — or be mistaken for — a normal resume, so we deliberately
    // give the VM no expiration hook that could call `resume()`.
    continuedTask.expirationHandler = { [weak self] in
      guard let self else { return }
      self.logger.warning("BG continuation task expiring")
      self.state.withLock { state in
        state.activeTask = nil
        state.onActivation = nil
      }
      continuedTask.setTaskCompleted(success: false)
    }

    let onActivation = state.withLock { state -> (@Sendable () -> Void)? in
      state.activeTask = continuedTask
      return state.onActivation
    }
    logger.info("BG continuation task activated")
    onActivation?()
  }
}
