import Foundation
import LlamaSwift
import os

/// On-device LLM backend using llama.cpp with Metal GPU acceleration.
///
/// Loads a GGUF model file from disk and runs inference locally.
/// Designed for TestFlight production use with Gemma 4 E2B.
///
/// - Important: Not safe for concurrent `generate`/`loadModel`/`unloadModel` calls.
///   The Engine executes inferences sequentially, so this is fine in practice.
///   A runtime guard (`precondition`) detects violations in both Debug and Release builds.
nonisolated public final class LlamaCppService: LLMService, @unchecked Sendable {
  // @unchecked Sendable: isModelLoaded flag protected by OSAllocatedUnfairLock.
  // C pointers use nonisolated(unsafe) — Engine calls generate() sequentially via
  // `for await` on a single AsyncStream, and loadModel()/unloadModel() bracket the
  // stream lifetime, guaranteeing no concurrent access to C pointers (ADR-002 §6).
  //
  // NOTE: Class body is at the SwiftLint type_body_length limit (250 lines).
  // Future additions should extract helpers into private extensions or separate files
  // (e.g., tokenization, sampler setup, or chat template logic).

  private let modelPath: String
  private let logger = Logger(subsystem: "com.pastura", category: "LlamaCppService")

  // Sampling parameters (ADR-002 §6, matching OllamaService)
  private static let temperature: Float = 0.8
  private static let maxTokens: Int = 1_000
  private static let topK: Int32 = 40
  private static let topP: Float = 0.95
  private static let repeatPenalty: Float = 1.1
  private static let contextSize: UInt32 = 8_192
  private static let batchSize: Int = 512

  private let loadedState: OSAllocatedUnfairLock<Bool>
  // Runtime guard for the sequential access contract (ADR-002 §6).
  // Catches concurrent generate(), or load/unload during active generation.
  private let generatingGuard = OSAllocatedUnfairLock<Bool>(initialState: false)
  // Sequential access only — protected by concurrency contract, not by lock
  nonisolated(unsafe) private var _model: OpaquePointer?
  nonisolated(unsafe) private var _context: OpaquePointer?

  /// Creates a llama.cpp service.
  ///
  /// - Parameter modelPath: Absolute path to the GGUF model file on disk.
  public init(modelPath: String) {
    self.modelPath = modelPath
    self.loadedState = OSAllocatedUnfairLock(initialState: false)
  }

  deinit {
    // Safety net: free C resources if still loaded.
    if loadedState.withLock({ $0 }) {
      if let ctx = _context { llama_free(ctx) }
      if let mdl = _model { llama_model_free(mdl) }
      llama_backend_free()
    }
  }

  // MARK: - LLMService

  public func loadModel() async throws {
    precondition(!generatingGuard.withLock({ $0 }), "loadModel() during generate() — ADR-002 §6")

    // llama_backend_init is internally ref-counted — safe to call multiple times
    llama_backend_init()

    var modelParams = llama_model_default_params()
    modelParams.n_gpu_layers = -1  // Offload all layers to Metal GPU

    guard let model = llama_model_load_from_file(modelPath, modelParams) else {
      llama_backend_free()
      throw LLMError.loadFailed(description: "Failed to load model from \(modelPath)")
    }

    var ctxParams = llama_context_default_params()
    ctxParams.n_ctx = Self.contextSize
    ctxParams.n_batch = UInt32(Self.batchSize)

    guard let context = llama_init_from_model(model, ctxParams) else {
      llama_model_free(model)
      llama_backend_free()
      throw LLMError.loadFailed(description: "Failed to create inference context")
    }

    _model = model
    _context = context
    loadedState.withLock { $0 = true }
  }

  public func unloadModel() async throws {
    // TODO: didReceiveMemoryWarning must await simulation completion before calling this (ADR-002 §7).
    precondition(!generatingGuard.withLock({ $0 }), "unloadModel() during generate() — ADR-002 §6")

    let wasLoaded = loadedState.withLock { loaded -> Bool in
      let was = loaded
      loaded = false
      return was
    }

    guard wasLoaded else { return }

    // Free C resources
    if let ctx = _context { llama_free(ctx) }
    if let mdl = _model { llama_model_free(mdl) }
    _context = nil
    _model = nil
    llama_backend_free()
  }

  public var isModelLoaded: Bool {
    loadedState.withLock { $0 }
  }

  public func generate(system: String, user: String) async throws -> String {
    // Thermal throttle: pause before inference when device is overheating (ADR-002 §5).
    // Uses `try await` (not `try?`) so Task cancellation propagates through the sleep.
    let thermalState = ProcessInfo.processInfo.thermalState
    if thermalState == .serious || thermalState == .critical {
      logger.warning("Thermal state \(String(describing: thermalState)) — inserting 200ms pause")
      try await Task.sleep(for: .milliseconds(200))
    }

    guard isModelLoaded, let model = _model, let context = _context else {
      throw LLMError.notLoaded
    }

    // Runtime enforcement of sequential access contract (ADR-002 §6).
    // Concurrent generate() would cause use-after-free of C pointers.
    // IMPORTANT: This guard is intentionally placed after the isModelLoaded check above.
    // Calls that fail with .notLoaded must not touch the flag — otherwise the flag
    // stays true and the next sequential call would be falsely flagged as concurrent.
    let wasGenerating = generatingGuard.withLock { flag -> Bool in
      let was = flag
      flag = true
      return was
    }
    precondition(!wasGenerating, "Concurrent generate() detected — ADR-002 §6")
    defer { generatingGuard.withLock { $0 = false } }

    let vocab = llama_model_get_vocab(model)

    // Apply chat template to format system+user into model-native format
    let formattedPrompt = try applyChatTemplate(system: system, user: user)

    // Tokenize the formatted prompt
    let tokens = try tokenize(vocab: vocab, text: formattedPrompt, addSpecial: true)

    let nCtx = Int(llama_n_ctx(context))
    guard tokens.count <= nCtx else {
      throw LLMError.generationFailed(
        description: "Prompt (\(tokens.count) tokens) exceeds context size (\(nCtx))"
      )
    }

    // Clear KV cache for independent inference (each generate() call is self-contained)
    llama_memory_clear(llama_get_memory(context), true)

    // Prefill: process prompt tokens
    try prefill(context: context, tokens: tokens)

    // Set up sampler chain
    let sampler = try createSampler()
    defer { llama_sampler_free(sampler) }

    // Resolve <|im_end|> token ID for explicit stop detection.
    // llama_vocab_is_eog() misses this token on Gemma 4 E2B, causing
    // hallucinated conversation continuations until maxTokens.
    let imEndTokenId = resolveImEndTokenId(vocab: vocab)

    // Auto-regressive generation loop
    var outputTokens: [llama_token] = []
    for _ in 0..<Self.maxTokens {
      let newTokenId = llama_sampler_sample(sampler, context, -1)

      if llama_vocab_is_eog(vocab, newTokenId) || newTokenId == imEndTokenId {
        if newTokenId == imEndTokenId { logger.debug("<|im_end|> stop token hit — ending early") }
        break
      }

      outputTokens.append(newTokenId)

      // Decode single token for next iteration
      var nextToken = newTokenId
      let batch = llama_batch_get_one(&nextToken, 1)
      let decodeResult = llama_decode(context, batch)
      guard decodeResult == 0 else {
        throw LLMError.generationFailed(
          description: "llama_decode failed during generation (error \(decodeResult))"
        )
      }
    }

    guard !outputTokens.isEmpty else {
      throw LLMError.generationFailed(description: "Model generated no output tokens")
    }

    return detokenize(vocab: vocab, tokens: outputTokens)
  }

  // MARK: - Chat Template

  private func applyChatTemplate(system: String, user: String) throws -> String {
    // Build llama_chat_message array using C strings
    guard
      let systemRole = strdup("system"),
      let userRole = strdup("user"),
      let systemContent = strdup(system),
      let userContent = strdup(user)
    else {
      throw LLMError.generationFailed(
        description: "Memory allocation failed for chat template"
      )
    }
    defer {
      free(systemRole)
      free(userRole)
      free(systemContent)
      free(userContent)
    }

    var messages: [llama_chat_message] = [
      llama_chat_message(role: systemRole, content: systemContent),
      llama_chat_message(role: userRole, content: userContent)
    ]

    // First call: determine required buffer size
    let requiredSize = llama_chat_apply_template(
      nil, &messages, messages.count, true, nil, 0
    )
    guard requiredSize > 0 else {
      throw LLMError.generationFailed(
        description: "llama_chat_apply_template failed to calculate buffer size"
      )
    }

    // Second call: write formatted prompt into buffer
    var buffer = [CChar](repeating: 0, count: Int(requiredSize) + 1)
    let written = llama_chat_apply_template(
      nil, &messages, messages.count, true, &buffer, Int32(buffer.count)
    )
    guard written > 0 else {
      throw LLMError.generationFailed(
        description: "llama_chat_apply_template failed"
      )
    }

    return String(cString: buffer)
  }

  // MARK: - Tokenization

  private func tokenize(
    vocab: OpaquePointer?,
    text: String,
    addSpecial: Bool
  ) throws -> [llama_token] {
    return try text.withCString { cStr in
      let textLen = Int32(strlen(cStr))
      let maxTokens = textLen + 128

      var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
      let nTokens = llama_tokenize(
        vocab, cStr, textLen, &tokens, maxTokens, addSpecial,
        true  // parse_special: handle special tokens in the template
      )

      if nTokens < 0 {
        // Buffer was too small; retry with the required size
        let required = -nTokens
        tokens = [llama_token](repeating: 0, count: Int(required))
        let nTokens2 = llama_tokenize(
          vocab, cStr, textLen, &tokens, required, addSpecial, true
        )
        guard nTokens2 >= 0 else {
          throw LLMError.generationFailed(description: "Tokenization failed")
        }
        return Array(tokens.prefix(Int(nTokens2)))
      }

      return Array(tokens.prefix(Int(nTokens)))
    }
  }

  private func detokenize(
    vocab: OpaquePointer?,
    tokens: [llama_token]
  ) -> String {
    tokens.map { decodePiece(vocab: vocab, token: $0) }.joined()
  }

  // MARK: - Prefill

  private func prefill(
    context: OpaquePointer,
    tokens: [llama_token]
  ) throws {
    var mutableTokens = tokens
    var offset = 0

    while offset < mutableTokens.count {
      let chunkSize = min(Self.batchSize, mutableTokens.count - offset)
      let batch = mutableTokens.withUnsafeMutableBufferPointer { ptr -> llama_batch in
        // baseAddress is non-nil because the while condition guarantees non-empty remaining tokens
        guard let base = ptr.baseAddress else {
          preconditionFailure("Empty token buffer should have been caught by context-size check")
        }
        return llama_batch_get_one(base + offset, Int32(chunkSize))
      }
      let decodeResult = llama_decode(context, batch)
      guard decodeResult == 0 else {
        throw LLMError.generationFailed(
          description: "llama_decode failed during prefill (error \(decodeResult))"
        )
      }
      offset += chunkSize
    }
  }

  // MARK: - Sampler

  private func createSampler() throws -> UnsafeMutablePointer<llama_sampler> {
    let sparams = llama_sampler_chain_default_params()
    guard let chain = llama_sampler_chain_init(sparams) else {
      throw LLMError.generationFailed(description: "Failed to initialize sampler chain")
    }

    // Order: penalties → top_k → top_p → temperature → dist
    // Penalties on full vocab first, then narrow, then temperature, then selection
    llama_sampler_chain_add(
      chain,
      llama_sampler_init_penalties(
        64,  // penalty_last_n: look back 64 tokens
        Self.repeatPenalty,  // repeat_penalty: 1.1
        0.0,  // freq_penalty: disabled
        0.0  // presence_penalty: disabled
      ))
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(Self.topK))
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(Self.topP, 1))
    llama_sampler_chain_add(chain, llama_sampler_init_temp(Self.temperature))
    llama_sampler_chain_add(
      chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

    return chain
  }
}

// MARK: - Tokenization Helpers

extension LlamaCppService {
  /// Decodes a single token ID to its string piece.
  fileprivate func decodePiece(
    vocab: OpaquePointer?,
    token: llama_token
  ) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    let nChars = llama_token_to_piece(
      vocab, token, &buffer, Int32(buffer.count), 0, false
    )
    if nChars > 0 {
      buffer[Int(nChars)] = 0  // null-terminate
      return String(cString: buffer)
    } else if nChars < 0 {
      // Buffer too small; retry with required size
      var largeBuffer = [CChar](repeating: 0, count: Int(-nChars) + 1)
      let retryChars = llama_token_to_piece(
        vocab, token, &largeBuffer, Int32(largeBuffer.count), 0, false
      )
      if retryChars > 0 {
        largeBuffer[Int(retryChars)] = 0
        return String(cString: largeBuffer)
      }
    }
    return ""
  }

  /// Returns the token ID for `<|im_end|>`, or `nil` if unresolvable.
  /// `llama_vocab_is_eog()` misses this token on Gemma 4 E2B; checked explicitly in the loop.
  fileprivate func resolveImEndTokenId(vocab: OpaquePointer?) -> llama_token? {
    // TODO: Cache result at loadModel() time — vocab is stable for the model lifetime (#65)
    // TODO: Consider adding <|im_start|> as stop token if hallucinated turn starts are observed (#65)
    let t = (try? tokenize(vocab: vocab, text: "<|im_end|>", addSpecial: false)) ?? []
    if t.count == 1 { return t[0] }
    // 0 tokens = tokenization threw; >1 = unexpected multi-token encoding
    logger.warning(
      "<|im_end|> resolved to \(t.count) tokens (expected 1) — stop-token optimization disabled")
    return nil
  }
}
