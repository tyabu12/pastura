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
    private let maximumResponseTokens: Int?
    private let loadedState: OSAllocatedUnfairLock<Bool>

    /// Creates a service over a system language model.
    ///
    /// Guardrail mode is injected through this parameter rather than being a
    /// setting of its own — pass `SystemLanguageModel(guardrails:)`:
    ///
    /// ```swift
    /// FoundationModelsService(
    ///   model: SystemLanguageModel(guardrails: .permissiveContentTransformations))
    /// ```
    ///
    /// The default (`.default` guardrails) is what spike #1072's first battery
    /// measured, and its "Apple offers no guardrail adjustment API" conclusion
    /// was wrong precisely because no caller ever passed anything else. The
    /// harness selects the mode via `--guardrails`.
    ///
    /// - Parameters:
    ///   - model: The system model to drive. Defaults to
    ///     ``SystemLanguageModel/default`` (the general-purpose base model with
    ///     default guardrails).
    ///   - maximumResponseTokens: Upper bound on generated tokens, forwarded as
    ///     `GenerationOptions.maximumResponseTokens`. `nil` (the default) leaves
    ///     generation unconstrained, i.e. the behaviour every prior #1072
    ///     battery measured. Spike #1154 wires this to test whether capping
    ///     output relieves the 4k-context blocker — the expected outcome is
    ///     *not* a clean win: a cap truncates the JSON object mid-object, which
    ///     converts a context-exceeded failure into a parse failure rather than
    ///     removing it. That conversion is itself the measurement.
    public init(model: SystemLanguageModel = .default, maximumResponseTokens: Int? = nil) {
      self.model = model
      self.maximumResponseTokens = maximumResponseTokens
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

    /// - Note: Guardrail-blind by construction — `SystemLanguageModel` exposes
    ///   no `guardrails` accessor, so this cannot reflect the injected model's
    ///   mode. The harness threads its own guardrail-bearing label instead
    ///   (`Main.swift`'s run-log name); prefer that when attributing a run.
    ///   `SimulationViewModel` persists this into `SimulationRecord`, so wiring
    ///   this service past spike scope means every record carries a
    ///   guardrail-blind identifier — solve that then, not now.
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
    /// ``LlamaCppService``.
    ///
    /// - Warning: **Adopting `@Generable` guided generation would silently
    ///   re-enable the default guardrails**, undoing the permissive mode this
    ///   backend is being re-evaluated under. Per Apple, permissive guardrails
    ///   "only work for generating a string value. When you use guided
    ///   generation, the framework runs the default guardrails against model
    ///   input and output as usual." This service returns `response.content`
    ///   (a plain `String`), which is the only shape permissive mode covers.
    ///   So guided generation is not the free win #1072's first digest called
    ///   it — it trades JSON-validity assurance (already measured as a
    ///   non-problem) for the return of the failure that killed the spike.
    ///   Re-measure guardrails before adopting it.
    ///   See: https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output
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
      system: String, user: String, schema: OutputSchema?,
      antiRepetitionSeeds: [String]
    ) async throws -> String {
      // `antiRepetitionSeeds` is ignored — the Foundation Models session API
      // exposes no per-request sampler seeding hook (#1105).
      guard isModelLoaded else { throw LLMError.notLoaded }

      // `model:` is LOAD-BEARING and easy to lose: the SDK initializer is
      // `init(model: SystemLanguageModel = .default, tools:, instructions:)`,
      // so omitting it silently builds the session over `.default` and the
      // injected model reaches only `loadModel()`'s availability check — never
      // generation. #1156 shipped exactly that: a 6-cell battery ran with
      // `--guardrails permissive`, logged "(permissive)" for every cell, and
      // produced guardrail-refusal counts byte-identical to the default-
      // guardrails run (word_wolf-ja 9, bokete-en 4), because every session was
      // a default one.
      // As of the Xcode 26.6 SDK no test can reach this: `LanguageModelSession`
      // exposes no `model` accessor, so the session's model is unobservable.
      // Re-check on SDK bumps. Until then the control is the battery — a
      // permissive run that still throws `guardrailViolation` means this
      // argument went missing.
      let session = LanguageModelSession(model: self.model, instructions: system)
      // Built ONCE here, ahead of any branch on generation path, and threaded to
      // every `respond` overload. `respond`'s `options:` carries a compiler
      // default, so a callsite that omits it silently generates unconstrained —
      // structurally the same silent-default trap as the `model:` argument
      // above, whose omission invalidated an entire 6-cell battery (#1156).
      // One value, one construction site, so no two paths can disagree.
      let options = GenerationOptions(maximumResponseTokens: maximumResponseTokens)
      do {
        let response = try await session.respond(to: user, options: options)
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
    ///
    /// The prefix is what carries the classification — do NOT rely on the
    /// SDK's `localizedDescription` to disambiguate. Its text for
    /// `unsupportedLanguageOrLocale` ("An unsupported language or locale was
    /// used") reads exactly like a hand-written prefix would, so a
    /// substring-matching consumer cannot tell the prefixed arm from the
    /// generic one.
    static func map(_ error: LanguageModelSession.GenerationError) -> LLMError {
      switch error {
      case .exceededContextWindowSize:
        return .generationFailed(
          description: "Foundation Models context window exceeded — \(error.localizedDescription)")
      case .guardrailViolation:
        return .generationFailed(
          description: "Foundation Models guardrail refusal — \(error.localizedDescription)")
      case .unsupportedLanguageOrLocale:
        // Observed 4× in `prisoners_dilemma_en` where #1072's earlier run of
        // the same effective config saw 0 — i.e. this class is the corrected
        // battery's run-to-run noise floor, so the digest has to count it
        // apart from everything else in the generic bucket.
        return .generationFailed(
          description:
            "Foundation Models unsupported language or locale — \(error.localizedDescription)")
      // Plain `default:` (not `@unknown default` like `describe`): the spike
      // only distinguishes the three prefixed classes above; every other
      // GenerationError case intentionally shares the generic message.
      default:
        return .generationFailed(
          description: "Foundation Models generation failed — \(error.localizedDescription)")
      }
    }
  }

#endif
