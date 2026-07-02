import Testing
import UIKit

@testable import Pastura

/// Unit coverage of ``PhaseGlyph``, the single source of truth for the
/// `PhaseType` → SF Symbol mapping used by the shared-scenario "What
/// happens" phase-step surface.
///
/// `@MainActor`: ``PhaseGlyph`` sits at the default (MainActor) isolation
/// (mirroring ``PhaseDisplayName``, swift-isolation.md Pattern 5), and
/// ``ScenarioSignaturePhase`` is `nonisolated` so it is callable from either
/// context — the suite matches ``PhaseGlyph`` so it can call directly.
@Suite("PhaseGlyph", .timeLimit(.minutes(1)))
@MainActor
struct PhaseGlyphTests {

  @Test func everyPhaseMapsToAValidSymbol() {
    for phase in PhaseType.allCases {
      let name = PhaseGlyph.symbolName(for: phase)
      #expect(
        UIImage(systemName: name) != nil,
        "PhaseGlyph.symbolName(for: \(phase)) = \"\(name)\" is not a valid SF Symbol")
    }
  }

  @Test func parityWithArtTileGlyph() {
    for phase in PhaseType.allCases {
      guard let signature = ScenarioSignaturePhase(phaseRawValue: phase.rawValue) else {
        continue
      }
      #expect(
        PhaseGlyph.symbolName(for: phase) == signature.sfSymbolName,
        "PhaseGlyph and ScenarioSignaturePhase diverge for \(phase)")
    }
  }
}
