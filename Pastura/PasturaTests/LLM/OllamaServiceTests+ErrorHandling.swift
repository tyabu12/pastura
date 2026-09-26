import Foundation
import Testing

@testable import Pastura

// Split from OllamaServiceTests.swift past its 400-line file_length cap
// (testing.md § "Splitting a Suite Across Files"). No new @Suite — these
// extend the original struct, which still owns `.serialized` ordering.
extension OllamaServiceTests {
  // MARK: - Transport vs HTTP 5xx

  @Test func transportErrorIsDistinguishableFromHTTP5xx() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    OllamaMockURLProtocol.requestHandler = { _ in
      throw URLError(.cannotConnectToHost)
    }

    do {
      _ = try await service.generate(system: "sys", user: "usr")
      Issue.record("Expected LLMError.networkError to be thrown")
    } catch {
      guard case .networkError(let description) = error as? LLMError else {
        Issue.record("Expected LLMError.networkError, got \(error)")
        return
      }
      #expect(!description.contains("HTTP "))
    }
  }

  // MARK: - invalidResponse (generate)

  @Test func generateThrowsInvalidResponseOnMalformedJSON() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    let malformed = Data("not json".utf8)
    OllamaMockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, malformed)
    }

    do {
      _ = try await service.generate(system: "sys", user: "usr")
      Issue.record("Expected LLMError.invalidResponse to be thrown")
    } catch {
      guard case .invalidResponse(let raw) = error as? LLMError else {
        Issue.record("Expected LLMError.invalidResponse, got \(error)")
        return
      }
      #expect(raw == "not json")
    }
  }

  @Test func generateThrowsInvalidResponseWhenChoicesMissing() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    OllamaMockURLProtocol.requestHandler = { _ in
      let body: [String: Any] = ["not_choices": []]
      // swiftlint:disable:next force_try
      let data = try! JSONSerialization.data(withJSONObject: body)
      let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, data)
    }

    do {
      _ = try await service.generate(system: "sys", user: "usr")
      Issue.record("Expected LLMError.invalidResponse to be thrown")
    } catch {
      guard case .invalidResponse = error as? LLMError else {
        Issue.record("Expected LLMError.invalidResponse, got \(error)")
        return
      }
    }
  }

  // MARK: - invalidResponse (generateWithMetrics)

  @Test(
    "generateWithMetrics throws invalidResponse for a bad body",
    arguments: [
      Data("not json".utf8),
      // swiftlint:disable:next force_try
      try! JSONSerialization.data(withJSONObject: ["not_choices": []])
    ]
  )
  func generateWithMetricsThrowsInvalidResponse(body: Data) async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    OllamaMockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, body)
    }

    do {
      _ = try await service.generateWithMetrics(system: "s", user: "u")
      Issue.record("Expected LLMError.invalidResponse to be thrown")
    } catch {
      guard case .invalidResponse = error as? LLMError else {
        Issue.record("Expected LLMError.invalidResponse, got \(error)")
        return
      }
    }
  }

  // MARK: - Schema → `format: "json"`

  @Test func requestBodyIncludesFormatJSONWhenSchemaProvided() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    var capturedBody: [String: Any]?
    OllamaMockURLProtocol.requestHandler = { request in
      capturedBody = OllamaServiceTests.jsonBody(of: request)
      return self.makeSuccessResponse(content: "test")
    }

    let schema = OutputSchema(fields: [.init(name: "statement", kind: .string)])
    _ = try await service.generate(system: "sys", user: "usr", schema: schema)

    let body = try #require(capturedBody)
    #expect(body["format"] as? String == "json")
  }

  @Test func requestBodyOmitsFormatWhenSchemaNil() async throws {
    let session = makeSession()
    let service = makeService(session: session)
    try await service.loadModel()

    var capturedBody: [String: Any]?
    OllamaMockURLProtocol.requestHandler = { request in
      capturedBody = OllamaServiceTests.jsonBody(of: request)
      return self.makeSuccessResponse(content: "test")
    }

    _ = try await service.generate(system: "sys", user: "usr", schema: nil)

    let body = try #require(capturedBody)
    #expect(body["format"] == nil)
  }
}
