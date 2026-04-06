import Foundation
import os

/// LLM service connecting to Ollama via its OpenAI-compatible chat API.
///
/// For development and Simulator use only. Connects to a local or network
/// Ollama instance. Not included in production builds.
nonisolated public final class OllamaService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: mutable state is protected by OSAllocatedUnfairLock.

  private let baseURL: URL
  private let modelName: String
  private let session: URLSession
  private let loadedState: OSAllocatedUnfairLock<Bool>

  // Hardcoded defaults matching Python prototype
  private static let temperature: Double = 0.8
  private static let maxTokens: Int = 1000

  /// Creates an Ollama service.
  ///
  /// - Parameters:
  ///   - baseURL: The Ollama API base URL. Defaults to `http://localhost:11434`.
  ///   - modelName: The Ollama model name. Defaults to `"gemma4:e2b"`.
  ///   - session: URLSession to use for requests. Injectable for testing.
  public init(
    baseURL: URL? = nil,
    modelName: String = "gemma4:e2b",
    session: URLSession = .shared
  ) {
    // Avoid force unwrap by using a static default
    self.baseURL =
      baseURL
      ?? {
        guard let url = URL(string: "http://localhost:11434") else {
          preconditionFailure("Static default URL literal is invalid")
        }
        return url
      }()
    self.modelName = modelName
    self.session = session
    self.loadedState = OSAllocatedUnfairLock(initialState: false)
  }

  public func loadModel() async throws {
    loadedState.withLock { $0 = true }
  }

  public func unloadModel() async throws {
    loadedState.withLock { $0 = false }
  }

  public var isModelLoaded: Bool {
    loadedState.withLock { $0 }
  }

  public func generate(system: String, user: String) async throws -> String {
    guard isModelLoaded else { throw LLMError.notLoaded }

    let request = try buildRequest(system: system, user: user)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw LLMError.networkError(description: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.networkError(description: "Non-HTTP response received")
    }

    try mapHTTPStatus(httpResponse)

    return try extractContent(from: data)
  }

  // MARK: - Request Building

  private func buildRequest(system: String, user: String) throws -> URLRequest {
    let url = baseURL.appendingPathComponent("v1/chat/completions")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "model": modelName,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
      ],
      "temperature": Self.temperature,
      "max_tokens": Self.maxTokens
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  // MARK: - Response Handling

  /// Map HTTP status codes to appropriate LLMError cases.
  private func mapHTTPStatus(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200...299:
      return
    case 400...499:
      throw LLMError.generationFailed(
        description: "HTTP \(response.statusCode): client error")
    default:
      throw LLMError.networkError(
        description: "HTTP \(response.statusCode): server error")
    }
  }

  /// Extract the content string from the OpenAI-compatible response.
  private func extractContent(from data: Data) throws -> String {
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let firstChoice = choices.first,
      let message = firstChoice["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      let raw = String(data: data, encoding: .utf8) ?? "<binary>"
      throw LLMError.invalidResponse(raw: raw)
    }
    return content
  }
}
