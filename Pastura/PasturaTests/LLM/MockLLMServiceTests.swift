import Testing

@testable import Pastura

struct MockLLMServiceTests {
  // MARK: - Basic sequence behavior

  @Test func returnsResponsesInSequence() async throws {
    let service = MockLLMService(responses: ["first", "second", "third"])
    try await service.loadModel()

    let result1 = try await service.generate(system: "sys", user: "u1")
    let result2 = try await service.generate(system: "sys", user: "u2")
    let result3 = try await service.generate(system: "sys", user: "u3")

    #expect(result1 == "first")
    #expect(result2 == "second")
    #expect(result3 == "third")
  }

  // MARK: - Not loaded throws

  @Test func throwsNotLoadedBeforeLoadModel() async {
    let service = MockLLMService(responses: ["response"])
    await #expect(throws: LLMError.self) {
      try await service.generate(system: "sys", user: "user")
    }
  }

  // MARK: - Load/unload lifecycle

  @Test func loadAndUnloadLifecycle() async throws {
    let service = MockLLMService(responses: [])
    #expect(!service.isModelLoaded)

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Exhausted responses throws

  @Test func throwsWhenResponsesExhausted() async throws {
    let service = MockLLMService(responses: ["only"])
    try await service.loadModel()

    _ = try await service.generate(system: "sys", user: "u1")

    await #expect(throws: LLMError.self) {
      try await service.generate(system: "sys", user: "u2")
    }
  }

  // MARK: - Generate call count

  @Test func tracksGenerateCallCount() async throws {
    let service = MockLLMService(responses: ["a", "b"])
    try await service.loadModel()

    #expect(service.generateCallCount == 0)
    _ = try await service.generate(system: "s", user: "u")
    #expect(service.generateCallCount == 1)
    _ = try await service.generate(system: "s", user: "u")
    #expect(service.generateCallCount == 2)
  }

  // MARK: - Captured prompts

  @Test func capturesPrompts() async throws {
    let service = MockLLMService(responses: ["r"])
    try await service.loadModel()

    _ = try await service.generate(system: "system prompt", user: "user prompt")

    #expect(service.capturedPrompts.count == 1)
    #expect(service.capturedPrompts[0].system == "system prompt")
    #expect(service.capturedPrompts[0].user == "user prompt")
  }

  // MARK: - Reset

  @Test func resetRewindsState() async throws {
    let service = MockLLMService(responses: ["a", "b"])
    try await service.loadModel()

    _ = try await service.generate(system: "s", user: "u")
    #expect(service.generateCallCount == 1)

    service.reset()
    #expect(service.generateCallCount == 0)
    #expect(service.capturedPrompts.isEmpty)

    let result = try await service.generate(system: "s", user: "u")
    #expect(result == "a")
  }

  // MARK: - Conforms to LLMService

  @Test func conformsToLLMService() {
    let service: any LLMService = MockLLMService(responses: [])
    #expect(service is MockLLMService)
  }

  // MARK: - attachSuspendController default

  @Test func attachSuspendControllerDefaultIsNoOp() async throws {
    // Default protocol extension provides a no-op for backends that don't
    // support suspend (Mock, Ollama). Calling it must be safe before/after
    // load and must not affect generate behaviour.
    let service: any LLMService = MockLLMService(responses: ["only"])
    await service.attachSuspendController(SuspendController())
    try await service.loadModel()
    await service.attachSuspendController(nil)

    let result = try await service.generate(system: "s", user: "u")
    #expect(result == "only")
  }
}
