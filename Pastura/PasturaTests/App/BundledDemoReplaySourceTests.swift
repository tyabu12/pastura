import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct BundledDemoReplaySourceTests {

  // MARK: - Fixtures

  /// Minimal scenario YAML with 2 personas + 1 speak_all phase —
  /// matches the shape the fixture demo YAML targets.
  static let presetYAML = """
    id: wf
    name: Preset
    description: ''
    agents: 2
    rounds: 1
    context: ''
    personas:
      - name: Alice
        description: ''
      - name: Bob
        description: ''
    phases:
      - type: speak_all
        prompt: say
        output:
          statement: string
    """

  /// Stub `PresetResolver` that returns a single in-memory preset.
  /// Use this in tests that drive the resolver happy-path; the real
  /// `BundledPresetResolver` reads from `Bundle.main`, which we want
  /// to avoid coupling to here.
  struct StubPresetResolver: PresetResolver {
    let id: String
    let yaml: String
    let shouldThrow: Bool

    init(id: String, yaml: String, shouldThrow: Bool = false) {
      self.id = id
      self.yaml = yaml
      self.shouldThrow = shouldThrow
    }

    func resolvePreset(id: String) throws -> ResolvedPreset? {
      if shouldThrow { throw StubResolverError() }
      guard id == self.id else { return nil }
      let scenario = try ScenarioLoader().load(yaml: yaml)
      return ResolvedPreset(scenario: scenario, sha256: ReplayHashing.sha256Hex(yaml))
    }
  }

  struct StubResolverError: Error {}

  static func validDemoYAML(sha256: String, id: String = "wf") -> String {
    """
    schema_version: 1
    preset_ref:
      id: \(id)
      yaml_sha256: \(sha256)
    turns:
      - round: 1
        phase_index: 0
        phase_type: speak_all
        agent: Alice
        fields: { statement: 'hi' }
    """
  }

  static let testConfig = ReplayPlaybackConfig(
    speedMultiplier: 100.0,
    turnDelayMs: 20,
    codePhaseDelayMs: 5,
    loopBehaviour: .stopAfterLast,
    onComplete: .awaitTransitionSignal)

  // MARK: - Happy path

  @Test func loadsValidDemoWhenShaMatches() throws {
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yamls = [
      (name: "demo1", contents: Self.validDemoYAML(sha256: correctSHA))
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.count == 1)
    #expect(sources[0].scenario.id == "wf")
    // plannedEvents should produce the synthesised lifecycle + turn.
    let plan = sources[0].plannedEvents()
    #expect(plan.count == 3)
  }

  // MARK: - Silent-skip paths (spec §3.3 / §3.5)

  @Test func skipsDemoWithShaMismatch() throws {
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yamls = [
      (
        name: "drift",
        contents: Self.validDemoYAML(sha256: "deadbeef" + String(repeating: "00", count: 28))
      )
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsDemoWithUnsupportedSchemaVersion() throws {
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yaml = """
      schema_version: 9999
      preset_ref:
        id: wf
        yaml_sha256: \(correctSHA)
      turns: []
      """
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      [(name: "future", contents: yaml)],
      presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsDemoMissingSchemaVersion() throws {
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    // Spec §3.5 — missing schema_version treated as drift. Source
    // throws `YAMLReplaySourceError.unsupportedSchemaVersion(nil)`,
    // wrapper silent-skips.
    let yaml = """
      preset_ref:
        id: wf
        yaml_sha256: \(correctSHA)
      turns: []
      """
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      [(name: "noversion", contents: yaml)],
      presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsDemoWithUnknownPresetId() throws {
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yamls = [
      (name: "orphan", contents: Self.validDemoYAML(sha256: correctSHA, id: "other"))
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsDemoWithMissingPresetRef() throws {
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yaml = """
      schema_version: 1
      turns: []
      """
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      [(name: "nopresetref", contents: yaml)],
      presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsDemoWithMalformedYAML() throws {
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yamls = [
      (name: "garbage", contents: "\t\tnot: [valid: yaml::")
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func skipsWhenResolverThrows() throws {
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML, shouldThrow: true)
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let yamls = [
      (name: "demo", contents: Self.validDemoYAML(sha256: correctSHA))
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  // MARK: - Heterogeneous input

  @Test func validDemosLoadWhileInvalidOnesSkip() throws {
    let correctSHA = ReplayHashing.sha256Hex(Self.presetYAML)
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let yamls = [
      (name: "good", contents: Self.validDemoYAML(sha256: correctSHA)),
      (name: "drift", contents: Self.validDemoYAML(sha256: String(repeating: "a", count: 64))),
      (name: "other", contents: Self.validDemoYAML(sha256: correctSHA, id: "nope")),
      (name: "good2", contents: Self.validDemoYAML(sha256: correctSHA))
    ]
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      yamls, presetResolver: resolver, config: Self.testConfig)
    // Only the two validated demos survive; the drift + unknown-id
    // entries silent-skip.
    #expect(sources.count == 2)
  }

  // MARK: - Empty-bundle fallback

  @Test func emptyInputReturnsEmptySourcesArray() throws {
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let sources = BundledDemoReplaySource.loadFromYAMLs(
      [], presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }

  @Test func bundleWithoutDemoReplaysDirectoryReturnsEmpty() throws {
    // Real `Bundle.main` during tests has no `DemoReplays/` subdir
    // — Phase 2 default pre-#170. This exercises the production
    // enumeration path and asserts the §5.3 fallback trigger.
    let resolver = StubPresetResolver(id: "wf", yaml: Self.presetYAML)
    let sources = BundledDemoReplaySource.loadAll(
      bundle: .main, presetResolver: resolver, config: Self.testConfig)
    #expect(sources.isEmpty)
  }
}
