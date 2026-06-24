import SwiftUI
import Testing

@testable import Pastura

/// Change-detector tripwire for the simulation-controls polish tokens
/// (``SimulationPlayButtonMetrics`` + ``SimulationLeaveSheetTokens``).
///
/// These assertions mirror the source-of-truth constants **by design**
/// (ADR-009 § "Change-detector tripwire"). The rendered appearance is
/// code-review-gated only; a failure here does NOT mean a bug — it means a
/// gated visual token drifted in a refactor, and the editor must confirm the
/// change was intended before updating the expected value.
///
/// `@MainActor` because comparing `Color` tokens hits MainActor-isolated
/// conformance lookup under default-actor isolation (swift-isolation
/// Pattern 5); MainActor can still read the nonisolated-free token enums.
@Suite("SimulationControlsTokens", .timeLimit(.minutes(1)))
@MainActor
struct SimulationControlsTokenTests {

  // MARK: - Play/pause button

  @Test func playButtonGeometryUnchanged() {
    // 34pt circle / 14pt glyph — user-confirmed via mockup.
    #expect(SimulationPlayButtonMetrics.diameter == 34)
    #expect(SimulationPlayButtonMetrics.glyphPointSize == 14)
  }

  @Test func playButtonFillsUnchanged() {
    #expect(SimulationPlayButtonMetrics.enabledFill == .mossDark)
    #expect(SimulationPlayButtonMetrics.disabledFill == .disabledText)
    #expect(SimulationPlayButtonMetrics.glyphColor == .white)
  }

  // MARK: - Leave sheet

  @Test func leaveSheetCautionUsesWarningFamily() {
    #expect(SimulationLeaveSheetTokens.cautionFill == .warningSoft)
    #expect(SimulationLeaveSheetTokens.cautionText == .warningInk)
    #expect(SimulationLeaveSheetTokens.cautionBorder == .warning)
  }

  /// The load-bearing semantic decision: "keep running" is a *caution*
  /// (`warning`), NOT a *destructive* action (`danger`). Guards against a
  /// silent swap back to the red/danger family (critic round-1 Axis 3).
  @Test func leaveSheetCautionIsNotDanger() {
    #expect(SimulationLeaveSheetTokens.cautionFill != .dangerSoft)
    #expect(SimulationLeaveSheetTokens.cautionText != .dangerInk)
    #expect(SimulationLeaveSheetTokens.cautionBorder != .danger)
  }

  @Test func leaveSheetCancelStaysNeutral() {
    #expect(SimulationLeaveSheetTokens.cancelText == .inkSecondary)
    #expect(SimulationLeaveSheetTokens.cancelBorder == .rule)
  }
}
