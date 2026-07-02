import Foundation

/// Single source of truth for the `PhaseType` → SF Symbol mapping used by
/// the shared-scenario detail screen's "What happens" phase-flow surface.
///
/// 6 of the 10 kinds intentionally reuse the Browse art-tile glyphs
/// (``ScenarioSignaturePhase/sfSymbolName`` in `GalleryCatalogRow.swift`) to
/// keep one visual language across the two gallery surfaces — a parity test
/// (`PhaseGlyphTests`) guards the two mappings against drift. The remaining
/// 4 kinds (`speak_all`, `speak_each`, `assign`, `summarize`) have no
/// `ScenarioSignaturePhase` counterpart (that enum only maps the "headline"
/// mechanic kinds) and get their own symbol here.
///
/// Left MainActor-default (not `nonisolated`) to mirror ``PhaseDisplayName``
/// so composing helpers stay uniformly MainActor
/// (swift-isolation.md Pattern 5).
public enum PhaseGlyph {

  /// SF Symbol name for `phase`'s glyph badge.
  public static func symbolName(for phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return "bubble.left.and.bubble.right"
    case .speakEach: return "bubble.left"
    case .vote: return "checkmark.square"
    case .choose: return "arrow.triangle.branch"
    case .scoreCalc: return "chart.bar"
    case .assign: return "tag"
    case .eliminate: return "xmark.circle"
    case .summarize: return "list.bullet.rectangle"
    case .conditional: return "diamond"
    case .eventInject: return "bolt.fill"
    }
  }
}
