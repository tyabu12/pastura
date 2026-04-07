import Foundation
import Testing

@testable import Pastura

// MARK: - URLProtocol Mock

/// Intercepts URLSession requests for testing without a live Ollama server.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  // Safe: tests run serialized via @Suite(.serialized), no concurrent access
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override static func canInit(with request: URLRequest) -> Bool {
    true
  }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      client?.urlProtocolDidFinishLoading(self)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

// MARK: - Tests

@Suite(.serialized)
struct OllamaServiceTests {
  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func makeService(session: URLSession) -> OllamaService {
    OllamaService(
      baseURL: URL(string: "http://localhost:11434")!,
      modelName: "gemma4:e2b",
      session: session
    )
  }

  private func makeSuccessResponse(content: String) -> (HTTPURLResponse, Data) {
    let body: [String: Any] = [
      "choices": [
        [
          "message": [
            "content": content
          ]
        ]
      ]
    ]
    // swiftlint:disable:next force_try
    let data = try! JSONSerialization.data(withJSONObject: body)
    let response = HTTPURLResponse(
      url: URL(string: "http://localhost:11434/v1/chat/completions")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    return (response, data)
  }

  // MARK: - Request construction

  @Test func constructsCorrectRequestURL() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
      capturedRequest = request
      return self.makeSuccessResponse(content: "test")
    }

    _ = try await service.generate(system: "sys", user: "usr")

    let url = try #require(capturedRequest?.url)
    #expect(url.absoluteString == "http://localhost:11434/v1/chat/completions")
    #expect(capturedRequest?.httpMethod == "POST")
  }

  @Test func requestBodyContainsCorrectFields() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    var capturedBody: [String: Any]?
    MockURLProtocol.requestHandler = { request in
      // httpBody may be nil when URLSession converts it to a stream
      let data: Data?
      if let body = request.httpBody {
        data = body
      } else if let stream = request.httpBodyStream {
        stream.open()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var accumulated = Data()
        while stream.hasBytesAvailable {
          let read = stream.read(&buffer, maxLength: bufferSize)
          if read > 0 {
            accumulated.append(buffer, count: read)
          }
        }
        stream.close()
        data = accumulated
      } else {
        data = nil
      }
      if let data {
        capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      }
      return self.makeSuccessResponse(content: "test")
    }

    _ = try await service.generate(system: "system prompt", user: "user prompt")

    let body = try #require(capturedBody)
    #expect(body["model"] as? String == "gemma4:e2b")
    #expect(body["temperature"] as? Double == 0.8)
    #expect(body["max_tokens"] as? Int == 1000)

    let messages = try #require(body["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] == "system")
    #expect(messages[0]["content"] == "system prompt")
    #expect(messages[1]["role"] == "user")
    #expect(messages[1]["content"] == "user prompt")
  }

  // MARK: - Successful response

  @Test func decodesSuccessfulResponse() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    MockURLProtocol.requestHandler = { _ in
      self.makeSuccessResponse(content: #"{"statement": "hello"}"#)
    }

    let result = try await service.generate(system: "sys", user: "usr")
    #expect(result == #"{"statement": "hello"}"#)
  }

  // MARK: - Error handling

  @Test func throwsNotLoadedBeforeLoadModel() async {
    let session = makeSession()
    let service = makeService(session: session)

    await #expect(throws: LLMError.self) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  @Test func maps4xxToGenerationFailed() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data())
    }

    await #expect(throws: LLMError.self) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  @Test func maps5xxToNetworkError() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data())
    }

    await #expect(throws: LLMError.self) {
      try await service.generate(system: "sys", user: "usr")
    }
  }

  // MARK: - Load/unload lifecycle

  @Test func loadAndUnloadLifecycle() async throws {
    let session = makeSession()
    let service = makeService(session: session)

    #expect(!service.isModelLoaded)
    try await service.loadModel()
    #expect(service.isModelLoaded)
    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Conforms to LLMService

  @Test func conformsToLLMService() {
    let session = makeSession()
    let service: any LLMService = makeService(session: session)
    #expect(service is OllamaService)
  }
}
