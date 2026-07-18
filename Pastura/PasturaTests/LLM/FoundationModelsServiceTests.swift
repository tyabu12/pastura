#if canImport(FoundationModels)

  import Foundation
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

    // MARK: - Guided-generation schema builder

    /// The ONLY machine gate on the guided-generation path (#1154 / #1072
    /// reversal condition 1). Real inference needs an Apple Intelligence device,
    /// but the `OutputSchema` → `GenerationSchema` translation is pure logic, so
    /// it runs in CI (every Swift job pins Xcode 26.4, which ships the FM SDK).
    @available(iOS 26, macOS 26, *)
    @Test func guidedSchemaCarriesEveryDeclaredFieldAndNothingElse() throws {
      let json = try schemaJSON(
        from: OutputSchema(fields: [
          .init(name: "statement", kind: .string),
          .init(name: "inner_thought", kind: .string)
        ]))

      let properties = json["properties"] as? [String: Any] ?? [:]
      #expect(Set(properties.keys) == ["statement", "inner_thought"])
      // Every declared field is mandatory — an optional field would let the
      // model omit one and still satisfy the schema, which is precisely the
      // missing-key failure `JSONResponseParser` exists to catch.
      let required = json["required"] as? [String] ?? []
      #expect(Set(required) == ["statement", "inner_thought"])
    }

    /// Field ORDER is load-bearing and is carried explicitly by the schema's
    /// `x-order` key. ``OutputSchema/fields`` documents its order as the single
    /// source of truth for the primary-first policy — the same ordering
    /// `GBNFGrammarBuilder` and `PromptBuilder` consume so grammar and prompt
    /// cannot drift — and `PartialOutputExtractor` relies on the primary field
    /// arriving first for progressive streaming display. The guided path must
    /// not silently reorder it.
    @available(iOS 26, macOS 26, *)
    @Test func guidedSchemaPreservesDeclaredFieldOrder() throws {
      let json = try schemaJSON(
        from: OutputSchema(fields: [
          .init(name: "statement", kind: .string),
          .init(name: "inner_thought", kind: .string)
        ]))

      #expect(json["x-order"] as? [String] == ["statement", "inner_thought"])
    }

    /// Pins the claim the guided path's why-comment makes: `.choice` maps to a
    /// plain String leaf, exactly like `.string`. `OutputSchema.Kind.choice`
    /// carries no option payload, so there is nothing to enumerate — if a future
    /// change starts emitting `anyOf:` for `.choice`, this fails and forces the
    /// decision to be explicit rather than incidental.
    @available(iOS 26, macOS 26, *)
    @Test func guidedSchemaTreatsChoiceAsAPlainString() throws {
      let asChoice = OutputSchema(fields: [.init(name: "action", kind: .choice)])
      let asString = OutputSchema(fields: [.init(name: "action", kind: .string)])

      #expect(try canonical(schemaJSON(from: asChoice)) == canonical(schemaJSON(from: asString)))
    }

    /// Negative control — a guard's success case proves nothing on its own.
    /// Adding a field MUST change the schema, or the assertions above would also
    /// pass against a builder that silently dropped every field.
    ///
    /// This control only works on the CANONICALIZED form. `JSONEncoder` output
    /// for `GenerationSchema` is dictionary-backed and its top-level key order
    /// varies between two encodes of the *same* schema — so comparing raw
    /// encoded strings makes any two schemas "differ" and the control passes
    /// vacuously. It did, until `canonical(_:)` was introduced.
    @available(iOS 26, macOS 26, *)
    @Test func guidedSchemaChangesWhenAFieldIsAdded() throws {
      let oneField = OutputSchema(fields: [.init(name: "statement", kind: .string)])
      let twoFields = OutputSchema(fields: [
        .init(name: "statement", kind: .string),
        .init(name: "inner_thought", kind: .string)
      ])

      #expect(try canonical(schemaJSON(from: oneField)) != canonical(schemaJSON(from: twoFields)))
    }

    /// The guided path deliberately has NO fallback: a schema-build failure
    /// throws instead of quietly running the turn unguided. That choice is what
    /// prevents #1156's failure shape — a build failure is deterministic per
    /// `OutputSchema` shape, so a silent fallback would run an ENTIRE battery
    /// unguided while the run log still claimed guided. This pins both the throw
    /// and the grep-classifiable prefix the harness digest keys on.
    ///
    /// Duplicate field names are the reachable failing shape: the SDK rejects
    /// them with `duplicateProperty`. An EMPTY field list and an empty field
    /// name were both probed and build fine — which is why the callsite guards
    /// `!schema.fields.isEmpty` itself rather than relying on a throw.
    @available(iOS 26, macOS 26, *)
    @Test func guidedSchemaBuildFailureThrowsWithClassifiablePrefix() {
      let duplicated = OutputSchema(fields: [
        .init(name: "statement", kind: .string),
        .init(name: "statement", kind: .string)
      ])

      #expect(throws: LLMError.self) {
        try FoundationModelsService.generationSchema(from: duplicated)
      }
      do {
        _ = try FoundationModelsService.generationSchema(from: duplicated)
        Issue.record("expected a schema-build failure")
      } catch {
        #expect(
          description(of: error as? LLMError ?? .notLoaded)
            .hasPrefix("Foundation Models guided schema build failed — "))
      }
    }

    /// Builds the schema and decodes its `Codable` form into inspectable JSON.
    ///
    /// `GenerationSchema` exposes no property accessors, so its encoded form is
    /// the only reachable surface to assert against — `debugDescription` is an
    /// undocumented, unstable format and would make a far weaker gate.
    @available(iOS 26, macOS 26, *)
    private func schemaJSON(from schema: OutputSchema) throws -> [String: Any] {
      let generationSchema = try FoundationModelsService.generationSchema(from: schema)
      let data = try JSONEncoder().encode(generationSchema)
      return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Key-sorted rendering, so two schemas compare on CONTENT rather than on
    /// dictionary iteration order (see `guidedSchemaChangesWhenAFieldIsAdded`).
    private func canonical(_ object: [String: Any]) throws -> String {
      let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Unwraps the description `map` builds — the whole point is the string,
    /// since `map` deliberately adds no `LLMError` case.
    private func description(of error: LLMError) -> String {
      guard case .generationFailed(let description) = error else { return "" }
      return description
    }
  }

#endif
