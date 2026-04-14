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
  /// Immediately pauses (synchronous safety) so any in-flight generate finishes
  /// before a potential BG task activation triggers a model reload.
  func handleScenePhaseBackground() {
    guard isRunning else { return }
    isPaused = true
  }

  /// Called by `SimulationView` when `scenePhase` becomes `.active`.
  /// If we switched to CPU for BG, switch back to GPU. Always completes any BG task.
  func handleScenePhaseForeground() async {
    guard isRunning else { return }

    // If we're running on CPU, switch back to GPU before resuming
    if isOnCPU {
      await switchToGPUInference()
    }

    // Complete the BG task — we're in foreground now
    backgroundManager?.completeTask(success: true)

    // Resume simulation
    isPaused = false

    // After a FG return, the previously scheduled BG task is consumed. Reset
    // the toggle so the user can explicitly re-arm for the next BG transition.
    // TODO: persist title/subtitle to auto-rearm without user re-tap (#84 follow-up).
    if isBackgroundContinuationEnabled {
      isBackgroundContinuationEnabled = false
    }
  }

  // MARK: - Private: BG task callbacks

  /// Called when BG task activates. Switch inference to CPU and resume.
  fileprivate func handleBackgroundActivation() async {
    guard isRunning, !isCompleted, !isCancelled else {
      backgroundManager?.completeTask(success: true)
      return
    }
    await switchToCPUInference()
    // Resume on CPU
    isPaused = false
  }

  /// Called when the system expires the BG task (resource/time pressure).
  fileprivate func handleBackgroundExpiration() async {
    isPaused = true
    backgroundManager?.completeTask(success: false)
  }

  /// Waits for inference to be idle, then reloads the model on CPU.
  fileprivate func switchToCPUInference() async {
    guard let llama = currentLLM as? LlamaCppService else { return }
    await pauseAndAwaitConfirmation()
    do {
      try await llama.reloadModel(gpuAcceleration: .none)
      isOnCPU = true
    } catch {
      errorMessage = "Failed to switch to CPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }

  /// Waits for inference to be idle, then reloads the model on GPU.
  fileprivate func switchToGPUInference() async {
    guard let llama = currentLLM as? LlamaCppService else { return }
    await pauseAndAwaitConfirmation()
    do {
      try await llama.reloadModel(gpuAcceleration: .full)
      isOnCPU = false
    } catch {
      errorMessage = "Failed to switch to GPU: \(error.localizedDescription)"
      cancelSimulation()
    }
  }
}
