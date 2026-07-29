import SwiftUI
import Testing
import UIKit

@testable import Pastura

// §2.9 dark-mode token-pair tests. Protects ADR-028's mechanism decision:
// `PasturaDynamicColor` resolves a light/dark pair through a `UIColor` dynamic
// provider, and the 57 paired `Color.*` aliases are actually wired to it.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` (required for auto-synth conformance lookup from these
// assertions — `swift-isolation.md` Pattern 5) and `.timeLimit(.minutes(1))`.
extension DesignTokensTests {

  // MARK: - Mechanism gate (UIColor dynamic provider)
  //
  // This is the load-bearing observation of ADR-028's mechanism claim. It goes
  // through `UIColor.resolvedColor(with:)` rather than SwiftUI, because that is
  // deterministic and does not pass through `Color.Resolved`, which
  // `DesignTokens.swift` documents as linear-light and lossy. If THIS reddens,
  // the mechanism itself is wrong.

  @Test func dynamicPairResolvesEachSideViaTraitCollection() {
    let pair = PasturaDynamicColor(
      light: PasturaPalette.ink, dark: PasturaPalette.nightInk)

    let resolvedLight = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .light))
    let resolvedDark = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .dark))

    #expect(sRGBComponentsMatch(resolvedLight, PasturaPalette.ink))
    #expect(sRGBComponentsMatch(resolvedDark, PasturaPalette.nightInk))
  }

  /// `.unspecified` must fall to the light value — the provider branches on
  /// `== .dark`, so an inverted condition would surface here.
  @Test func dynamicPairFallsToLightOnUnspecifiedTrait() {
    let pair = PasturaDynamicColor(
      light: PasturaPalette.moss, dark: PasturaPalette.nightMoss)

    let resolved = pair.uiColor.resolvedColor(
      with: UITraitCollection(userInterfaceStyle: .unspecified))

    #expect(sRGBComponentsMatch(resolved, PasturaPalette.moss))
  }

  // MARK: - Pair table (matches design-system.md §2.9)

  @Test func declaredPairsMatchTheDesignSystemTable() {
    #expect(PasturaDynamicPalette.screenBackground.dark == PasturaPalette.nightBackground)
    #expect(PasturaDynamicPalette.bubbleBackground.dark == PasturaPalette.nightBubble)
    #expect(PasturaDynamicPalette.whisperBubble.dark == PasturaPalette.nightWhisperBubble)
    #expect(PasturaDynamicPalette.ink.dark == PasturaPalette.nightInk)
    #expect(PasturaDynamicPalette.inkSecondary.dark == PasturaPalette.nightInkSecondary)
    #expect(PasturaDynamicPalette.muted.dark == PasturaPalette.nightMuted)
    #expect(PasturaDynamicPalette.rule.dark == PasturaPalette.nightRule)
    #expect(PasturaDynamicPalette.moss.dark == PasturaPalette.nightMoss)
    #expect(PasturaDynamicPalette.info.dark == PasturaPalette.nightInfo)
    #expect(PasturaDynamicPalette.infoSoft.dark == PasturaPalette.nightInfoSoft)
    #expect(PasturaDynamicPalette.infoInk.dark == PasturaPalette.nightInfoInk)
    #expect(PasturaDynamicPalette.success.dark == PasturaPalette.nightSuccess)
    #expect(PasturaDynamicPalette.successSoft.dark == PasturaPalette.nightSuccessSoft)
    #expect(PasturaDynamicPalette.successInk.dark == PasturaPalette.nightSuccessInk)
    #expect(PasturaDynamicPalette.warning.dark == PasturaPalette.nightWarning)
    #expect(PasturaDynamicPalette.warningSoft.dark == PasturaPalette.nightWarningSoft)
    #expect(PasturaDynamicPalette.warningInk.dark == PasturaPalette.nightWarningInk)
    #expect(PasturaDynamicPalette.danger.dark == PasturaPalette.nightDanger)
    #expect(PasturaDynamicPalette.dangerSoft.dark == PasturaPalette.nightDangerSoft)
    #expect(PasturaDynamicPalette.dangerInk.dark == PasturaPalette.nightDangerInk)
    #expect(PasturaDynamicPalette.hover.dark == PasturaPalette.nightHover)
    #expect(PasturaDynamicPalette.pressed.dark == PasturaPalette.nightPressed)
    #expect(PasturaDynamicPalette.selected.dark == PasturaPalette.nightSelected)
    #expect(PasturaDynamicPalette.focusRing.dark == PasturaPalette.nightFocusRing)
    #expect(PasturaDynamicPalette.disabledText.dark == PasturaPalette.nightDisabledText)
    #expect(
      PasturaDynamicPalette.disabledBackground.dark == PasturaPalette.nightDisabledBackground)
    #expect(PasturaDynamicPalette.metaBaseL1.dark == PasturaPalette.nightMetaBaseL1)
    #expect(PasturaDynamicPalette.metaStrongL1.dark == PasturaPalette.nightMetaStrongL1)
    #expect(PasturaDynamicPalette.metaDotOnL1.dark == PasturaPalette.nightMetaDotOnL1)
    #expect(PasturaDynamicPalette.metaBaseL2.dark == PasturaPalette.nightMetaBaseL2)
    #expect(PasturaDynamicPalette.metaStrongL2.dark == PasturaPalette.nightMetaStrongL2)
    #expect(PasturaDynamicPalette.metaDotOnL2.dark == PasturaPalette.nightMetaDotOnL2)
    #expect(PasturaDynamicPalette.metaBaseL3.dark == PasturaPalette.nightMetaBaseL3)
    #expect(PasturaDynamicPalette.metaStrongL3.dark == PasturaPalette.nightMetaStrongL3)
    #expect(PasturaDynamicPalette.metaDotOnL3.dark == PasturaPalette.nightMetaDotOnL3)
    #expect(PasturaDynamicPalette.metaBaseL4.dark == PasturaPalette.nightMetaBaseL4)
    #expect(PasturaDynamicPalette.metaStrongL4.dark == PasturaPalette.nightMetaStrongL4)
    #expect(PasturaDynamicPalette.metaDotOnL4.dark == PasturaPalette.nightMetaDotOnL4)
    #expect(PasturaDynamicPalette.headerRule.dark == PasturaPalette.nightHeaderRule)
    #expect(PasturaDynamicPalette.headerMetaInk.dark == PasturaPalette.nightHeaderMetaInk)
  }

  /// Guards the registry's documented size, NOT completeness: declaring a 58th
  /// pair without appending it to `all` leaves the count at 57 and passes. What it
  /// does catch outright is a copy-paste duplicate in `all` (the `Set` line).
  /// Per-alias coverage lives in `DesignTokensTests+DarkModeWiring`.
  @Test func exactlyFiftySevenPairsAreWired() {
    #expect(PasturaDynamicPalette.all.count == 57)
    #expect(Set(PasturaDynamicPalette.all.map(\.name)).count == 57)
  }

  /// The false-green guard the tolerance note above is really asking for.
  ///
  /// The wiring tests assert an alias resolves to its *dark* token. That check is
  /// only meaningful if a **wrongly light-sourced alias would fail it** —
  /// otherwise it passes either way. So this reconstructs exactly that alias: a
  /// pair whose dark side is its light value, resolved under a dark environment,
  /// compared against the dark token the wiring test expects.
  ///
  /// The two operands deliberately mirror the wiring test's own asymmetry — the
  /// alias leg goes `Color(UIColor(dynamicProvider:))` → UIKit resolve, the
  /// expected leg is direct — so the UIColor round-trip's error is inside the
  /// measurement rather than outside it. Resolving both legs directly (an
  /// earlier shape of this test) would have measured a pipeline neither wiring
  /// test uses, and could clear the bound while the real comparison did not.
  ///
  /// This is a negative control, so it is the one test here that reddens when the
  /// palette stops being able to prove anything. If a future pair is designed too
  /// close to its light sibling, this fails and the wiring assertions above are
  /// the thing to distrust.
  ///
  /// Verified by mutation rather than by its own success: setting
  /// `PasturaDynamicPalette.hover.dark` to the light value (the tightest pair —
  /// its two sides differ by 0.02 of alpha) reddens this test. That probe also
  /// settled the question the tolerance note above raises: the two sides resolved
  /// to `#8A9A6C0F` and `#A8B88814`, so `Color.Resolved` does **not**
  /// premultiply alpha into RGB — the §2.7 washes stay distinguishable on their
  /// colour channels, not only on alpha.
  @Test func everyPairsTwoSidesAreDistinguishableAtTolerance() {
    for (name, pair) in PasturaDynamicPalette.all {
      // The alias this pair would produce if its dark half had never been
      // repointed. `darkEnvironment()` is load-bearing here, unlike in a plain
      // static-token comparison: it is what drives the provider's branch.
      let stillLightSourced = PasturaDynamicColor(light: pair.light, dark: pair.light)
        .color.resolve(in: darkEnvironment())
      let expectedDark = pair.dark.color.resolve(in: darkEnvironment())
      #expect(
        !resolvedComponentsMatch(stillLightSourced, expectedDark),
        Comment(
          rawValue: "pair '\(name)' has light and dark within tolerance — the wiring "
            + "tests cannot distinguish them, so they would pass even if the alias were still "
            + "sourced from PasturaPalette"))
    }
  }

}

// MARK: - Helpers
//
// The three below are **internal, not `private`**: the sibling wiring file
// (`DesignTokensTests+DarkModeWiring.swift`) calls them, and `private` at file
// scope is invisible across files. Widening is contained — the test target is
// its own module. `sRGBComponentsMatch` stays `private` because only this file
// uses it, and `.claude/rules/swift-isolation.md` cites it as the worked
// example of the cross-module `@MainActor`-on-a-private-helper shape.

/// `EnvironmentValues` pinned to dark, for `Color.resolve(in:)`.
func darkEnvironment() -> EnvironmentValues {
  var env = EnvironmentValues()
  env.colorScheme = .dark
  return env
}

/// `EnvironmentValues` pinned to light, for `Color.resolve(in:)`.
func lightEnvironment() -> EnvironmentValues {
  var env = EnvironmentValues()
  env.colorScheme = .light
  return env
}

/// Compares a resolved `UIColor`'s sRGB components against a token. Exact
/// (0.001) because this path does not go through `Color.Resolved`.
///
/// `@MainActor` is load-bearing, verified by deletion: without it the build
/// fails with `main actor-isolated property 'red' can not be referenced from a
/// nonisolated context` on each component read below.
///
/// The asymmetry — `PasturaDynamicColor.uiColor`'s **nonisolated** provider
/// closure reads those same `let` properties and compiles — is the module
/// boundary, and it takes two facts. (1) `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor` is set on the app target's configs only (2 occurrences in the
/// pbxproj), so a file-scope `private func` here in `PasturaTests` is
/// nonisolated by default while app-module code is not. (2) Swift's implicit
/// exemption for reading immutable `Sendable` `let` storage of a
/// global-actor-isolated type applies only **within the declaring module** —
/// outside it the `let` could later become computed. Hence in-module reads
/// compile and `@testable import`-ed ones do not.
@MainActor
private func sRGBComponentsMatch(
  _ resolved: UIColor, _ token: PasturaColorValue, tolerance: CGFloat = 0.001
) -> Bool {
  var red: CGFloat = 0
  var green: CGFloat = 0
  var blue: CGFloat = 0
  var alpha: CGFloat = 0
  guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
  return abs(red - token.red) < tolerance
    && abs(green - token.green) < tolerance
    && abs(blue - token.blue) < tolerance
    && abs(alpha - token.opacity) < tolerance
}

/// Compares two `Color.Resolved` values. Tolerance is looser than the UIColor
/// path because both sides have been through SwiftUI's linear-light round trip.
func resolvedComponentsMatch(
  _ lhs: Color.Resolved, _ rhs: Color.Resolved, tolerance: Float = 0.005
) -> Bool {
  abs(lhs.red - rhs.red) < tolerance
    && abs(lhs.green - rhs.green) < tolerance
    && abs(lhs.blue - rhs.blue) < tolerance
    && abs(lhs.opacity - rhs.opacity) < tolerance
}
