import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Pastura

// Asset-catalog appearance invariants (ADR-028 gates 4/5, #1284).
//
// The catalog sits outside EVERY ADR-028 gate predicate: gate 1 reasons over
// the `Color` extension in `DesignTokens+SwiftUI.swift`, and gate 3 greps Swift
// source under `Views/` + `App/`. `Assets.xcassets` is in neither, so a
// colorset with no dark appearance ships unflagged — which is how the launch
// ground and `AccentColor` both reached the lock-removal PR unpaired. These
// tests are the missing predicate: two pin the values of the colorsets that
// exist, and `everyColorSetCarriesADarkAppearanceOrIsRecordedAsFixed` covers
// the class, so a colorset added later cannot repeat the failure silently.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent. Inherits its `@MainActor` (required to read
// `PasturaPalette`, which is default-MainActor) and `.timeLimit(.minutes(1))`.
extension DesignTokensTests {

  // MARK: - Launch ground

  /// The launch colorset must carry BOTH appearances, and its dark entry must
  /// be the `nightBubble` value it was chosen from.
  ///
  /// Pinning the dark entry against the token — not against a literal — is what
  /// makes this a cross-file guard rather than a restatement: a future edit to
  /// `nightBubble` that forgets the catalog reddens here.
  @Test func launchScreenColorSetCarriesBothAppearances() throws {
    let entries = try Self.colorSetEntries(named: "launchScreenBackground")

    let light = try #require(entries.light, "launchScreenBackground has no universal entry")
    let dark = try #require(
      entries.dark,
      "launchScreenBackground has no dark entry — a dark device flashes the light cream")

    #expect(approxEqual(light.red, 0xF1 / 255.0))
    #expect(approxEqual(light.green, 0xEC / 255.0))
    #expect(approxEqual(light.blue, 0xDC / 255.0))
    #expect(dark == PasturaPalette.nightBubble)
  }

  /// The SwiftUI splash fills the whole screen with
  /// ``LaunchAnimationConfig/backgroundColor`` immediately after the static
  /// launch screen hands off, so the two must agree in BOTH appearances or the
  /// handoff flashes.
  ///
  /// `LaunchAnimationConfig` is `nonisolated`, so it cannot read
  /// `PasturaPalette` in a `static let` initializer (`swift-isolation.md`
  /// Pattern 5, the "Main actor-isolated default value in a nonisolated
  /// context" shape) — its two values are therefore literals, and THIS is what
  /// keeps them in lock-step with the catalog. Mutating either side must redden
  /// this test.
  @Test func launchAnimationConfigBackgroundMatchesTheCatalogInBothAppearances() throws {
    let entries = try Self.colorSetEntries(named: "launchScreenBackground")
    let light = try #require(entries.light)
    let dark = try #require(entries.dark)

    let splash = UIColor(LaunchAnimationConfig.backgroundColor)

    #expect(
      sRGBMatches(splash.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), light))
    #expect(
      sRGBMatches(splash.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), dark))
    // The splash provider is a second, hand-rolled copy of
    // `PasturaDynamicColor.uiColor`'s `== .dark` branch, so it needs its own
    // pin for the `.unspecified` fallback — `DesignTokensTests+DarkMode`'s
    // covers the shared type only. An inverted condition surfaces here.
    #expect(
      sRGBMatches(
        splash.resolvedColor(with: UITraitCollection(userInterfaceStyle: .unspecified)), light))
  }

  // MARK: - System tint

  /// `AccentColor` tints system chrome wherever nothing sets an explicit
  /// `.tint` — outside `RootTabView`, i.e. the first-run flow, database
  /// recovery and the init-failure screen. Unpaired, dark renders light moss
  /// there while every Pastura-drawn moss surface renders `nightMoss`.
  @Test func accentColorSetPairsMossWithNightMoss() throws {
    let entries = try Self.colorSetEntries(named: "AccentColor")

    let light = try #require(entries.light, "AccentColor has no universal entry")
    let dark = try #require(
      entries.dark,
      "AccentColor has no `luminosity: dark` entry — system chrome stays light moss in dark")

    #expect(light == PasturaPalette.moss)
    #expect(dark == PasturaPalette.nightMoss)
  }

  // MARK: - The class, not just the two instances

  /// Colorsets deliberately fixed in both appearances. Empty today — a new
  /// entry needs the reason written next to it, the same way gate 1's second
  /// branch admits "recorded as fixed" as an answer equal to a designed value.
  private static let colorSetsFixedInBothAppearances: Set<String> = []

  /// EVERY colorset must carry a dark appearance or be named as fixed.
  ///
  /// The two tests above pin the two colorsets that exist; this one is what
  /// makes the file's opening claim — that it is the predicate the ADR-028
  /// gates never had over `Assets.xcassets` — true of the *class*. Without it a
  /// third colorset added later reproduces the original failure exactly: it
  /// ships unpaired with nothing to notice.
  @Test func everyColorSetCarriesADarkAppearanceOrIsRecordedAsFixed() throws {
    let catalog = Self.repoRoot.appending(path: "Pastura/Pastura/Assets.xcassets")
    let names = try FileManager.default.contentsOfDirectory(atPath: catalog.path())
      .filter { $0.hasSuffix(".colorset") }
      .map { String($0.dropLast(".colorset".count)) }
      .sorted()

    // Guards the scan itself: a rename or a moved catalog would otherwise make
    // this test vacuously green.
    #expect(names.count >= 2, "found only \(names.count) colorsets — did the scan break?")

    for name in names where !Self.colorSetsFixedInBothAppearances.contains(name) {
      let entries = try Self.colorSetEntries(named: name)
      #expect(
        entries.dark != nil,
        """
        \(name).colorset has no `luminosity: dark` entry. The app follows the \
        device appearance since #1284, so it renders its light value on a dark \
        device. Add a dark entry, or add the name to \
        `colorSetsFixedInBothAppearances` with the reason.
        """)
    }
  }

  // MARK: - Helpers

  /// Light (`universal`, no `appearances`) and dark (`luminosity: dark`)
  /// entries of a colorset, read from the repo rather than the built bundle —
  /// the compiled asset catalog exposes only the *resolved* colour, which
  /// cannot distinguish "no dark entry" from "dark entry equal to light".
  private static func colorSetEntries(named name: String) throws -> (
    light: PasturaColorValue?, dark: PasturaColorValue?
  ) {
    let url = repoRoot.appending(
      path: "Pastura/Pastura/Assets.xcassets/\(name).colorset/Contents.json")
    let root =
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    let colors = root["colors"] as? [[String: Any]] ?? []

    var light: PasturaColorValue?
    var dark: PasturaColorValue?
    for entry in colors {
      guard let value = Self.colorValue(from: entry) else { continue }
      let appearances = entry["appearances"] as? [[String: Any]] ?? []
      let isDark = appearances.contains { appearance in
        appearance["appearance"] as? String == "luminosity"
          && appearance["value"] as? String == "dark"
      }
      let isExplicitLight = appearances.contains { appearance in
        appearance["appearance"] as? String == "luminosity"
          && appearance["value"] as? String == "light"
      }
      if isDark {
        dark = value
      } else if appearances.isEmpty || isExplicitLight {
        // Xcode emits a bare universal entry for a colorset authored from a
        // light base, and an explicit `luminosity: light` one when both
        // appearances are checked. Accept either, or a catalog authored the
        // second way fails with "has no universal entry" — a message pointing
        // at the wrong cause.
        light = value
      }
    }
    return (light, dark)
  }

  /// Xcode writes the components as `"0xNN"` strings.
  private static func colorValue(from entry: [String: Any]) -> PasturaColorValue? {
    guard let color = entry["color"] as? [String: Any],
      let components = color["components"] as? [String: String],
      let red = channel(components["red"]),
      let green = channel(components["green"]),
      let blue = channel(components["blue"])
    else { return nil }
    let alpha = Double(components["alpha"] ?? "1.000") ?? 1.0
    return PasturaColorValue(red: red, green: green, blue: blue, opacity: alpha)
  }

  private static func channel(_ raw: String?) -> Double? {
    guard let raw else { return nil }
    let trimmed = raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
    guard let byte = UInt8(trimmed, radix: 16) else { return nil }
    return Double(byte) / 255.0
  }

  /// `…/Pastura/PasturaTests/Views/<this file>` → four levels up.
  private static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Views
      .deletingLastPathComponent()  // PasturaTests
      .deletingLastPathComponent()  // Pastura
      .deletingLastPathComponent()  // repo root
  }
}

/// Local copy — `DesignTokensTests+DarkMode.swift`'s equivalent is `private`,
/// so it is not visible from this sibling file.
///
/// `@MainActor` for the reason that file's helper documents at length: reading
/// `PasturaColorValue`'s `let` properties from a `@testable import`-ed module
/// crosses a module boundary, where Swift's implicit exemption for immutable
/// `Sendable` `let` storage of a global-actor-isolated type does not apply.
@MainActor
private func sRGBMatches(
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
