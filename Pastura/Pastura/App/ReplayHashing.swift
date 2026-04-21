import CryptoKit
import Foundation

/// Shared SHA-256 helper for replay-schema integrity checks.
///
/// Spec: `docs/specs/demo-replay-spec.md` §3.3 (preset drift detection).
///
/// Symmetry is load-bearing: ``YAMLReplayExporter`` writes
/// `preset_ref.yaml_sha256` by hashing the scenario's YAML string at
/// export time, and ``BundledPresetResolver`` re-hashes the bundled
/// preset YAML at load time to verify the demo still matches. Both
/// sides **must** hash the same bytes — i.e. `Data(string.utf8)` of the
/// UTF-8-decoded YAML, not the raw file bytes — otherwise a BOM or
/// CRLF difference on disk would silent-skip every bundled demo in
/// production.
///
/// Kept as a namespace enum (not a free function) so the call sites
/// read as `ReplayHashing.sha256Hex(yaml)` — signalling "replay
/// hashing" rather than "generic SHA-256" at the point of use.
nonisolated enum ReplayHashing {
  /// Returns the lowercase hex representation of `SHA-256(source.utf8)`.
  ///
  /// Both ``YAMLReplayExporter`` (for `preset_ref.yaml_sha256` emission)
  /// and ``BundledPresetResolver`` (for drift verification against
  /// shipped presets) route through this single entry point. Do not
  /// introduce a parallel hashing path — the E1 round-trip tests +
  /// spec §3.3 invariant depend on bit-for-bit agreement.
  static func sha256Hex(_ source: String) -> String {
    let digest = SHA256.hash(data: Data(source.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
