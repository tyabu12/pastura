import SwiftUI
import Testing
import UIKit

@testable import Pastura

// §2.9 dark-mode token-pair tests. Protects ADR-028's mechanism decision:
// `PasturaDynamicColor` resolves a light/dark pair through a `UIColor` dynamic
// provider, and the eight paired `Color.*` aliases are actually wired to it.
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

  // MARK: - Wiring (the `Color.*` aliases are dynamic, not static)
  //
  // Asserting only the pair contents would pass even if
  // `DesignTokens+SwiftUI.swift` were reverted to static aliases, so these
  // probe `Color.*` itself.
  //
  // The tolerance absorbs the **UIColor round trip**: the alias side goes
  // `Color(UIColor(dynamicProvider:))` → UIKit resolve → `Color.Resolved`,
  // while the expected side is `Color(.sRGB, …)` → `Color.Resolved`. Only the
  // final linear conversion is shared, so these are NOT one pipeline and an
  // exact equality check would be a false red. Note the tolerance is in
  // **linear** space and therefore non-uniform — measured, ~16 8-bit steps of
  // slack near black but only ~0.6 of a step near white. Metric: the **minimum
  // per-channel gap** after the sRGB→linear transform (the conservative
  // aggregation; a max-channel reading gives larger multiples), computed over
  // RGB — including alpha collapses every opaque pair to 0, since both sides
  // are 1.0.
  //
  // By that metric the closest opaque pair is `muted`↔`nightMuted` at 11.9x the
  // tolerance, next `moss` and `focusRing` at 19.2x; #1282's slice adds nothing
  // tighter than `warning` at 15.2x. The three §2.7 overlays are the exception —
  // their RGB gap is 19.2x but their alpha gap is only 4.0x (`hover`), 8.0x
  // (`pressed`) and 12.0x (`selected`).
  //
  // Do NOT extend this note for a new pair by recomputing the number. The
  // arithmetic is no longer what guards the bound —
  // `everyPairsTwoSidesAreDistinguishableAtTolerance` below asserts the property
  // this paragraph used to estimate, for every pair, including the alpha
  // channel and whatever `Color.Resolved` does to it.

  @Test func pairedAliasesResolveDarkUnderDarkColorScheme() {
    let cases: [(alias: Color, dark: PasturaColorValue)] = [
      (.screenBackground, PasturaPalette.nightBackground),
      (.bubbleBackground, PasturaPalette.nightBubble),
      (.whisperBubble, PasturaPalette.nightWhisperBubble),
      (.ink, PasturaPalette.nightInk),
      (.inkSecondary, PasturaPalette.nightInkSecondary),
      (.muted, PasturaPalette.nightMuted),
      (.rule, PasturaPalette.nightRule),
      (.moss, PasturaPalette.nightMoss),
      (.info, PasturaPalette.nightInfo),
      (.infoSoft, PasturaPalette.nightInfoSoft),
      (.infoInk, PasturaPalette.nightInfoInk),
      (.success, PasturaPalette.nightSuccess),
      (.successSoft, PasturaPalette.nightSuccessSoft),
      (.successInk, PasturaPalette.nightSuccessInk),
      (.warning, PasturaPalette.nightWarning),
      (.warningSoft, PasturaPalette.nightWarningSoft),
      (.warningInk, PasturaPalette.nightWarningInk),
      (.danger, PasturaPalette.nightDanger),
      (.dangerSoft, PasturaPalette.nightDangerSoft),
      (.dangerInk, PasturaPalette.nightDangerInk),
      (.hover, PasturaPalette.nightHover),
      (.pressed, PasturaPalette.nightPressed),
      (.selected, PasturaPalette.nightSelected),
      (.focusRing, PasturaPalette.nightFocusRing),
      (.disabledText, PasturaPalette.nightDisabledText),
      (.disabledBackground, PasturaPalette.nightDisabledBackground)
    ]

    for (alias, dark) in cases {
      let resolvedAlias = alias.resolve(in: darkEnvironment())
      let resolvedExpected = dark.color.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  @Test func pairedAliasesStillResolveLightUnderLightColorScheme() {
    let cases: [(alias: Color, light: PasturaColorValue)] = [
      (.screenBackground, PasturaPalette.screenBackground),
      (.bubbleBackground, PasturaPalette.bubbleBackground),
      (.whisperBubble, PasturaPalette.whisperBubble),
      (.ink, PasturaPalette.ink),
      (.inkSecondary, PasturaPalette.inkSecondary),
      (.muted, PasturaPalette.muted),
      (.rule, PasturaPalette.rule),
      (.moss, PasturaPalette.moss),
      (.info, PasturaPalette.info),
      (.infoSoft, PasturaPalette.infoSoft),
      (.infoInk, PasturaPalette.infoInk),
      (.success, PasturaPalette.success),
      (.successSoft, PasturaPalette.successSoft),
      (.successInk, PasturaPalette.successInk),
      (.warning, PasturaPalette.warning),
      (.warningSoft, PasturaPalette.warningSoft),
      (.warningInk, PasturaPalette.warningInk),
      (.danger, PasturaPalette.danger),
      (.dangerSoft, PasturaPalette.dangerSoft),
      (.dangerInk, PasturaPalette.dangerInk),
      (.hover, PasturaPalette.hover),
      (.pressed, PasturaPalette.pressed),
      (.selected, PasturaPalette.selected),
      (.focusRing, PasturaPalette.focusRing),
      (.disabledText, PasturaPalette.disabledText),
      (.disabledBackground, PasturaPalette.disabledBackground)
    ]

    for (alias, light) in cases {
      let resolvedAlias = alias.resolve(in: lightEnvironment())
      let resolvedExpected = light.color.resolve(in: lightEnvironment())
      #expect(resolvedComponentsMatch(resolvedAlias, resolvedExpected))
    }
  }

  /// Smoke test that unpaired tokens stay scheme-invariant. Honest about its
  /// strength: these five are plain `Color(.sRGB, …)` values with no trait
  /// dependency, so invariance holds by *type*, not by wiring — and none has a
  /// `night*` counterpart, so no plausible edit to this feature reddens it. It
  /// documents the intended light-only boundary; it does not police it. A real
  /// control would need an over-application mechanism to exist first.
  @Test func unpairedAliasesDoNotChangeAcrossColorSchemes() {
    // `.warning` / `.danger` used to sit here and were paired by #1282's slice;
    // refilled from the 42 that remain unpaired, spread across §2.1/§2.3/§2.4/
    // §2.5/§2.8 so a future slice removing one leaves the rest.
    let lightOnly: [Color] = [
      .page, .promoBackground, .mossSoft, .inkOnAccent, .metaBaseL3, .avatarBodyAlice, .link
    ]

    for alias in lightOnly {
      let underLight = alias.resolve(in: lightEnvironment())
      let underDark = alias.resolve(in: darkEnvironment())
      #expect(resolvedComponentsMatch(underLight, underDark))
    }
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
  }

  /// Guards the registry's documented size, NOT completeness: declaring a 27th
  /// pair without appending it to `all` leaves the count at 26 and passes. What it
  /// does catch outright is a copy-paste duplicate in `all` (the `Set` line), and
  /// it makes *editing the registry* trip over the `nightSurface` double-mapping
  /// (ADR-028 § "The `nightSurface` double-mapping") before a 27th is wired.
  /// Per-alias coverage lives in the wiring tests above.
  @Test func exactlyTwentySixPairsAreWired() {
    #expect(PasturaDynamicPalette.all.count == 26)
    #expect(Set(PasturaDynamicPalette.all.map(\.name)).count == 26)
  }

  /// The false-green guard the tolerance note above is really asking for.
  ///
  /// The wiring tests assert an alias resolves to its *dark* token. That check is
  /// only meaningful if the pair's two sides are far enough apart to be told
  /// apart at the comparison tolerance — otherwise an alias still wired to the
  /// light value would pass. Rather than reason about how far apart the values
  /// are (and about whether `Color.Resolved` premultiplies alpha, which would
  /// shrink the three §2.7 overlays toward each other), assert the discriminating
  /// power directly: under a dark environment, every pair's light value must NOT
  /// match its dark value.
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
      let light = pair.light.color.resolve(in: darkEnvironment())
      let dark = pair.dark.color.resolve(in: darkEnvironment())
      #expect(
        !resolvedComponentsMatch(light, dark),
        Comment(
          rawValue: "pair '\(name)' has light and dark within tolerance — the wiring "
            + "tests cannot distinguish them, so they would pass even if the alias were still "
            + "sourced from PasturaPalette"))
    }
  }

  /// `nightSurface` is defined in the palette but deliberately unwired. If it
  /// ever gains a light partner this test should be deleted along with the
  /// ADR-028 deferral.
  @Test func nightSurfaceIsDefinedButNotWired() {
    #expect(!PasturaDynamicPalette.all.contains { $0.pair.dark == PasturaPalette.nightSurface })
  }
}

// MARK: - Helpers

/// `EnvironmentValues` pinned to dark, for `Color.resolve(in:)`.
private func darkEnvironment() -> EnvironmentValues {
  var env = EnvironmentValues()
  env.colorScheme = .dark
  return env
}

/// `EnvironmentValues` pinned to light, for `Color.resolve(in:)`.
private func lightEnvironment() -> EnvironmentValues {
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
private func resolvedComponentsMatch(
  _ lhs: Color.Resolved, _ rhs: Color.Resolved, tolerance: Float = 0.005
) -> Bool {
  abs(lhs.red - rhs.red) < tolerance
    && abs(lhs.green - rhs.green) < tolerance
    && abs(lhs.blue - rhs.blue) < tolerance
    && abs(lhs.opacity - rhs.opacity) < tolerance
}
