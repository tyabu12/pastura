#if canImport(FoundationModels)

  import FoundationModels
  import Testing

  @testable import Pastura

  /// Unit coverage for the **non-inference** logic of ``FoundationModelsService``.
  ///
  /// Real inference cannot run in CI / the simulator (Apple Intelligence needs
  /// an eligible device with the system model present — the same simulator
  /// constraint `LlamaCppService` has, `.claude/rules/engine.md`), so these
  /// tests exercise lifecycle, identifiers, and availability-reason mapping
  /// only. Availability-dependent paths (`loadModel()` success) are avoided so
  /// the suite is deterministic across environments — on the simulator the
  /// system model is typically unavailable.
  ///
  /// `@available` sits on each `@Test` (Swift Testing skips them below the
  /// runtime version), **not** on the `@Suite` type — the `@Suite` macro
  /// rejects an `@available`-annotated structure.
  @Suite(.timeLimit(.minutes(1)))
  struct FoundationModelsServiceTests {
    @available(iOS 26, macOS 26, *)
    @Test func startsUnloaded() {
      let service = FoundationModelsService()
      #expect(service.isModelLoaded == false)
    }

    @available(iOS 26, macOS 26, *)
    @Test func throwsNotLoadedBeforeLoadModel() async {
      let service = FoundationModelsService()
      await #expect(throws: LLMError.notLoaded) {
        _ = try await service.generate(system: "s", user: "u", schema: nil)
      }
    }

    @available(iOS 26, macOS 26, *)
    @Test func unloadKeepsUnloaded() async throws {
      let service = FoundationModelsService()
      try await service.unloadModel()
      #expect(service.isModelLoaded == false)
    }

    @available(iOS 26, macOS 26, *)
    @Test func exposesStableIdentifiers() {
      let service = FoundationModelsService()
      #expect(service.modelIdentifier == "Apple Foundation Model")
      #expect(service.backendIdentifier == "FoundationModels")
    }

    @available(iOS 26, macOS 26, *)
    @Test func conformsToLLMService() {
      let service: any LLMService = FoundationModelsService()
      #expect(service.backendIdentifier == "FoundationModels")
    }

    @available(iOS 26, macOS 26, *)
    @Test func mapsUnavailableReasonsToDistinctCauses() {
      let device = FoundationModelsService.describe(.deviceNotEligible)
      let notEnabled = FoundationModelsService.describe(.appleIntelligenceNotEnabled)
      let notReady = FoundationModelsService.describe(.modelNotReady)

      #expect(device.contains("device not eligible"))
      #expect(notEnabled.contains("Apple Intelligence not enabled"))
      #expect(notReady.contains("not ready"))
      // Distinct messages so loadModel()'s error surfaces the real cause.
      #expect(Set([device, notEnabled, notReady]).count == 3)
    }

    /// The three prefixed classes must stay mutually distinguishable by grep:
    /// the harness JSONL carries `map`'s description verbatim as a
    /// `turn_skipped` cause, and the #1072 digest counts them separately.
    ///
    /// `unsupportedLanguageOrLocale` earns a prefix because the corrected
    /// battery observed 4 of them in `prisoners_dilemma_en` where #1072's run
    /// observed 0 — it is the digest's run-to-run noise floor, and it cannot
    /// be counted while it shares the generic bucket with every other error.
    @available(iOS 26, macOS 26, *)
    @Test func mapsGenerationErrorsToDistinctPrefixes() {
      let context = LanguageModelSession.GenerationError.Context(debugDescription: "probe")
      let ctxExceeded = FoundationModelsService.map(.exceededContextWindowSize(context))
      let guardrail = FoundationModelsService.map(.guardrailViolation(context))
      let locale = FoundationModelsService.map(.unsupportedLanguageOrLocale(context))
      let other = FoundationModelsService.map(.rateLimited(context))

      // Assert the PREFIX, not `.contains` — the SDK's own
      // `localizedDescription` for `unsupportedLanguageOrLocale` reads "An
      // unsupported language or locale was used", so a `.contains` check
      // passes on the generic arm too and pins nothing. (It did: this test was
      // green before the arm existed.)
      #expect(
        description(of: ctxExceeded).hasPrefix("Foundation Models context window exceeded — "))
      #expect(description(of: guardrail).hasPrefix("Foundation Models guardrail refusal — "))
      #expect(
        description(of: locale).hasPrefix("Foundation Models unsupported language or locale — "))
      // Unprefixed classes still share the generic bucket by design.
      #expect(description(of: other).hasPrefix("Foundation Models generation failed — "))
    }

    /// Unwraps the description `map` builds — the whole point is the string,
    /// since `map` deliberately adds no `LLMError` case.
    private func description(of error: LLMError) -> String {
      guard case .generationFailed(let description) = error else { return "" }
      return description
    }
  }

#endif
