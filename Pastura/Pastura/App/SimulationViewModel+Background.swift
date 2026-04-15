import Foundation

// MARK: - Background continuation
//
// Adds iOS 26+ BGContinuedProcessingTask integration to SimulationViewModel.
// See ADR-003 for the design and safe-reload pattern.

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
        },
        onExpiration: { [weak self] in
          // System needs to stop us: pause and flush.
          Task { @MainActor [weak self] in
            await self?.handleBackgroundExpiration()
          }
        }
      )
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
  /// `isPaused` is intentionally NOT set here: that flag is reserved for the
  /// user-initiated pause button. Scene-phase handling goes through the
  /// SuspendController path end-to-end.
  func handleScenePhaseBackground() {
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
  }

  // MARK: - Private: BG task callbacks

  /// Called when BG task activates. The in-flight `generate` (if any) is
  /// parked in `awaitResume()` by now — `handleScenePhaseBackground` requested
  /// suspend before the app was backgrounded. Reload to CPU safely, then
  /// `resume()` so the parked generate retries on CPU.
  fileprivate func handleBackgroundActivation() async {
    guard isRunning, !isCompleted, !isCancelled else {
      backgroundManager?.completeTask(success: true)
      return
    }
    await switchToCPUInference()
    suspendController?.resume()
  }

  /// Called when the system expires the BG task (resource/time pressure).
  ///
  /// Intentionally does NOT call `resume()` — the paused SuspendController
  /// state holds until `scenePhase = .active` takes over. Step 15 will also
  /// flip from `setTaskCompleted(false)` to a no-resume contract on
  /// expiration; for now we only complete the task.
  fileprivate func handleBackgroundExpiration() async {
    backgroundManager?.completeTask(success: false)
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
    guard let llama = currentLLM as? LlamaCppService else { return }
    isReloadingModel = true
    defer { isReloadingModel = false }
    do {
      try await llama.reloadModel(gpuAcceleration: .none)
      isOnCPU = true
    } catch {
      errorMessage = "Failed to switch to CPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }

  /// Reloads the model on GPU.
  ///
  /// Same quiescence contract as `switchToCPUInference`: the FG return handler
  /// calls `requestSuspend` before this so any CPU generate is parked.
  fileprivate func switchToGPUInference() async {
    guard let llama = currentLLM as? LlamaCppService else { return }
    isReloadingModel = true
    defer { isReloadingModel = false }
    do {
      try await llama.reloadModel(gpuAcceleration: .full)
      isOnCPU = false
    } catch {
      errorMessage = "Failed to switch to GPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }
}
