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
  }

#endif
