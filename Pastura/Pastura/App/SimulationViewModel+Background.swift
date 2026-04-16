import Foundation
import os

// MARK: - Background continuation
//
// Adds iOS 26+ BGContinuedProcessingTask integration to SimulationViewModel.
// See ADR-003 for the design and safe-reload pattern.
//
// Suspend/resume semantics (Step 13 / 14 / 15 / 16):
// - `handleWillResignActive` is the earliest suspend signal — fires before
//   scenePhase = .background, giving the GPU loop a head start on exiting
//   ahead of the iOS Metal-deny window.
// - `handleScenePhaseBackground` is a backstop to `handleWillResignActive`
//   and is toggle-agnostic: it always calls `suspendController?.requestSuspend()`.
//   The difference between Toggle ON and Toggle OFF manifests at BG task
//   activation time, not at suspend time.
// - Toggle ON: `handleBackgroundActivation` fires (because a BG request was
//   scheduled), reloads the model on CPU, then `resume()`s so the parked
//   generate retries on CPU.
// - Toggle OFF: no BG task activation. The parked generate stays parked
//   until `handleScenePhaseForeground` calls `resume()`. Partial KV-cache
//   cleanup on a Metal-induced decode failure is handled by the LLM layer
//   (`LlamaCppService.decodeFailureError` → `llama_memory_clear`) so the
//   retry on GPU starts from a clean state.
// - BG task expiration is deliberately NOT routed through the VM. The
//   manager completes the task synchronously and the SuspendController stays
//   paused until scenePhase = .active resumes it normally. See Step 15.

extension SimulationViewModel {

  /// Enables background continuation and schedules a BG task request.
  /// Must be called in response to an explicit user action (toggle tap).
  ///
  /// - Parameters:
  ///   - title: Shown in the system BG UI (e.g., "Simulation running").
  ///   - subtitle: Subtitle with more detail (e.g., scenario title).
  @available(iOS 26, *)
  func enableBackgroundContinuation(title: String, subtitle: String) {
    guard canEnableBackgroundContinuation else { return }
    guard let bgManager = backgroundManager else { return }

    do {
      try bgManager.scheduleRequest(
        title: title,
        subtitle: subtitle,
        onActivation: { [weak self] in
          // BG task activated: app is in background, switch to CPU inference.
          Task { @MainActor [weak self] in
            await self?.handleBackgroundActivation()
          }
        }
      )
      // Expiration is handled entirely inside BackgroundSimulationManager —
      // the VM intentionally has no expiration hook. Late-firing expiration
      // must not race with (or be mistaken for) a normal resume, so we route
      // all resume() calls through scenePhase = .active only.
      isBackgroundContinuationEnabled = true
    } catch {
      errorMessage = "Failed to enable background continuation: \(error.localizedDescription)"
      isBackgroundContinuationEnabled = false
    }
  }

  /// Disables background continuation and cancels any pending BG request.
  func disableBackgroundContinuation() {
    backgroundManager?.cancelPendingRequest()
    isBackgroundContinuationEnabled = false
  }

  /// Called by `SimulationView` when `scenePhase` becomes `.background`.
  ///
  /// Signals the SuspendController so an in-flight `generate` exits within
  /// milliseconds — iOS denies Metal GPU work from background within the same
  /// window, so waiting for the phase-boundary checkpoint would race the OS
  /// and trigger a Metal decode failure.
  ///
  /// Serves as a backstop to `handleWillResignActive` for cases where the
  /// earlier notification was missed (or never fires, e.g. direct
  /// `.active → .background` transitions on iPad split view). `requestSuspend`
  /// is idempotent so the double call is cheap.
  ///
  /// `isPaused` is intentionally NOT set here: that flag is reserved for the
  /// user-initiated pause button. Scene-phase handling goes through the
  /// SuspendController path end-to-end.
  func handleScenePhaseBackground() {
    lifecycleLogger.info(
      "scenePhase=.background: isRunning=\(self.isRunning), isOnCPU=\(self.isOnCPU), bgEnabled=\(self.isBackgroundContinuationEnabled)"
    )
    guard isRunning else { return }
    suspendController?.requestSuspend()
  }

  /// Called by `SimulationView` on `UIApplication.willResignActiveNotification`,
  /// which fires earlier than `scenePhase = .background`.
  ///
  /// Requesting suspend here gives the in-flight `generate` a head start on
  /// exiting the GPU loop before iOS begins denying Metal work. If the app
  /// returns to `.active` without ever going to `.background` (e.g. a
  /// Control Center pull), `handleScenePhaseForeground` will `resume()` the
  /// controller and the parked generate retries on GPU — at most one wasted
  /// inference, which is an acceptable price for robust BG handling.
  func handleWillResignActive() {
    lifecycleLogger.info("willResignActive: isRunning=\(self.isRunning), isOnCPU=\(self.isOnCPU)")
    guard isRunning else { return }
    suspendController?.requestSuspend()
  }

  /// Called by `SimulationView` when `scenePhase` becomes `.active`.
  ///
  /// Two paths depending on the toggle state at background time:
  ///
  /// - **Toggle ON** (`isOnCPU == true`): the BG task activated and the model
  ///   was reloaded on CPU. Re-park any CPU generate via `requestSuspend()`
  ///   so `reloadModel(.full)` can claim the sequential-access guard without
  ///   racing, swap back to GPU, then `resume()` so the parked generate
  ///   retries on GPU.
  /// - **Toggle OFF** / BG activation never fired (`isOnCPU == false`):
  ///   no model reload needed — the LLM-layer reactive path already wiped
  ///   any partial KV state when the Metal decode failed. Just `resume()`
  ///   so the parked generate retries on GPU.
  ///
  /// Safe on iOS < 26: the CPU branch never runs (isOnCPU stays false because
  /// BG activation never fires) and `backgroundManager.completeTask` no-ops.
  func handleScenePhaseForeground() async {
    lifecycleLogger.info(
      "scenePhase=.active enter: isRunning=\(self.isRunning), isOnCPU=\(self.isOnCPU), isReloadingModel=\(self.isReloadingModel)"
    )
    guard isRunning else { return }

    if isOnCPU {
      suspendController?.requestSuspend()
      await switchToGPUInference()
    }

    backgroundManager?.completeTask(success: true)

    // Wake any generate parked in `awaitResume()` so it retries on GPU.
    // Idempotent — safe when no suspend was active.
    suspendController?.resume()

    // After a FG return, the previously scheduled BG task is consumed. Reset
    // the toggle so the user can explicitly re-arm for the next BG transition.
    // TODO: persist title/subtitle to auto-rearm without user re-tap (#84 follow-up).
    if isBackgroundContinuationEnabled {
      isBackgroundContinuationEnabled = false
    }
    lifecycleLogger.info(
      "scenePhase=.active exit: isOnCPU=\(self.isOnCPU), isRunning=\(self.isRunning)"
    )
  }

  // MARK: - Private: BG task callbacks

  /// Called when BG task activates. The in-flight `generate` (if any) is
  /// parked in `awaitResume()` by now — `handleScenePhaseBackground` requested
  /// suspend before the app was backgrounded. Reload to CPU safely, then
  /// `resume()` so the parked generate retries on CPU.
  fileprivate func handleBackgroundActivation() async {
    lifecycleLogger.info(
      "BG task activation: isRunning=\(self.isRunning), isCompleted=\(self.isCompleted), isCancelled=\(self.isCancelled)"
    )
    guard isRunning, !isCompleted, !isCancelled else {
      lifecycleLogger.info("BG task activation: guard failed — completing as success")
      backgroundManager?.completeTask(success: true)
      return
    }
    await switchToCPUInference()
    lifecycleLogger.info("BG task activation: switchToCPU returned, calling resume()")
    suspendController?.resume()
  }

  /// Reloads the model on CPU.
  ///
  /// Quiescence is enforced by `reloadModel`'s internal `awaitGenerateIdle`.
  /// In the BG activation flow the in-flight generate is already parked in
  /// `awaitResume()` (because the scene-phase handler called `requestSuspend`),
  /// so idle is reached within milliseconds rather than waiting for a full
  /// inference to complete.
  ///
  /// Safe on iOS < 26: early returns if `currentLLM` isn't `LlamaCppService`.
  /// In practice this method only fires from the BG activation callback, which
  /// is only wired up when `canEnableBackgroundContinuation` is true (iOS 26+).
  fileprivate func switchToCPUInference() async {
    guard let llama = currentLLM as? LlamaCppService else {
      lifecycleLogger.info("switchToCPU: skipped (currentLLM is not LlamaCppService)")
      return
    }
    lifecycleLogger.info("switchToCPU: begin reloadModel(.none)")
    isReloadingModel = true
    defer { isReloadingModel = false }
    do {
      try await llama.reloadModel(gpuAcceleration: .none)
      isOnCPU = true
      lifecycleLogger.info("switchToCPU: success, isOnCPU=true")
    } catch {
      lifecycleLogger.error(
        "switchToCPU: failed with \(error.localizedDescription, privacy: .public)")
      errorMessage = "Failed to switch to CPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }

  /// Reloads the model on GPU.
  ///
  /// Same quiescence contract as `switchToCPUInference`: the FG return handler
  /// calls `requestSuspend` before this so any CPU generate is parked.
  fileprivate func switchToGPUInference() async {
    guard let llama = currentLLM as? LlamaCppService else {
      lifecycleLogger.info("switchToGPU: skipped (currentLLM is not LlamaCppService)")
      return
    }
    lifecycleLogger.info("switchToGPU: begin reloadModel(.full)")
    isReloadingModel = true
    defer { isReloadingModel = false }
    do {
      try await llama.reloadModel(gpuAcceleration: .full)
      isOnCPU = false
      lifecycleLogger.info("switchToGPU: success, isOnCPU=false")
    } catch {
      lifecycleLogger.error(
        "switchToGPU: failed with \(error.localizedDescription, privacy: .public)")
      errorMessage = "Failed to switch to GPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }
}
