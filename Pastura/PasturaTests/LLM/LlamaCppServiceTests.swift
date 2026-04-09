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
}
