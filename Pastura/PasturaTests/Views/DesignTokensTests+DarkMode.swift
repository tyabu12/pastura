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
  // slack near black but only ~0.6 of a step near white. Margin for today's
  // eight pairs is comfortable. Metric: the **minimum per-channel gap** after
  // the sRGB→linear transform (the conservative aggregation; a max-channel
  // reading gives larger multiples). By that metric the closest is
  // `muted`↔`nightMuted` at 11.9x the tolerance, next `moss` at 19.2x. Compare a
  // ninth pair against those two before trusting this bound.

  @Test func pairedAliasesResolveDarkUnderDarkColorScheme() {
    let cases: [(alias: Color, dark: PasturaColorValue)] = [
      (.screenBackground, PasturaPalette.nightBackground),
      (.bubbleBackground, PasturaPalette.nightBubble),
      (.whisperBubble, PasturaPalette.nightWhisperBubble),
      (.ink, PasturaPalette.nightInk),
      (.inkSecondary, PasturaPalette.nightInkSecondary),
      (.muted, PasturaPalette.nightMuted),
      (.rule, PasturaPalette.nightRule),
      (.moss, PasturaPalette.nightMoss)
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
      (.moss, PasturaPalette.moss)
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
    let lightOnly: [Color] = [.page, .promoBackground, .warning, .danger, .mossSoft]

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
  }

  /// Guards the registry's documented size, NOT completeness: declaring a ninth
  /// pair without appending it to `all` leaves the count at 8 and passes. What it
  /// does catch outright is a copy-paste duplicate in `all` (the `Set` line), and
  /// it makes *editing the registry* trip over the `nightSurface` double-mapping
  /// (ADR-028 § "The `nightSurface` double-mapping") before a ninth is wired.
  /// Per-alias coverage lives in the wiring tests above.
  @Test func exactlyEightPairsAreWired() {
    #expect(PasturaDynamicPalette.all.count == 8)
    #expect(Set(PasturaDynamicPalette.all.map(\.name)).count == 8)
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
