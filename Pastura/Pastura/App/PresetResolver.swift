import Foundation

/// A bundled preset resolved to its parsed ``Scenario`` + integrity
/// SHA-256 as stored at load time.
///
/// Spec: `docs/specs/demo-replay-spec.md` §3.3.
///
/// Returned by ``PresetResolver/resolvePreset(id:)``. The `sha256`
/// field is computed via ``ReplayHashing/sha256Hex(_:)`` so it is
/// bit-for-bit identical to what ``YAMLReplayExporter`` wrote into a
/// recorded demo's `preset_ref.yaml_sha256` at curation time — the
/// drift guard compares these two values.
nonisolated public struct ResolvedPreset: Sendable, Equatable {
  public let scenario: Scenario
  /// Lowercase hex SHA-256 of the scenario's YAML source. Symmetric
  /// with ``YAMLReplayExporter``'s `preset_ref.yaml_sha256` emission.
  public let sha256: String

  public init(scenario: Scenario, sha256: String) {
    self.scenario = scenario
    self.sha256 = sha256
  }
}

/// Resolves a `preset_ref.id` (spec §3.2) to a shipped preset and
/// its integrity SHA-256. Used by ``BundledDemoReplaySource`` to
/// honour the spec §3.3 drift guard and spec §7.2 "preset-only, no
/// gallery shadowing" rule.
///
/// Conforming types **must** resolve only against shipped presets —
/// never against `ScenarioRepository`, which also holds
/// gallery-imported scenarios and would expose the collision-shadowing
/// risk named in spec §7.2. The default implementation
/// ``BundledPresetResolver`` enforces this structurally by reading
/// exclusively from `Bundle.main`.
nonisolated public protocol PresetResolver: Sendable {
  /// Returns the resolved preset for `id`, or `nil` if no shipped
  /// preset with that id exists in the resolver's source.
  ///
  /// Throws when a preset file is found but cannot be decoded as
  /// UTF-8 or parsed as a valid ``Scenario`` — these are
  /// build-integrity failures (the curator shipped a corrupt file),
  /// distinct from the "unknown id" miss case which is normal.
  ///
  /// Silent-skip semantics for drift are the **wrapper**'s concern
  /// (``BundledDemoReplaySource`` catches and logs); callers that
  /// want an actionable diagnostic (future
  /// `UserSimulationReplaySource`, spec §4.5) receive the throw.
  func resolvePreset(id: String) throws -> ResolvedPreset?
}

/// Production ``PresetResolver`` that reads shipped presets from the
/// app's main bundle.
///
/// **Gallery shadowing is structurally impossible**: this type reads
/// exclusively from `Bundle.main.url(forResource:withExtension:)` —
/// it does not touch ``ScenarioRepository`` and therefore cannot see
/// user-imported gallery scenarios that might collide on id. This
/// matches spec §7.2's mitigation requirement.
nonisolated public final class BundledPresetResolver: PresetResolver {
  /// Reads the bundled YAML for `id` and returns its contents. Returns
  /// `nil` when no file exists; throws when decode fails.
  ///
  /// Stored as a closure so tests can inject fixture-driven readers
  /// without writing real `Bundle` resources. Production callers use
  /// ``init(bundle:)`` which wires `Bundle.url(forResource:)`.
  private let yamlReader: @Sendable (String) throws -> String?

  /// Constructs a resolver backed by `bundle` (default `.main`).
  public init(bundle: Bundle = .main) {
    self.yamlReader = { id in
      guard let url = bundle.url(forResource: id, withExtension: "yaml") else {
        return nil
      }
      return try String(contentsOf: url, encoding: .utf8)
    }
  }

  /// Test-only initialiser injecting a custom YAML reader. Used by
  /// ``BundledPresetResolverTests`` to avoid touching `Bundle.main`
  /// in assertions about SHA + parse behaviour.
  internal init(yamlReader: @escaping @Sendable (String) throws -> String?) {
    self.yamlReader = yamlReader
  }

  public func resolvePreset(id: String) throws -> ResolvedPreset? {
    guard let yaml = try yamlReader(id) else { return nil }
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let sha256 = ReplayHashing.sha256Hex(yaml)
    return ResolvedPreset(scenario: scenario, sha256: sha256)
  }
}
