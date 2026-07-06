import Foundation

/// Single source of truth for the `PhaseType` → SF Symbol mapping used by
/// the shared-scenario detail screen's "What happens" phase-step surface.
///
/// 6 of the 12 kinds intentionally reuse the Browse art-tile glyphs
/// (``ScenarioSignaturePhase/sfSymbolName`` in `GalleryCatalogRow.swift`) to
/// keep one visual language across the two gallery surfaces — a parity test
/// (`PhaseGlyphTests`) guards the two mappings against drift. The remaining
/// 6 kinds (`speak_all`, `speak_each`, `assign`, `summarize`, `reflect`,
/// `whisper`) have no `ScenarioSignaturePhase` counterpart (that enum only
/// maps the "headline" mechanic kinds) and get their own symbol here.
///
/// Left MainActor-default (not `nonisolated`) to mirror ``PhaseDisplayName``
/// so composing helpers stay uniformly MainActor
/// (swift-isolation.md Pattern 5).
public enum PhaseGlyph {

  // Pure name-mapping switch (one line per phase type). The 13-case count
  // exceeds SwiftLint's cyclomatic threshold but carries no branching logic.
  // swiftlint:disable cyclomatic_complexity
  /// SF Symbol name for `phase`'s glyph badge.
  public static func symbolName(for phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return "bubble.left.and.bubble.right"
    case .speakEach: return "bubble.left"
    case .vote: return "checkmark.square"
    case .choose: return "arrow.triangle.branch"
    case .reflect: return "square.and.pencil"
    case .whisper: return "ear"
    case .scoreCalc: return "chart.bar"
    case .assign: return "tag"
    case .eliminate: return "xmark.circle"
    case .summarize: return "list.bullet.rectangle"
    case .conditional: return "diamond"
    case .eventInject: return "bolt.fill"
    case .relationshipUpdate: return "person.2"
    }
  }
  // swiftlint:enable cyclomatic_complexity
}
