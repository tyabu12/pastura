// Same `canImport(FoundationModels)` gate as the primary file — the framework
// ships only in the iOS 26 / macOS 26 SDK. CI compiles this (all Swift jobs pin
// Xcode 26.4, which ships the SDK), so a break here is caught there.
#if canImport(FoundationModels)

  import Foundation
  import FoundationModels

  /// Guided-generation (schema-constrained) support for ``FoundationModelsService``.
  ///
  /// ## Why this exists
  ///
  /// Spike #1072 closed No-Go with a **reversal condition**: its top remaining
  /// blocker was that FM runs without a GBNF-equivalent constraint, so free-form
  /// prompts produce JSON that never closes — and that the obvious remedy,
  /// guided generation, is documented by Apple to **re-enable the default
  /// guardrails** ("When you use guided generation, the framework runs the
  /// default guardrails against model input and output as usual"), which would
  /// cancel out the permissive-guardrails fix that #1159 landed. Two known
  /// repairs that undo each other, with the interaction never measured. This
  /// file makes it measurable.
  ///
  /// ## Which question this actually answers
  ///
  /// #1072's condition names `@Generable` guided generation. This code uses a
  /// **runtime-built `GenerationSchema`** instead, because Pastura's output
  /// shape is per-phase data (``OutputSchema``), not a compile-time Swift type.
  /// Apple's guardrail sentence is scoped to "guided generation" generally, not
  /// to the macro specifically, so the two are expected to behave alike — but
  /// that expectation is an **assumption, not a measurement**. Any digest built
  /// on this code must say "under runtime-schema guided generation", never
  /// silently "under `@Generable`".
  @available(iOS 26, macOS 26, *)
  nonisolated extension FoundationModelsService {

    /// Whether the schema is restated inside the prompt.
    ///
    /// **`false` on purpose**, and load-bearing for the experiment:
    ///
    /// 1. `PromptBuilder` already states the field contract in the prompt, so
    ///    `true` would spend the ~4k context on the same information twice —
    ///    directly worsening the blocker the sibling instrumentation measures.
    /// 2. It keeps the guided arm's prompt **byte-identical** to the plain
    ///    arm's, so an A/B differs in exactly one variable (decode constraint
    ///    present or absent). With `true`, a guardrail difference and an
    ///    increase in context pressure would arrive confounded.
    ///
    /// The schema still constrains decoding either way; only the prompt text
    /// differs. `schemaTokens` is logged regardless, so the cost this avoids
    /// stays visible.
    static let includeSchemaInPrompt = false

    /// Translates Pastura's ``OutputSchema`` into a Foundation Models
    /// `GenerationSchema`.
    ///
    /// Every field maps to a **String** leaf, including ``OutputSchema/Kind/choice``.
    ///
    /// - Note: `DynamicGenerationSchema(name:anyOf:)` would let a `.choice`
    ///   field enumerate its allowed values, and is deliberately NOT used — but
    ///   **not for the reason the sibling GBNF code avoids enumeration**. The
    ///   llama.cpp path avoids it because enumerating CJK / dynamic literals
    ///   crashes that sampler at accept time (#597 / #599); that rationale is
    ///   specific to llama.cpp's grammar sampler and does not transfer to FM.
    ///   The actual reason here is simpler and structural: `.choice` carries no
    ///   option payload (`OutputSchema.Kind` is a payload-free marker), so the
    ///   allowed values are not reachable from this type at all. If a future
    ///   schema carries them, `anyOf:` becomes a legitimate option for FM even
    ///   though it stays forbidden for GBNF.
    ///
    /// - Throws: ``LLMError/generationFailed(description:)`` when the schema
    ///   cannot be built.
    static func generationSchema(from schema: OutputSchema) throws -> GenerationSchema {
      let leaf = DynamicGenerationSchema(type: String.self)
      let properties = schema.fields.map {
        DynamicGenerationSchema.Property(name: $0.name, schema: leaf)
      }
      let root = DynamicGenerationSchema(name: "TurnOutput", properties: properties)
      do {
        // Broad catch, not `catch let e as GenerationSchema.SchemaError`: the
        // initializer is declared with untyped `throws`, so a narrow catch would
        // let a non-`SchemaError` failure escape as a raw SDK error and lose the
        // grep-classifiable prefix below.
        return try GenerationSchema(root: root, dependencies: [])
      } catch {
        throw LLMError.generationFailed(
          description: "Foundation Models guided schema build failed — \(error)")
      }
    }

    /// Runs one schema-constrained turn.
    ///
    /// Returns the raw JSON text rather than a decoded value so
    /// ``JSONResponseParser`` — which owns the field contract for every backend
    /// — stays the single parse path. `rawContent.jsonString` is already
    /// schema-shaped, so the parser's repair pipeline simply has nothing to do.
    ///
    /// - Returns: The JSON text plus the turn's transcript entries, which the
    ///   caller feeds to the response-side token instrumentation.
    func respondGuided(
      session: LanguageModelSession, user: String, schema: GenerationSchema,
      options: GenerationOptions
    ) async throws -> (text: String, entries: ArraySlice<Transcript.Entry>) {
      let response = try await session.respond(
        to: user, schema: schema, includeSchemaInPrompt: Self.includeSchemaInPrompt,
        options: options)
      return (response.rawContent.jsonString, response.transcriptEntries)
    }
  }

#endif
