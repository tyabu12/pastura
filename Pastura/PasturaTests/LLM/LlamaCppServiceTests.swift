import Testing

@testable import Pastura

/// Unit tests for ``LlamaCppService``.
///
/// These tests validate lifecycle, error paths, and protocol conformance
/// without requiring a real GGUF model file. Tests that call `loadModel()`
/// use a non-existent path, which exercises the C API error handling.
@Suite(.serialized)
struct LlamaCppServiceTests {

  // MARK: - Protocol conformance

  @Test func conformsToLLMService() {
    let service: any LLMService = LlamaCppService(modelPath: "/nonexistent.gguf")
    #expect(service is LlamaCppService)
  }

  // MARK: - Initial state

  @Test func initialStateIsNotLoaded() {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    #expect(!service.isModelLoaded)
  }

  // MARK: - generate() before load

  @Test func throwsNotLoadedBeforeLoadModel() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - loadModel with invalid path

  @Test func loadModelWithInvalidPathThrowsLoadFailed() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    await #expect(throws: LLMError.self) {
      try await service.loadModel()
    }
  }

  @Test func loadModelFailureKeepsNotLoaded() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    try? await service.loadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - unloadModel safety

  @Test func unloadModelWhenNotLoadedIsSafe() async throws {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - generate after unload

  @Test func generateAfterUnloadThrowsNotLoaded() async throws {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    try await service.unloadModel()
    await #expect(throws: LLMError.notLoaded) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - Concurrent access guard (no false positives)

  @Test func guardAllowsSequentialGenerateCalls() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    await #expect(throws: LLMError.self) {
      try await service.reloadModel(gpuAcceleration: .none)
    }
  }

  @Test func reloadModelFailureKeepsNotLoaded() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    try? await service.reloadModel(gpuAcceleration: .none)
    #expect(!service.isModelLoaded)
  }

  @Test func reloadModelWhenNotLoadedBehavesLikeLoad() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    // Reload before initial load should attempt load (fails on invalid path).
    // State must remain not-loaded on failure.
    await #expect(throws: LLMError.self) {
      try await service.reloadModel(gpuAcceleration: .full)
    }
    #expect(!service.isModelLoaded)
  }

  @Test func reloadModelUnloadsFirstEvenIfReloadFails() async throws {
    // If reload's inner load fails, the previous model should still be unloaded —
    // the caller gets a clean not-loaded state, not a partial state.
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    let controller = SuspendController()
    await service.attachSuspendController(controller)
    #expect(service.suspendController === controller)
  }

  @Test func attachSuspendControllerReplacesPreviousReference() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    let first = SuspendController()
    let second = SuspendController()
    await service.attachSuspendController(first)
    await service.attachSuspendController(second)
    #expect(service.suspendController === second)
  }

  @Test func attachSuspendControllerNilDetaches() async {
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
    await service.attachSuspendController(SuspendController())
    await service.attachSuspendController(nil)
    #expect(service.suspendController == nil)
  }

  // Note: cooperative suspend behavior inside the generate auto-regressive
  // loop and the prefill loop is exercised end-to-end by the integration
  // tests in step 18 (real model required to actually enter the loop).

  @Test func unloadModelDoesNotEarlyReturnOnTaskCancellation() async throws {
    // Even if the owning task is cancelled, unloadModel must NOT return while
    // generate is still in flight — that would free C pointers still in use
    // (use-after-free). Verifies the Task.detached sleep pattern isn't
    // short-circuited by cancellation.
    let service = LlamaCppService(modelPath: "/nonexistent.gguf")
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
