import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for `PhaseTypeLabel`'s colour routing
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens"). Sibling in shape to
/// ``ScenarioBadgeStyleTokenTests`` and ``ResultsPillTokenTests``.
///
/// **Why this exists, concretely.** ``PhaseTypeLabelTests`` checks the
/// LLM-vs-code *structure* — every LLM phase picks one side, every code phase
/// the other — and is deliberately blind to *which token* each side is. That
/// blindness has already cost something: #1327 repointed the LLM arm from `moss`
/// to `mossOnWash`, the structural suite stayed green, and that suite's own doc
/// comment went on naming `Color.moss` as the label colour until #1408. Closing
/// the gap is why `badgeText` / `badgeFill` are internal rather than `private`.
///
/// **Fill and label are pinned together on purpose.** They were one token per
/// arm until #1327 / #1408 split them, so the interesting regression is not
/// either accessor drifting alone but the two silently re-converging under a
/// well-meaning "these are the same, simplify" edit.
///
/// **A failure here is not a bug.** It means a code-review-gated token drifted.
/// Confirm the change was intended and passed review, then update the
/// expectation.
///
/// **Why assert the alias, not the hex** — `view-testing.md`'s reasoning, plus
/// one thing specific to the code arm: `inkOnWash` and `inkSecondary` are **byte-identical
/// in light**, so a value comparison could not tell them apart at all. `Color`
/// compares by provider instance, which is what makes the arm meaningful and
/// equally why no "these two differ" assertion appears anywhere here.
///
/// Token *values* are `DesignTokensTests`' contract and the contrast claims are
/// `DesignTokensTests+InkOnWash`'s / `+MossOnWash`'s. This suite guards only the
/// routing.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PhaseTypeLabelTokenTests {

  /// `.speakAll` is LLM-driven and `.scoreCalc` is not — the split
  /// ``PhaseTypeLabelTests`` pins exhaustively across `PhaseType.allCases`, so
  /// one representative per side is enough here.
  private let llm = PhaseTypeLabel(phaseType: .speakAll)
  private let code = PhaseTypeLabel(phaseType: .scoreCalc)

  @Test func llmArmRoutesToTheMossWashPair() {
    #expect(llm.badgeFill == Color.moss)
    #expect(llm.badgeText == Color.mossOnWash)
  }

  @Test func codeArmRoutesToTheInkWashPair() {
    // The fill stays `inkSecondary`; only the label moved (#1408). Before that
    // both were `inkSecondary`, and in light they still resolve to the same
    // value — so this pair of expectations is the only thing standing between
    // the split and a silent re-merge.
    #expect(code.badgeFill == Color.inkSecondary)
    #expect(code.badgeText == Color.inkOnWash)
  }
}
