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
}
