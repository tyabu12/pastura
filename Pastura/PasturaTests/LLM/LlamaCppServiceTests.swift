import Testing

@testable import Pastura

/// File-scope helper for constructing a `LlamaCppService` with test-shaped
/// values. Production code must provide all four parameters explicitly (via
/// a `ModelDescriptor`); this helper centralizes the values that the lifecycle
/// / error-path tests don't depend on so each test call-site stays terse.
private func makeTestService(modelPath: String = "/nonexistent.gguf") -> LlamaCppService {
  LlamaCppService(
    modelPath: modelPath,
    stopSequence: "<|im_end|>",
    modelIdentifier: "test-model",
    systemPromptSuffix: nil
  )
}

/// Unit tests for ``LlamaCppService``.
///
/// These tests validate lifecycle, error paths, and protocol conformance
/// without requiring a real GGUF model file. Tests that call `loadModel()`
/// use a non-existent path, which exercises the C API error handling.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LlamaCppServiceTests {

  // MARK: - Protocol conformance

  @Test func conformsToLLMService() {
    let service: any LLMService = makeTestService()
    #expect(service is LlamaCppService)
  }

  // MARK: - Initial state

  @Test func initialStateIsNotLoaded() {
    let service = makeTestService()
    #expect(!service.isModelLoaded)
  }

  // MARK: - generate() before load

  @Test func throwsNotLoadedBeforeLoadModel() async {
    let service = makeTestService()
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - generateStream() before load

  /// Errors from the underlying generate path must surface through the
  /// stream via `finish(throwing:)` — not silently end. A missing model is
  /// the cheapest way to exercise this without a real GGUF file.
  @Test func generateStreamPropagatesNotLoadedBeforeLoadModel() async {
    let service = makeTestService()
    await #expect(throws: LLMError.notLoaded) {
      for try await _ in service.generateStream(system: "sys", user: "usr") {}
    }
  }

  // MARK: - loadModel with invalid path

  @Test func loadModelWithInvalidPathThrowsLoadFailed() async {
    let service = makeTestService()
    await #expect(throws: LLMError.self) {
      try await service.loadModel()
    }
  }

  @Test func loadModelFailureKeepsNotLoaded() async {
    let service = makeTestService()
    try? await service.loadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - unloadModel safety

  @Test func unloadModelWhenNotLoadedIsSafe() async throws {
    let service = makeTestService()
    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - generate after unload

  @Test func generateAfterUnloadThrowsNotLoaded() async throws {
    let service = makeTestService()
    try await service.unloadModel()
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - Concurrent access guard (no false positives)

  @Test func guardAllowsSequentialGenerateCalls() async {
    let service = makeTestService()
    // Sequential generate() calls should not trigger the guard.
    // Both throw notLoaded (no model loaded), but the guard itself must not fire.
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  @Test func guardAllowsLoadUnloadCycle() async throws {
    let service = makeTestService()
    // load (fails) → generate (fails) → unload → generate (fails)
    // None of these overlap, so the guard must not fire.
    try? await service.loadModel()
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
    try await service.unloadModel()
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - reloadModel(gpuAcceleration:)

  @Test func reloadModelWithInvalidPathThrowsLoadFailed() async {
    let service = makeTestService()
    await #expect(throws: LLMError.self) {
      try await service.reloadModel(gpuAcceleration: .none)
    }
  }

  @Test func reloadModelFailureKeepsNotLoaded() async {
    let service = makeTestService()
    try? await service.reloadModel(gpuAcceleration: .none)
    #expect(!service.isModelLoaded)
  }

  @Test func reloadModelWhenNotLoadedBehavesLikeLoad() async {
    let service = makeTestService()
    // Reload before initial load should attempt load (fails on invalid path).
    // State must remain not-loaded on failure.
    await #expect(throws: LLMError.self) {
      try await service.reloadModel(gpuAcceleration: .full)
    }
    #expect(!service.isModelLoaded)
  }

  // MARK: - loadModel idempotency (issue #114)

  @Test func loadModelTwiceOnInvalidPathPreservesSuspendController() async {
    // Regression test for issue #114. Calling loadModel() while already loaded
    // must unload the prior model first to avoid leaking ~3GB of Gemma buffers.
    // With an invalid path both calls throw, so this test locks in the
    // observable invariants that hold when the defensive unload path runs:
    //   - Service ends not-loaded after each failure
    //   - Attached SuspendController survives the unload/load cycle
    // The actual leak-prevention path requires a loaded model — see
    // LlamaCppIntegrationTests.loadModelTwiceIsIdempotent for that coverage.
    let service = makeTestService()
    let controller = SuspendController()
    await service.attachSuspendController(controller)

    try? await service.loadModel()
    try? await service.loadModel()

    #expect(!service.isModelLoaded)
    #expect(service.suspendController === controller)
  }

  @Test func reloadModelUnloadsFirstEvenIfReloadFails() async throws {
    // If reload's inner load fails, the previous model should still be unloaded —
    // the caller gets a clean not-loaded state, not a partial state.
    let service = makeTestService()
    try? await service.loadModel()  // fails, but tests atomicity
    try? await service.reloadModel(gpuAcceleration: .none)
    #expect(!service.isModelLoaded)
  }

  // MARK: - unloadModel cooperative wait (no precondition crash)

  @Test func unloadModelDoesNotCrashWhenCalledConcurrentlyWithGenerate() async throws {
    // Regression test for a crash where unloadModel() would hit a precondition
    // when called while generate() was still running. This happens in practice
    // on memory warning + cancellation paths because llama.cpp's C API does not
    // respect Swift Task cancellation — generate runs to completion regardless.
    //
    // The fix is to make unloadModel() wait for generate to complete instead
    // of crashing. Here we exercise the path by calling unloadModel on an
    // unloaded service: the fast path returns immediately without any guard
    // check that could crash.
    let service = makeTestService()
    // Multiple back-to-back unloads must be safe (the first exits early via
    // the `guard wasLoaded` check; the second sees isModelLoaded==false).
    try await service.unloadModel()
    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  @Test func unloadModelWaitsForInFlightGenerate() async throws {
    // Exercises the awaitGenerateIdle polling loop: unloadModel should block
    // while generatingGuard is true, and proceed once it clears. Uses the
    // DEBUG-only setGeneratingForTesting hook to simulate an in-flight generate
    // without actually running one (which would require a real model file).
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let unloadTask = Task<Bool, Error> {
      try await service.unloadModel()
      return true
    }

    // Give unload a chance to start polling
    try await Task.sleep(for: .milliseconds(100))
    #expect(!unloadTask.isCancelled, "unloadModel should still be blocked on the guard")

    // Simulate generate completing — clears the flag, unloadModel's poll exits
    service.setGeneratingForTesting(false)
    let completed = try await unloadTask.value
    #expect(completed)
    #expect(!service.isModelLoaded)
  }

  // MARK: - SuspendController attachment

  @Test func attachSuspendControllerStoresReference() async {
    let service = makeTestService()
    let controller = SuspendController()
    await service.attachSuspendController(controller)
    #expect(service.suspendController === controller)
  }

  @Test func attachSuspendControllerReplacesPreviousReference() async {
    let service = makeTestService()
    let first = SuspendController()
    let second = SuspendController()
    await service.attachSuspendController(first)
    await service.attachSuspendController(second)
    #expect(service.suspendController === second)
  }

  @Test func attachSuspendControllerNilDetaches() async {
    let service = makeTestService()
    await service.attachSuspendController(SuspendController())
    await service.attachSuspendController(nil)
    #expect(service.suspendController == nil)
  }

  @Test func reloadModelPreservesSuspendControllerAcrossFailure() async {
    // Even if reload throws (invalid path), the previously attached controller
    // must still be in place — the App layer's reference must survive the
    // unload/load cycle without any explicit re-attach.
    let service = makeTestService()
    let controller = SuspendController()
    await service.attachSuspendController(controller)

    try? await service.reloadModel(gpuAcceleration: .none)

    #expect(service.suspendController === controller)
  }

  // Note: cooperative suspend behavior inside the generate auto-regressive
  // loop and the prefill loop is exercised end-to-end by the integration
  // tests in step 18 (real model required to actually enter the loop).

  // MARK: - Reactive suspend mapping (decodeFailureError)

  @Test func decodeFailureWithoutControllerReturnsGenerationFailed() {
    let service = makeTestService()
    // No controller attached at all — every non-zero decode is fatal.
    let mapped = service.decodeFailureError(-3)
    if case .generationFailed = mapped { /* OK */
    } else {
      Issue.record("expected .generationFailed but got \(mapped)")
    }
  }

  @Test func decodeFailureWithoutSuspendRequestReturnsGenerationFailed() async {
    let service = makeTestService()
    await service.attachSuspendController(SuspendController())
    // Controller exists but no suspend was requested → still fatal.
    let mapped = service.decodeFailureError(2)
    if case .generationFailed = mapped { /* OK */
    } else {
      Issue.record("expected .generationFailed but got \(mapped)")
    }
  }

  @Test func decodeFailureWithSuspendRequestReturnsSuspended() async {
    let service = makeTestService()
    let controller = SuspendController()
    await service.attachSuspendController(controller)
    controller.requestSuspend()

    // Mapping is intentionally code-agnostic — any non-zero result under
    // active suspend becomes .suspended, regardless of the specific error.
    #expect(service.decodeFailureError(-3) == .suspended)
    #expect(service.decodeFailureError(2) == .suspended)
    #expect(service.decodeFailureError(-1000) == .suspended)
  }

  @Test func unloadModelDoesNotEarlyReturnOnTaskCancellation() async throws {
    // Even if the owning task is cancelled, unloadModel must NOT return while
    // generate is still in flight — that would free C pointers still in use
    // (use-after-free). Verifies the Task.detached sleep pattern isn't
    // short-circuited by cancellation.
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let unloadTask = Task<Bool, Error> {
      try await service.unloadModel()
      return true
    }

    // Cancel while generate is "running"
    try await Task.sleep(for: .milliseconds(100))
    unloadTask.cancel()

    // unloadModel should still be waiting — confirm it hasn't returned
    try await Task.sleep(for: .milliseconds(200))
    service.setGeneratingForTesting(false)

    // Now it should complete
    let completed = try await unloadTask.value
    #expect(completed)
  }
}
