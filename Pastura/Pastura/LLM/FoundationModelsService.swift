// The whole file is gated on `canImport(FoundationModels)` — the framework
// ships only in the iOS 26 / macOS 26 SDK. On an older toolchain (a CI runner
// on Xcode < 26) this compiles out entirely, keeping the app + harness builds
// green without an FM SDK, exactly as llama.cpp real inference is absent from
// CI. NOTE (#1072 spike): because `canImport` is an SDK check, standard CI /
// pre-commit that lack the FM SDK never type-check this code — verify a real
// build on the Xcode-26 SDK (`canImport` true) before trusting the API shape.
#if canImport(FoundationModels)

  import Foundation
  import FoundationModels
  import os

  /// LLM service backed by the on-device Apple Foundation Model (iOS 26+ /
  /// macOS 26+, Apple Intelligence system model), evaluated as a third
  /// ``LLMService`` backend under spike #1072.
  ///
  /// - Important: This is a spike-scope backend. It is **not** wired into the
  ///   production `ModelRegistry` / model-selection UI — integration is a
  ///   separate issue gated on the spike's GO/NO-GO. Unlike ``OllamaService``
  ///   it is **not** dev-gated (`#if DEBUG`), because an Apple on-device model
  ///   is App-Store-safe to ship.
  /// - Note: Not safe for concurrent `generate`/`unloadModel` calls. The Engine
  ///   executes inferences sequentially, so this is fine in practice (same
  ///   contract as ``OllamaService`` / ``LlamaCppService``).
  @available(iOS 26, macOS 26, *)
  nonisolated public final class FoundationModelsService: LLMService, @unchecked Sendable {
    // @unchecked Sendable: the only mutable state is `loadedState`, protected by
    // OSAllocatedUnfairLock. `model` is an immutable Sendable value.

    private let model: SystemLanguageModel
    private let loadedState: OSAllocatedUnfairLock<Bool>

    /// Creates a service over a system language model.
    ///
    /// - Parameter model: The system model to drive. Defaults to
    ///   ``SystemLanguageModel/default`` (the general-purpose base model).
    public init(model: SystemLanguageModel = .default) {
      self.model = model
      self.loadedState = OSAllocatedUnfairLock(initialState: false)
    }

    /// Marks the service ready after confirming the system model is available.
    ///
    /// - Throws: ``LLMError/loadFailed(description:)`` when the model is
    ///   unavailable (device ineligible, Apple Intelligence disabled, or the
    ///   model not yet downloaded). Unlike a GGUF backend there is no file to
    ///   load — availability is the readiness gate.
    public func loadModel() async throws {
      switch model.availability {
      case .available:
        loadedState.withLock { $0 = true }
      case .unavailable(let reason):
        throw LLMError.loadFailed(description: Self.describe(reason))
      }
    }

    public func unloadModel() async throws {
      // No resource to release — the system model is process-external. Clearing
      // the flag keeps `isModelLoaded` / `notLoaded` semantics uniform across
      // backends.
      loadedState.withLock { $0 = false }
    }

    public var isModelLoaded: Bool {
      loadedState.withLock { $0 }
    }

    public var modelIdentifier: String { "Apple Foundation Model" }
    public let backendIdentifier = "FoundationModels"

    /// Generates a completion from the system model.
    ///
    /// Creates a **fresh** ``LanguageModelSession`` per call: Pastura's
    /// `generate` is a single-turn call (the conversation log is already baked
    /// into `user` by the prompt builder), so a per-call session keeps the
    /// model's ~4k context window holding only ONE turn (instructions + user +
    /// output) — structurally avoiding the cumulative-transcript overflow a
    /// long-lived session would hit.
    ///
    /// `schema` is intentionally **ignored** in this spike: the model runs
    /// schema-unconstrained (no `@Generable` guided generation). The prompt
    /// already instructs JSON and ``JSONResponseParser`` carries the field
    /// contract. Consequence for the #1072 evaluation phase: FM parse-failure
    /// rates are **not** apples-to-apples with the GBNF-grammar-constrained
    /// ``LlamaCppService`` — guided generation is a defensible follow-up, not
    /// spike scope.
    ///
    /// - Throws: ``LLMError/notLoaded`` before ``loadModel()``;
    ///   ``LLMError/generationFailed(description:)`` on inference failure. The
    ///   description carries a distinctive prefix for context-window-exceeded
    ///   and guardrail-refusal cases so the harness JSONL log stays grep-classifiable.
    ///
    /// `@concurrent`: `LanguageModelSession.respond(to:)` is
    /// `nonisolated(nonsending)` (SE-0461) — it runs on the CALLER's executor.
    /// Reached from the MainActor `SimulationViewModel` its body would otherwise
    /// run on the MainActor; `@concurrent` forces it onto the global concurrent
    /// executor (Pattern 6, `.claude/rules/swift-isolation.md`), mirroring
    /// `LlamaCppService`.
    @concurrent
    public func generate(
      system: String, user: String, schema: OutputSchema?
    ) async throws -> String {
      guard isModelLoaded else { throw LLMError.notLoaded }

      let session = LanguageModelSession(instructions: system)
      do {
        let response = try await session.respond(to: user)
        return response.content
      } catch let error as LanguageModelSession.GenerationError {
        throw Self.map(error)
      } catch {
        throw LLMError.generationFailed(description: String(describing: error))
      }
    }

    /// Maps a model-unavailable reason to a human-readable, distinct message so
    /// ``loadModel()``'s error surfaces the actual cause.
    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
      switch reason {
      case .deviceNotEligible:
        return "Foundation Models unavailable: device not eligible for Apple Intelligence"
      case .appleIntelligenceNotEnabled:
        return "Foundation Models unavailable: Apple Intelligence not enabled in Settings"
      case .modelNotReady:
        return
          "Foundation Models unavailable: system model not ready (still downloading or warming up)"
      @unknown default:
        return "Foundation Models unavailable: unknown reason"
      }
    }

    /// Maps a `GenerationError` to ``LLMError``, keeping a distinctive
    /// description prefix per class so failures stay classifiable by grep in
    /// the harness JSONL run log — without adding an ``LLMError`` case (which
    /// would ripple through its no-default-exhaustive `errorDescription`
    /// switch and add i18n catalog keys).
    static func map(_ error: LanguageModelSession.GenerationError) -> LLMError {
      switch error {
      case .exceededContextWindowSize:
        return .generationFailed(
          description: "Foundation Models context window exceeded — \(error.localizedDescription)")
      case .guardrailViolation:
        return .generationFailed(
          description: "Foundation Models guardrail refusal — \(error.localizedDescription)")
      default:
        return .generationFailed(
          description: "Foundation Models generation failed — \(error.localizedDescription)")
      }
    }
  }

#endif
