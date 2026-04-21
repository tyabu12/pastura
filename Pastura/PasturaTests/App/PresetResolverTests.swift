import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PresetResolverTests {

  // MARK: - Fixture

  /// Minimal valid scenario YAML used by tests that don't need to
  /// exercise the real bundled presets. Matches ``ScenarioLoader``'s
  /// required fields.
  private static let fixtureYAML = """
    id: fx
    name: Fixture
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

  // MARK: - resolvePreset

  @Test func returnsNilForUnknownId() throws {
    let resolver = BundledPresetResolver(yamlReader: { _ in nil })
    #expect(try resolver.resolvePreset(id: "nonexistent") == nil)
  }

  @Test func parsesScenarioAndHashesYAML() throws {
    let resolver = BundledPresetResolver(yamlReader: { id in
      id == "fx" ? Self.fixtureYAML : nil
    })
    let resolved = try resolver.resolvePreset(id: "fx")
    #expect(resolved != nil)
    #expect(resolved?.scenario.id == "fx")
    #expect(resolved?.scenario.personas.count == 2)
    // Sanity: SHA is lowercase hex of the expected length (SHA-256 = 64 chars).
    #expect(resolved?.sha256.count == 64)
    if let sha = resolved?.sha256 {
      #expect(sha == sha.lowercased())
    }
  }

  @Test func sha256IsDeterministicAcrossCalls() throws {
    let resolver = BundledPresetResolver(yamlReader: { _ in Self.fixtureYAML })
    let first = try resolver.resolvePreset(id: "any")
    let second = try resolver.resolvePreset(id: "any")
    #expect(first?.sha256 == second?.sha256)
  }

  @Test func throwsWhenReaderSurfacesDecodeFailure() throws {
    struct ReaderError: Error, Equatable {}
    let resolver = BundledPresetResolver(yamlReader: { _ in throw ReaderError() })
    #expect(throws: ReaderError.self) {
      _ = try resolver.resolvePreset(id: "any")
    }
  }

  @Test func throwsWhenYAMLCannotBeParsedAsScenario() throws {
    let resolver = BundledPresetResolver(yamlReader: { _ in
      "not valid scenario yaml"
    })
    #expect(throws: (any Error).self) {
      _ = try resolver.resolvePreset(id: "any")
    }
  }

  // MARK: - SHA symmetry with YAMLReplayExporter

  @Test func sha256MatchesYAMLReplayExporterForSamePreset() throws {
    // Spec §3.3's drift guard relies on the exporter (writing
    // `preset_ref.yaml_sha256`) and the resolver (re-hashing at load
    // time) agreeing bit-for-bit. If these drift, every bundled demo
    // silent-skips in production. This test pins the invariant.
    let yaml = Self.fixtureYAML
    let resolver = BundledPresetResolver(yamlReader: { _ in yaml })
    let resolved = try resolver.resolvePreset(id: "any")
    let exporterSHA = YAMLReplayExporter.sha256Hex(yaml)
    #expect(resolved?.sha256 == exporterSHA)
  }

  @Test func sha256MatchesSharedReplayHashingHelper() throws {
    // Belt-and-braces: both sides route through `ReplayHashing`, so
    // hashing the same string twice at the Swift level must also agree.
    let yaml = Self.fixtureYAML
    let resolver = BundledPresetResolver(yamlReader: { _ in yaml })
    let resolved = try resolver.resolvePreset(id: "any")
    #expect(resolved?.sha256 == ReplayHashing.sha256Hex(yaml))
  }

  // MARK: - Bundle.main production path (real shipped presets)

  @Test func resolvesRealBundledPresetFromBundleMain() throws {
    // Word Wolf ships bundled with the app — verify the production
    // `Bundle.main` path actually finds a preset. If this breaks,
    // either the bundle layout regressed or Bundle.main resolution
    // changed in the test host.
    let resolver = BundledPresetResolver()
    let resolved = try resolver.resolvePreset(id: "word_wolf")
    #expect(resolved != nil)
    #expect(resolved?.scenario.id == "word_wolf")
    // Exporter round-trip: the sha we compute at load time must equal
    // what `YAMLReplayExporter.sha256Hex` would emit for the same
    // bundled YAML string.
    if let resolved {
      let bundledURL = Bundle.main.url(forResource: "word_wolf", withExtension: "yaml")
      if let url = bundledURL {
        let bundledYAML = try String(contentsOf: url, encoding: .utf8)
        #expect(resolved.sha256 == YAMLReplayExporter.sha256Hex(bundledYAML))
      } else {
        Issue.record("Bundle.main could not locate word_wolf.yaml — bundle layout regression?")
      }
    }
  }
}
