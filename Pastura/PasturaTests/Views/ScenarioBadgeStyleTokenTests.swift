import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for the scenario badge's colour contract
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens").
///
/// **Why this is not tautological.** The badge is a purely visual surface with
/// no logic to assert and no automated visual coverage — ADR-009 rules out
/// snapshot tests, and the screenshot tour never lands on a badged Browse card,
/// so until #1296 its tokens were code-review-gated *only*. That gate already
/// failed once in the direction this suite guards: #1283 tokenized two badge
/// renderers in parallel on the assumption both were live, which is how a
/// byte-identical duplicate survived long enough to need retiring. One renderer
/// remains and its tokens now live in one place; this pins them there.
///
/// **A failure here is not a bug.** It means a code-review-gated token drifted —
/// most likely in an unrelated refactor or an ADR-028 pairing slice. Confirm the
/// change was intended and passed review, then update the expectation.
///
/// **Why assert the alias, not the hex.** `Color.moss` and `Color.inkSecondary`
/// are trait-resolving (`PasturaDynamicPalette`); `Color.mossDark` is still
/// fixed. Comparing against the alias keeps this suite green when ADR-028 pairs
/// `mossDark`, while still reddening if a token is swapped for a *different*
/// one — which is the actual drift being guarded.
///
/// `@MainActor` because the token members are MainActor-isolated: they read the
/// `Color.*` statics, which are declared in a default-MainActor layer
/// (`.claude/rules/swift-isolation.md` Pattern 5, fix order 1). The
/// `ScenarioBadge` → `ScenarioBadgeStyle` mapping itself stays nonisolated and
/// is covered by ``ScenarioBadgeTests``.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenarioBadgeStyleTokenTests {

  @Test func tintReadsTheAccentPair() {
    // § 2.3: `moss` for fills, `mossDark` for accent text. Swapping the label
    // to `moss` would drop white-on-accent contrast below AA.
    #expect(ScenarioBadgeStyle.tint.fillToken == Color.moss)
    #expect(ScenarioBadgeStyle.tint.labelToken == Color.mossDark)
  }

  @Test func secondaryReadsTheNeutralTokenForBoth() {
    #expect(ScenarioBadgeStyle.secondary.fillToken == Color.inkSecondary)
    #expect(ScenarioBadgeStyle.secondary.labelToken == Color.inkSecondary)
  }

  @Test func washOpacitiesAreTheReviewedValues() {
    #expect(ScenarioBadgeStyle.tint.fillOpacity == 0.2)
    #expect(ScenarioBadgeStyle.secondary.fillOpacity == 0.15)
  }

  /// The two styles must stay visually distinguishable. Independent of the
  /// assertions above: those would all still pass if a future retune gave
  /// `moss` and `inkSecondary` the same value, collapsing the tint/secondary
  /// distinction the badge relies on to separate "changed" from "provenance".
  @Test func theTwoStylesAreNotIdentical() {
    #expect(ScenarioBadgeStyle.tint.fillToken != ScenarioBadgeStyle.secondary.fillToken)
    #expect(ScenarioBadgeStyle.tint.labelToken != ScenarioBadgeStyle.secondary.labelToken)
  }
}
