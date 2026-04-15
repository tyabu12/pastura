import Foundation

/// Canonical source-type tags stored in `ScenarioRecord.sourceType`.
///
/// Used by the Data layer's readonly guard and the App layer's gallery flow
/// to distinguish how a scenario entered the local DB. A centralized
/// constant avoids scattering the string literal across call sites — a
/// typo anywhere becomes a compile error rather than a silent bypass.
nonisolated public enum ScenarioSourceType {
  /// Row imported from the Share Board (read-only gallery).
  public static let gallery: String = "gallery"
}
