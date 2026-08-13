import Foundation
import Testing

@testable import Pastura

// MARK: - Configuration

/// Reads llama.cpp integration test settings from environment variables.
private enum LlamaCppConfig {
  /// Gate: must be exactly "1" to enable these tests.
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["LLAMACPP_INTEGRATION"] == "1"
  }

  /// Absolute path to a GGUF model file.
  /// Defaults to `~/Models/gemma-4-E2B-it-Q4_K_M.gguf` — matches
  /// `ModelRegistry.gemma4E2B.fileName` (canonical upstream casing).
  /// iOS Simulator's `fopen` matches paths case-sensitively even on
  /// case-insensitive macOS APFS volumes, so the casing here MUST track
  /// the actual filename on disk after `curl` from HuggingFace.
  static var modelPath: String {
    ProcessInfo.processInfo.environment["LLAMACPP_MODEL_PATH"]
      ?? "\(NSHomeDirectory())/Models/gemma-4-E2B-it-Q4_K_M.gguf"
  }
}

// MARK: - Tests

/// Integration tests that run against a real GGUF model via llama.cpp.
///
/// Gated by the `LLAMACPP_INTEGRATION` environment variable being `"1"`.
/// These tests are skipped in normal CI runs and require a local GGUF
/// model file.
///
/// Run with:
/// 1. Enable the scheme's env var. Either:
///    - Xcode → Edit Scheme → Run → Arguments → Environment Variables →
///      check `LLAMACPP_INTEGRATION`. Optionally check / edit
///      `LLAMACPP_MODEL_PATH` if your GGUF is not at the default location
///      (`$(HOME)/Models/gemma-4-E2B-it-Q4_K_M.gguf` — matches the
///      canonical HuggingFace filename; iOS Simulator's `fopen` is
///      case-sensitive even on case-insensitive APFS volumes).
///    - OR edit `Pastura.xcscheme` directly and flip `isEnabled="NO"` →
///      `isEnabled="YES"` on the `LLAMACPP_INTEGRATION` row.
/// 2. Run from Xcode (Cmd+U on this suite) OR from the CLI wrapper:
///    ```
///    source scripts/sim-dest.sh
///    scripts/xcodebuild.sh test \
///      -only-testing PasturaTests/LlamaCppIntegrationTests
///    ```
///
/// **Why scheme-toggle, not raw CLI env vars**: env vars set on the
/// `xcodebuild` command line are NOT automatically forwarded to the test
/// runner subprocess. The scheme env (with
/// `shouldUseLaunchSchemeArgsEnv="YES"` on the TestAction) is the standard
/// mechanism — same pattern as `OLLAMA_INTEGRATION` (see
/// `.claude/rules/xcodebuild-cli.md`).
@Suite(.serialized, .enabled(if: LlamaCppConfig.isEnabled))
struct LlamaCppIntegrationTests {

  // MARK: - Helpers

  // Not `private`: sibling `+*.swift` extensions of this suite call it
  // (`.claude/rules/testing.md` § "Splitting a Suite Across Files").
  func makeService() -> LlamaCppService {
    LlamaCppService(
      modelPath: LlamaCppConfig.modelPath,
      // Mirrors `ModelRegistry.gemma4E2B` — carries no Gemma marker (#1417).
      stopSequence: "<|im_end|>",
      // Stated, not defaulted. This suite drives the real Gemma GGUF, so the
      // `.chatML` default would have it parse under different markers than
      // production — exactly the descriptor/runtime divergence #1422 is about,
      // and invisible here because the suite asserts on parsed output.
      turnMarkers: ChatTurnMarkers(start: "<|turn>", end: "<turn|>"),
      modelIdentifier: "Gemma 4 E2B (Q4_K_M)",
      systemPromptSuffix: nil
    )
  }

  // MARK: - Test 1: Load/unload lifecycle

  @Test(.timeLimit(.minutes(2)))
  func loadAndUnloadLifecycle() async throws {
    let service = makeService()
    #expect(!service.isModelLoaded)

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Test 1b: loadModel idempotency (issue #114)

  @Test(.timeLimit(.minutes(3)))
  func loadModelTwiceIsIdempotent() async throws {
    // Regression test for issue #114: calling loadModel() while already loaded
    // must free the prior _model/_context, not leak ~3GB of Gemma buffers.
    // A memory leak is not directly assertable without Instruments, so this
    // test verifies the happy-path invariants that lock in the defensive
    // unload: both loads succeed, state stays consistent, and the final
    // unload completes cleanly (a stale dangling pointer would crash here).
    let service = makeService()

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.loadModel()
    #expect(service.isModelLoaded)

    try await service.unloadModel()
    #expect(!service.isModelLoaded)
  }

  // MARK: - Test 2: Simple generation

  @Test(.timeLimit(.minutes(3)))
  func simpleGenerationProducesOutput() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: "You are a helpful assistant. Respond in JSON with a 'greeting' field.",
      user: "Say hello."
    )

    #expect(!result.isEmpty, "Generation produced empty output")
    #expect(result.count > 5, "Generation suspiciously short: \(result)")
  }

  // MARK: - Test 3: JSON output parses via JSONResponseParser

  @Test(.timeLimit(.minutes(3)))
  func jsonResponseParserHandlesOutput() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    )

    let parsed = try JSONResponseParser().parse(result)
    let statement = parsed.statement ?? ""
    #expect(!statement.isEmpty, "Parsed statement is empty. Raw: \(result)")
  }

  // MARK: - Test 4: Generation terminates cleanly, with no template-token leak

  @Test(.timeLimit(.minutes(3)))
  func generationTerminatesWithoutTemplateTokenLeak() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let result = try await service.generate(
      system: """
        You are a character in a game. Respond ONLY with a JSON object.
        Required format: {"statement": "your statement here"}
        """,
      user: "Introduce yourself briefly."
    )

    // Leak check. When the stop path FIRES the sentinel is truncated before
    // `generate` returns, so this passes; it fails only on a spelled-out
    // `<|im_end|>` the stop path did NOT catch. ChatML-shaped only — a
    // Gemma-shaped hallucination (`<|turn>` / `<turn|>`) is matched nowhere
    // (#1422). Gemma's normal termination is EOG, and the length bound below is
    // only a runaway proxy for it: it would notice termination failing outright,
    // but cannot tell EOG from the #907 caught-grammar stop, nor either from a
    // naturally short answer.
    #expect(
      !result.contains("<|im_end|>"),
      "Raw output contains <|im_end|> — stop token not working. Output: \(result)"
    )
    // Output should be well under maxTokens (1000 tokens ≈ 4000 chars).
    // A runaway generation hitting maxTokens indicates termination failed.
    #expect(
      result.count < 2000,
      "Output suspiciously long (\(result.count) chars) — may have hit maxTokens"
    )
  }

  // MARK: - Test 6: Multiple sequential generations (KV cache clear)

  @Test(.timeLimit(.minutes(5)))
  func multipleSequentialGenerations() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    for idx in 1...3 {
      let result = try await service.generate(
        system: "Reply with JSON: {\"number\": \"\(idx)\"}",
        user: "What number?"
      )
      #expect(!result.isEmpty, "Generation \(idx) produced empty output")
    }
  }

  // MARK: - Test 7: Grammar-constrained output (#194 PR#b)

  /// Feeds the `prisoners_dilemma` `choose` phase shape through
  /// grammar-constrained sampling and asserts the output parses without
  /// invoking the repair pipeline — i.e., the grammar itself enforced
  /// valid JSON structure and an in-set `action` value.
  ///
  /// Catches tokenizer ↔ grammar interactions that the pure-transformation
  /// `GBNFGrammarBuilderTests` cannot reach (e.g., Gemma's chat-template
  /// bytes colliding with the GBNF string class, or grammar masking that
  /// is too restrictive for the model's sampled path).
  @Test(.timeLimit(.minutes(3)))
  func grammarConstrainedProducesSchemaValidJSON() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .choose, prompt: "…",
          outputSchema: ["action": "string", "inner_thought": "string"],
          options: ["cooperate", "betray"])))

    let result = try await service.generate(
      system: """
        あなたは囚人のジレンマに挑むプレイヤーです。JSONのみで答えてください。
        形式: {"action": "cooperate"|"betray", "inner_thought": "あなたの本音"}
        """,
      user: "相手と協力するか裏切るか選んでください。",
      schema: schema)

    // 1. Parse without repair — grammar should make the raw output
    //    directly parseable, so the parser reports `repairKind == nil`.
    let parsed = try JSONResponseParser().parse(
      result, expectedKeys: Set(schema.fields.map(\.name)))
    #expect(
      parsed.repairKind == nil,
      "grammar-constrained output should not need repair, got \(parsed.repairKind ?? "?"); raw=\(result)"
    )

    // 2. action must be one of the options (grammar-enforced, not
    //    runtime-validated). If this fails, the grammar chain did not
    //    actually constrain sampling — the exact regression wiring one
    //    of the two sampler call paths but not the other would produce.
    let action = parsed.0.fields["action"]
    #expect(
      action == "cooperate" || action == "betray",
      "action must be grammar-constrained to options, got \(action ?? "nil")")

    // 3. inner_thought must contain Japanese characters (sanity check
    //    that `[^"\\]` string production accepted UTF-8 / CJK content
    //    — Critic Axis 1).
    let thought = parsed.0.fields["inner_thought"] ?? ""
    let hasJapanese = thought.unicodeScalars.contains { scalar in
      (0x3000...0x9FFF).contains(scalar.value)  // Kanji + kana block
        || (0xFF00...0xFFEF).contains(scalar.value)  // Fullwidth forms
    }
    #expect(hasJapanese, "expected Japanese content in inner_thought, got: \(thought)")
  }

  // MARK: - Test 8: Single-field grammar-constrained output (#334)

  /// Issue #334 repro: minimal single-field `{statement: string}` schemas
  /// historically triggered an uncaught `std::runtime_error` from
  /// `llama_grammar_accept_token`. After the SafeSampler bridge this should
  /// either (a) complete normally OR (b) surface as
  /// `LLMError.generationFailed` — never crash the process.
  ///
  /// Note: this test exercises the **success path**. The repro from
  /// issue #334 was on a specific (model, prompt, seed) combination; the
  /// non-deterministic sampling means a single run may or may not hit the
  /// crash trigger. The success-path assertions cover the case where the
  /// new wrapper does not interfere with normal generation. If the crash
  /// trigger fires on this run, the assertion that the call returns
  /// **without aborting the process** is itself the regression guard — a
  /// pre-fix build would `std::terminate` instead of throwing.
  ///
  /// User-run on device: `LLAMACPP_INTEGRATION=1` plus a Gemma 4 E2B GGUF
  /// at the path described by `LLAMACPP_MODEL_PATH`. CI does not exercise
  /// this; see `docs/decisions/ADR-002.md` §12.10 for the verification
  /// procedure.
  @Test(.timeLimit(.minutes(3)))
  func singleFieldGrammarRecoverableUnderRealModel() async throws {
    let service = makeService()
    try await service.loadModel()
    defer { Task { try? await service.unloadModel() } }

    let schema = try #require(
      OutputSchema.from(
        phase: Phase(
          type: .speakAll, prompt: "…",
          outputSchema: ["statement": "string"])))

    // The system prompt + user prompt mirror issue #334's repro YAML
    // ("Say one word.") — short prompt + single-field schema is the exact
    // shape that surfaced the crash.
    do {
      let result = try await service.generate(
        system:
          "You are a helpful assistant. Respond ONLY with JSON: {\"statement\": \"…\"}",
        user: "Say one word.",
        schema: schema)

      // Success path: the call completed, so the SafeSampler bridge either
      // never saw a crash on this run OR caught one and... we wouldn't be
      // here. Verify the output at least parses — a partially-corrupted
      // response would surface as a parse failure, not a crash.
      let parsed = try JSONResponseParser().parse(
        result, expectedKeys: Set(schema.fields.map(\.name)))
      #expect(parsed.0.fields["statement"] != nil)
    } catch LLMError.samplerCrashCaught(let description) {
      // The SafeSampler bridge caught a C++ exception and surfaced it as
      // the retryable `.samplerCrashCaught` (#885). The test passes —
      // process did NOT crash. `description` is the raw caught `what()`
      // (the "Sampler crash caught:" prefix now lives in
      // `LLMError.errorDescription`, not the associated value).
      #expect(
        !description.isEmpty,
        "SafeSampler caught a crash but surfaced an empty what(): \(description)")
    } catch LLMError.generationFailed(let description) {
      // A non-sampler generation failure (e.g. genuine backend error) is
      // still acceptable here — the point of this test is that the
      // process did not crash. Kept as a distinct arm so a sampler crash
      // that regressed back to `.generationFailed` would surface loudly.
      Issue.record("generation failed without a caught sampler crash: \(description)")
    }
  }
}
