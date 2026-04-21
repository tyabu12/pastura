import Foundation
import Yams
import os

/// Wrapping ``ReplaySource`` that loads pre-recorded demos shipped in
/// the app bundle, verifies their `preset_ref.yaml_sha256` against the
/// currently-shipped preset, and silent-skips on any mismatch or
/// unsupported-schema failure per spec §3.3 / §3.5.
///
/// Spec: `docs/specs/demo-replay-spec.md` §4.4.
///
/// **Preset-only resolution (spec §7.2).** Only bundled presets are
/// acceptable `preset_ref.id` targets — gallery scenarios live in the
/// DB and are structurally unreachable from ``BundledPresetResolver``,
/// so a gallery entry whose id happens to collide with a bundled
/// preset cannot shadow the preset from a demo replay's perspective.
///
/// **Silent-skip posture (spec §3.3).** Drift at runtime (a demo
/// referencing a preset whose bytes no longer match the recorded
/// SHA) logs a diagnostic and drops the demo from the rotation. A
/// louder error would be worse than a shorter rotation on the
/// ambient DL-time surface — the CI drift guard (Issue #170) catches
/// mismatches at build time as the primary defence.
nonisolated public final class BundledDemoReplaySource: ReplaySource {

  // MARK: - Stored

  private let inner: YAMLReplaySource

  // MARK: - ReplaySource

  public var scenario: Scenario { inner.scenario }
  public func events() -> AsyncStream<SimulationEvent> { inner.events() }
  public func plannedEvents() -> [PacedEvent] { inner.plannedEvents() }

  // MARK: - Init

  private init(inner: YAMLReplaySource) {
    self.inner = inner
  }

  // MARK: - Logging

  private static let logger = Logger(
    subsystem: "com.tyabu12.Pastura", category: "BundledDemoReplaySource")

  // MARK: - Bundle loading

  /// Enumerates demo YAMLs under `Resources/DemoReplays/` in `bundle`,
  /// validates each, and returns the subset that passed all checks.
  ///
  /// Silent-skip cases (all logged via `os.Logger` at `notice` level):
  /// - `DemoReplays/` directory absent from the bundle (Phase 2 default
  ///   state before Issue #170 populates it — returns `[]`).
  /// - YAML file unreadable as UTF-8.
  /// - YAML malformed / missing `preset_ref.id` or `yaml_sha256`.
  /// - `preset_ref.id` not a shipped preset (unknown, gallery-only,
  ///   or typo).
  /// - `preset_ref.yaml_sha256` does not match the resolved preset's
  ///   current bytes — drift per spec §3.3.
  /// - Demo's `schema_version` unsupported — `YAMLReplaySource` throws
  ///   `YAMLReplaySourceError.unsupportedSchemaVersion`; wrapper
  ///   catches per spec §3.5.
  public static func loadAll(
    bundle: Bundle = .main,
    presetResolver: any PresetResolver = BundledPresetResolver(),
    config: ReplayPlaybackConfig = .demoDefault
  ) -> [BundledDemoReplaySource] {
    let yamls = enumerateDemoYAMLs(bundle: bundle)
    return loadFromYAMLs(yamls, presetResolver: presetResolver, config: config)
  }

  /// Test seam: construct from an already-enumerated list of
  /// `(filename, yaml-contents)` pairs. Production callers go through
  /// ``loadAll(bundle:presetResolver:config:)``.
  internal static func loadFromYAMLs(
    _ yamls: [(name: String, contents: String)],
    presetResolver: any PresetResolver,
    config: ReplayPlaybackConfig
  ) -> [BundledDemoReplaySource] {
    yamls.compactMap { yaml in
      loadOne(
        name: yaml.name, contents: yaml.contents,
        presetResolver: presetResolver, config: config)
    }
  }

  /// Loads a single demo YAML. Returns nil on any validation failure,
  /// logging the reason.
  ///
  /// swiftlint:disable:next function_body_length
  private static func loadOne(
    name: String, contents: String,
    presetResolver: any PresetResolver,
    config: ReplayPlaybackConfig
  ) -> BundledDemoReplaySource? {
    // Parse just `preset_ref` first — we need its `id` to resolve the
    // scenario and its `yaml_sha256` for drift verification before
    // handing off to `YAMLReplaySource`'s stricter validation.
    let presetRef: (id: String, sha256: String)
    do {
      guard let parsed = try parsePresetRef(yaml: contents) else {
        logger.notice("Demo replay '\(name, privacy: .public)' missing preset_ref — skipping.")
        return nil
      }
      presetRef = parsed
    } catch {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' malformed YAML: \(error.localizedDescription, privacy: .public) — skipping."
      )
      return nil
    }

    // Resolve the preset the demo claims to target.
    let resolved: ResolvedPreset?
    do {
      resolved = try presetResolver.resolvePreset(id: presetRef.id)
    } catch {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' preset resolver failed for id '\(presetRef.id, privacy: .public)': \(error.localizedDescription, privacy: .public) — skipping."
      )
      return nil
    }
    guard let resolvedPreset = resolved else {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' preset id '\(presetRef.id, privacy: .public)' not found in shipped presets — skipping."
      )
      return nil
    }

    // SHA drift check (spec §3.3).
    guard resolvedPreset.sha256 == presetRef.sha256 else {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' SHA mismatch for preset '\(presetRef.id, privacy: .public)' (recorded \(presetRef.sha256, privacy: .public) vs resolved \(resolvedPreset.sha256, privacy: .public)) — skipping."
      )
      return nil
    }

    // Hand off to `YAMLReplaySource` for full validation (schema
    // version, turns, code_phase_events). Spec §3.5 mandates silent
    // skip on `unsupportedSchemaVersion`.
    do {
      let inner = try YAMLReplaySource(
        yaml: contents, scenario: resolvedPreset.scenario, config: config)
      return BundledDemoReplaySource(inner: inner)
    } catch YAMLReplaySourceError.unsupportedSchemaVersion(let version) {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' unsupported schema version \(version ?? -1, privacy: .public) — skipping."
      )
      return nil
    } catch {
      logger.notice(
        "Demo replay '\(name, privacy: .public)' YAMLReplaySource rejected it: \(error.localizedDescription, privacy: .public) — skipping."
      )
      return nil
    }
  }

  private static func enumerateDemoYAMLs(bundle: Bundle) -> [(name: String, contents: String)] {
    // `urls(forResourcesWithExtension:subdirectory:)` returns nil when
    // the directory doesn't exist in the bundle. Phase 2 default: no
    // `DemoReplays/` shipped until Issue #170 populates it, so `[]`
    // triggers the host view's §5.3 progress-bar-only fallback.
    guard
      let urls = bundle.urls(
        forResourcesWithExtension: "yaml", subdirectory: "DemoReplays")
    else {
      return []
    }
    return urls.compactMap { url in
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        logger.notice(
          "Demo replay at '\(url.path, privacy: .public)' not readable as UTF-8 — skipping."
        )
        return nil
      }
      return (name: url.deletingPathExtension().lastPathComponent, contents: contents)
    }
  }

  private static func parsePresetRef(yaml: String) throws -> (id: String, sha256: String)? {
    guard let root = try Yams.load(yaml: yaml) as? [String: Any] else { return nil }
    guard let presetRef = root["preset_ref"] as? [String: Any] else { return nil }
    guard let identifier = presetRef["id"] as? String,
      let sha256 = presetRef["yaml_sha256"] as? String
    else {
      return nil
    }
    return (id: identifier, sha256: sha256)
  }
}
