// The whole file is gated on `canImport(FoundationModels)` — the framework
// ships only in the iOS 26 / macOS 26 SDK, so on an older toolchain this
// compiles out entirely and the app + harness builds stay green without an FM
// SDK, exactly as llama.cpp real inference is absent from CI.
//
// CI DOES type-check this file: every Swift job in `.github/workflows/ci.yml`
// pins `DEVELOPER_DIR` to Xcode 26.4, which ships the FM SDK, so `canImport` is
// true there and a break here reddens CI like any other code. (An earlier
// version of this comment claimed the opposite; the #1072 spike predated the
// toolchain pin.) What CI still cannot do is RUN any of it — Apple Intelligence
// needs an eligible device — so inference-dependent behaviour remains
// device-verified, and only the pure-logic parts (error mapping, the guided
// schema builder) are machine-gated.
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

    // `model` / `maximumResponseTokens` are internal rather than private so the
    // sibling-file extensions can read them — `private` is file-scoped, and the
    // token-budget instrumentation lives in `+TokenBudget.swift`.
    let model: SystemLanguageModel
    let maximumResponseTokens: Int?
    private let guidedGeneration: Bool
    private let loadedState: OSAllocatedUnfairLock<Bool>

    /// Monotonic turn counter, used solely as a join key across the three
    /// diagnostic lines one ``generate(system:user:schema:antiRepetitionSeeds:)``
    /// call can emit (input / response / overflow). An overflowing turn emits no
    /// response line, so without a key an analyst cannot pair the overflow with
    /// the input measurements that produced it.
    private let turnSeq: OSAllocatedUnfairLock<Int>

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
    ///   - guidedGeneration: When `true`, a turn that carries an
    ///     ``OutputSchema`` runs schema-constrained via
    ///     ``respondGuided(session:user:schema:options:)`` instead of free-form.
    ///     Defaults to `false` — see `FoundationModelsService+GuidedGeneration`
    ///     for what this measures and why it is off by default.
    public init(
      model: SystemLanguageModel = .default, maximumResponseTokens: Int? = nil,
      guidedGeneration: Bool = false
    ) {
      self.model = model
      self.maximumResponseTokens = maximumResponseTokens
      self.guidedGeneration = guidedGeneration
      self.loadedState = OSAllocatedUnfairLock(initialState: false)
      self.turnSeq = OSAllocatedUnfairLock(initialState: 0)
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
    /// `schema` is honoured only when the service was built with
    /// `guidedGeneration: true` (default `false`). Unconstrained, the model runs
    /// free-form: the prompt instructs JSON and ``JSONResponseParser`` carries
    /// the field contract, so FM parse-failure rates are **not** apples-to-apples
    /// with the GBNF-grammar-constrained ``LlamaCppService``. Constrained, the
    /// turn decodes against a runtime `GenerationSchema` — see
    /// `FoundationModelsService+GuidedGeneration`.
    ///
    /// - Warning: **Guided generation is documented to re-enable the default
    ///   guardrails**, which would undo the permissive mode this backend was
    ///   re-evaluated under. Per Apple, permissive guardrails "only work for
    ///   generating a string value. When you use guided generation, the
    ///   framework runs the default guardrails against model input and output
    ///   as usual." The unconstrained path returns `response.content` (a plain
    ///   `String`), the only shape permissive mode covers; the guided path
    ///   returns schema-decoded content and so is expected to lose that cover.
    ///   That expectation is precisely what `guidedGeneration` exists to
    ///   **measure** (#1072 reversal condition 1) — it is not yet an observed
    ///   fact, which is why the flag defaults off. Guided generation is
    ///   therefore not the free win #1072's first digest called
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
      let seq = turnSeq.withLock { seq in
        seq += 1
        return seq
      }
      // Emitted BEFORE the `do` on purpose: a turn that overflows the context
      // window throws out of `respond`, and the input-side numbers are exactly
      // what blocker 2 needs on that turn. Measuring after the call would
      // condition the whole sample on success and drop the failing population.
      // Built here — ahead of the input-budget emission and OUTSIDE the `do` —
      // for two reasons: `schemaTokens` needs a schema to report, and a
      // schema-build failure is not a `GenerationError`, so it must not land in
      // the catch arm below that maps generation errors.
      var generationSchema: GenerationSchema?
      if guidedGeneration, let schema, !schema.fields.isEmpty {
        generationSchema = try Self.generationSchema(from: schema)
      }
      let inputTokens = await logInputTokenBudget(
        seq: seq, system: system, user: user, schema: generationSchema)
      do {
        let result: (text: String, entries: ArraySlice<Transcript.Entry>)
        if let generationSchema {
          result = try await respondGuided(
            session: session, user: user, schema: generationSchema, options: options)
        } else {
          let response = try await session.respond(to: user, options: options)
          result = (response.content, response.transcriptEntries)
        }
        await logResponseTokenBudget(
          seq: seq, inputTokens: inputTokens, entries: result.entries)
        return result.text
      } catch let error as LanguageModelSession.GenerationError {
        if case .exceededContextWindowSize = error {
          // No response exists, so no response-side line is emitted. Without
          // this marker the event blocker 2 is ABOUT would be the one event
          // absent from the data. Carries `input` directly (not only the `seq`
          // join) because this line is the primary evidence: the #1154 smoke run
          // saw overflow at input=403 against contextSize=4096 — under 10% of
          // the window — while a turn with input=575 succeeded. Whatever
          // exhausts the window, it is not the size of the input.
          Self.emitTokenBudget(
            "fmTokenBudget seq=\(seq) phase=overflow contextSize=\(model.contextSize) "
              + "input=\(inputTokens)")
        }
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
