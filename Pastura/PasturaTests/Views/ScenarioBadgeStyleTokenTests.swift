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
/// `@MainActor` is required twice over, which is why it is not removable: this
/// suite reads the `Color.*` statics directly, and the token members it calls
/// are themselves MainActor-isolated. Both arms of that second fact were
/// measured against `scripts/xcodebuild.sh build` (Pattern 8: the target, never
/// a `swiftc -typecheck` probe) — an in-module
/// `nonisolated func { _ = ScenarioBadgeStyle.tint.fillToken }` fails, and so
/// does marking the extension itself `nonisolated`, on all four `Color.*`
/// reads. So a build **does** discriminate here, per
/// `.claude/rules/swift-isolation.md` Pattern 5's non-test table row 2; its
/// cross-module corollary does not apply, because those reads are in-module.
/// The MainActor boundary is deliberate — the tokens are UI values whose only
/// legitimate caller is a View, while the pure `ScenarioBadge` →
/// `ScenarioBadgeStyle` mapping stays nonisolated and is covered by
/// ``ScenarioBadgeTests``.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenarioBadgeStyleTokenTests {

  @Test func tintReadsTheAccentPair() {
    // § 2.3: `moss` for fills, `mossDark` for accent text. On this badge's
    // composited wash the label measures ≈3.92:1; swapping it to `moss` drops
    // it to ≈2.51:1. (Not "white-on-accent" — no white foreground is involved
    // here; that framing belongs to the solid-fill cases in ADR-028.)
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

  // No "the two styles are not identical" test here, deliberately. Such a test
  // would have to compare two `Color.*` aliases, and alias `==` is instance-based
  // rather than value-based (a `PasturaDynamicColor`-backed alias compares by
  // provider, not by resolved components) — so it cannot see the token-value
  // collapse it would claim to guard. Probed: giving `moss` / `nightMoss` their
  // `inkSecondary` counterparts' hex left an alias-level `!=` assertion GREEN,
  // while `DesignTokensTests.mossPrimaryMatchesSpec` reddened on the same
  // mutation. Token values are that suite's contract; this one guards only which
  // token the badge reads.
}
