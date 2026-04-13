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

  private let modelPath: String
  let logger = Logger(subsystem: "com.pastura", category: "LlamaCppService")

  // Sampling parameters (ADR-002 §6, matching OllamaService)
  static let temperature: Float = 0.8
  static let maxTokens: Int = 1_000
  static let topK: Int32 = 40
  static let topP: Float = 0.95
  static let repeatPenalty: Float = 1.1
  static let contextSize: UInt32 = 8_192
  static let batchSize: Int = 512
  // String-based, not token-ID, because Gemma 4 E2B tokenizes <|im_end|> into
  // 6 subword tokens — single-token ID matching is impossible for this model.
  // TODO: Consider adding <|im_start|> if hallucinated turn starts are observed (#65)
  static let stopSequence = "<|im_end|>"

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
    try await throttleIfOverheating()

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

    // Auto-regressive generation loop with string-based stop detection.
    // Tokens are decoded incrementally so we can detect <|im_end|> even when
    // the model's tokenizer splits it across multiple subword tokens.
    var outputText = ""
    for _ in 0..<Self.maxTokens {
      let newTokenId = llama_sampler_sample(sampler, context, -1)

      if llama_vocab_is_eog(vocab, newTokenId) { break }

      outputText += decodePiece(vocab: vocab, token: newTokenId)

      if let range = outputText.range(of: Self.stopSequence) {
        outputText = String(outputText[..<range.lowerBound])
        logger.debug("<|im_end|> stop sequence detected — ending generation early")
        break
      }

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

    guard !outputText.isEmpty else {
      throw LLMError.generationFailed(description: "Model generated no output tokens")
    }

    return outputText
  }
}
