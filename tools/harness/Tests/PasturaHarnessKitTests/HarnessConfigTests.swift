import Testing

@testable import PasturaHarnessKit

@Suite(.timeLimit(.minutes(1)))
struct HarnessConfigTests {
  @Test func parsesRequiredAndDefaults() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "/tmp/s.yaml", "--model", "/tmp/m.gguf"
    ])
    #expect(config.scenarioPath == "/tmp/s.yaml")
    #expect(config.modelPath == "/tmp/m.gguf")
    #expect(config.outPath == nil)
    #expect(config.timeoutSeconds == 1800)
    #expect(config.quiet == false)
  }

  @Test func parsesAllOptions() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf",
      "--out", "run.jsonl", "--timeout", "60", "--quiet"
    ])
    #expect(config.outPath == "run.jsonl")
    #expect(config.timeoutSeconds == 60)
    #expect(config.quiet == true)
  }

  @Test func missingScenarioThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse(["--model", "m.gguf"])
    }
  }

  @Test func missingModelThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse(["--scenario", "s.yaml"])
    }
  }

  @Test func unknownFlagThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--bogus"
      ])
    }
  }

  @Test func nonNumericTimeoutThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--timeout", "soon"
      ])
    }
  }

  @Test func defaultsProfileToGemma() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf"
    ])
    #expect(config.profile == .gemma4E2B)
  }

  @Test func parsesExplicitProfile() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf",
      "--profile", "qwen-3-4b-q4-k-m"
    ])
    #expect(config.profile == .qwen34B)
  }

  @Test func unknownProfileThrows() {
    do {
      _ = try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--profile", "bogus"
      ])
      Issue.record("expected HarnessConfigError")
    } catch let error as HarnessConfigError {
      #expect(error.message.contains("bogus"))
      #expect(error.message.contains("gemma-4-e2b-q4-k-m"))
      #expect(error.message.contains("qwen-3-4b-q4-k-m"))
    } catch {
      Issue.record("expected HarnessConfigError, got \(error)")
    }
  }

  @Test func missingProfileValueThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--profile"
      ])
    }
  }

  @Test func defaultsBackendToLlamaCpp() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf"
    ])
    #expect(config.backend == .llamaCpp)
  }

  @Test func parsesFoundationModelsBackendWithoutModel() throws {
    // Foundation Models has no GGUF file — --model is optional and modelPath
    // stays empty.
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models"
    ])
    #expect(config.backend == .foundationModels)
    #expect(config.modelPath == "")
  }

  @Test func llamaCppBackendRequiresModel() {
    // The default (llama-cpp) backend still requires --model — guards the
    // pre-existing contract that `missingModelThrows` also covers.
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--backend", "llama-cpp"
      ])
    }
  }

  @Test func unknownBackendThrows() {
    do {
      _ = try HarnessConfig.parse([
        "--scenario", "s.yaml", "--backend", "bogus"
      ])
      Issue.record("expected HarnessConfigError")
    } catch let error as HarnessConfigError {
      #expect(error.message.contains("bogus"))
      #expect(error.message.contains("foundation-models"))
      #expect(error.message.contains("llama-cpp"))
    } catch {
      Issue.record("expected HarnessConfigError, got \(error)")
    }
  }

  @Test func missingBackendValueThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--backend"
      ])
    }
  }

  @Test func defaultsGuardrailsToDefault() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf"
    ])
    #expect(config.guardrails == .default)
  }

  @Test func parsesPermissiveGuardrails() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models",
      "--guardrails", "permissive"
    ])
    #expect(config.guardrails == .permissive)
  }

  @Test func unknownGuardrailsThrows() {
    do {
      _ = try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--guardrails", "bogus"
      ])
      Issue.record("expected HarnessConfigError")
    } catch let error as HarnessConfigError {
      #expect(error.message.contains("bogus"))
      #expect(error.message.contains("default"))
      #expect(error.message.contains("permissive"))
    } catch {
      Issue.record("expected HarnessConfigError, got \(error)")
    }
  }

  @Test func missingGuardrailsValueThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--guardrails"
      ])
    }
  }

  @Test func defaultsMaxResponseTokensAndGuidedGenerationToUnset() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--model", "m.gguf"
    ])
    #expect(config.maxResponseTokens == nil)
    #expect(config.guidedGeneration == false)
  }

  @Test func parsesMaxResponseTokens() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models",
      "--max-response-tokens", "512"
    ])
    #expect(config.maxResponseTokens == 512)
  }

  @Test func parsesGuidedGeneration() throws {
    let config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models",
      "--guided-generation"
    ])
    #expect(config.guidedGeneration == true)
  }

  @Test func nonNumericMaxResponseTokensThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf",
        "--max-response-tokens", "soon"
      ])
    }
  }

  @Test func zeroMaxResponseTokensThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf",
        "--max-response-tokens", "0"
      ])
    }
  }

  @Test func negativeMaxResponseTokensThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf",
        "--max-response-tokens", "-1"
      ])
    }
  }

  @Test func missingMaxResponseTokensValueThrows() {
    #expect(throws: HarnessConfigError.self) {
      try HarnessConfig.parse([
        "--scenario", "s.yaml", "--model", "m.gguf", "--max-response-tokens"
      ])
    }
  }

  @Test func foundationModelsRunLabelDefaultGuardrailsOnly() throws {
    var config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models"
    ])
    config.guardrails = .default
    #expect(config.foundationModelsRunLabel == "Apple Foundation Model (default)")
  }

  @Test func foundationModelsRunLabelPermissiveOnly() throws {
    var config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models"
    ])
    config.guardrails = .permissive
    #expect(config.foundationModelsRunLabel == "Apple Foundation Model (permissive)")
  }

  @Test func foundationModelsRunLabelPermissiveGuided() throws {
    var config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models"
    ])
    config.guardrails = .permissive
    config.guidedGeneration = true
    #expect(config.foundationModelsRunLabel == "Apple Foundation Model (permissive, guided)")
  }

  @Test func foundationModelsRunLabelPermissiveGuidedMaxTok() throws {
    var config = try HarnessConfig.parse([
      "--scenario", "s.yaml", "--backend", "foundation-models"
    ])
    config.guardrails = .permissive
    config.guidedGeneration = true
    config.maxResponseTokens = 512
    #expect(
      config.foundationModelsRunLabel
        == "Apple Foundation Model (permissive, guided, maxtok=512)")
  }
}
