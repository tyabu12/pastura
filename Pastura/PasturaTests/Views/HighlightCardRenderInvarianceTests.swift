import SwiftUI
import Testing
import UIKit

@testable import Pastura

// MEASUREMENT SPIKE — not a permanent guard. #1337.
//
// ADR-009 decision 1 forbids asserting rendered output, so nothing here may
// survive into the CI suite without the carve-out amendment that decision 5's
// trailing clause demands. The disposition is decided by arm C's outcome; see
// the issue plan comment.
//
// The question: `HighlightCardImageRenderer.render(_:colorScheme:)` is a
// fixed-appearance export, and a paired `Color.*` alias read anywhere inside it
// would mean "whatever appearance the renderer resolved". `SheepAvatarPalette`
// avoided the aliases on the stated grounds that a `Canvas` would rest on
// `GraphicsContext` resolving a dynamic `UIColor` — "a behaviour nothing in this
// repo verifies and no test here could". This measures exactly that.
//
// The axis is the INJECTION, not the ambient appearance. `PasturaDynamicColor`
// is fed by two disjoint channels: the SwiftUI environment (driven by
// `.environment(\.colorScheme,)`) and `UITraitCollection.current` (driven at
// CG-draw time). `ImageRenderer` ignoring ambient state is the documented
// premise (`HighlightCardImageRenderer.swift:11-12`), so an ambient flip cannot
// distinguish "the flip never landed" from "the renderer ignored it by design".
// Flipping the injection has no such ambiguity.
@Suite("HighlightCardRenderInvariance", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct HighlightCardRenderInvarianceTests {

  /// Rasterizes `content` the way production does — appearance passed in
  /// explicitly, never inherited. Mirrors `HighlightCardImageRenderer.render`'s
  /// `.environment(\.colorScheme,)` injection; `scale` is 1 rather than
  /// production's 3 because nothing here depends on export resolution and the
  /// smaller bitmap keeps the arms fast.
  func renderPNG(_ content: some View, colorScheme: ColorScheme) -> Data? {
    let renderer = ImageRenderer(
      content: content.environment(\.colorScheme, colorScheme))
    renderer.scale = 1
    renderer.isOpaque = true
    return renderer.uiImage?.pngData()
  }

  // MARK: - arm 0 — determinism baseline

  /// Two renders of identical content under an identical injection must be
  /// byte-identical. If this reddens, PNG bytes are not a stable observable in
  /// this host and **no other arm below is interpretable** — the finding would
  /// be "the measurement could not be constructed", not anything about aliases.
  @Test func arm0_identicalRendersAreByteIdentical() throws {
    let first = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .light))
    let second = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .light))
    #expect(first == second, "arm 0: rasterization is nondeterministic")
  }

  // MARK: - arm V — value distinguishability (no rendering)

  /// The token's two sides must actually differ, or a byte-identical render
  /// would be explained by the values rather than by the resolution path.
  /// `ink` #2D2E26 / `nightInk` #E8E5D8 is the max-contrast pair on purpose.
  @Test func armV_theTokensTwoSidesResolveToDifferentValues() {
    let pair = PasturaDynamicPalette.ink
    let light = pair.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    let dark = pair.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    #expect(light != dark, "arm V: the pair's two sides are indistinguishable")
  }

  // MARK: - arm N — fixed-value negative control

  /// A raw `PasturaPalette` swatch is fixed sRGB, so flipping the injection must
  /// change nothing. If this reddens, some *other* element of the render
  /// environment is appearance-sensitive and a red arm P or C could not be
  /// attributed to the alias.
  @Test func armN_aRawPaletteSwatchIsUnchangedByTheInjection() throws {
    let light = try #require(
      renderPNG(Swatch(fill: PasturaPalette.ink.color), colorScheme: .light))
    let dark = try #require(
      renderPNG(Swatch(fill: PasturaPalette.ink.color), colorScheme: .dark))
    #expect(light == dark, "arm N: a fixed sRGB fill moved with the injection")
  }

  // MARK: - arm P — positive control

  /// A paired alias in plain `View` content must follow the injection. This is
  /// the apparatus's own control: if a `Rectangle().fill(Color.ink)` does not
  /// move, the measurement cannot detect movement anywhere, and arm C's result
  /// means nothing.
  @Test func armP_aPairedAliasInPlainViewContentFollowsTheInjection() throws {
    let light = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .light))
    let dark = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .dark))
    #expect(light != dark, "arm P: the apparatus cannot observe a paired alias at all")
  }

  // MARK: - arm C — the measurement

  /// The #1319 shape: the alias is resolved by `GraphicsContext`, not by the
  /// view tree. Asserted as "follows the injection" so that a **failure** is the
  /// finding — it would mean the export cannot express a chosen appearance for
  /// anything a `Canvas` draws, which is the escape `SheepAvatarPalette`
  /// sidestepped without being able to verify.
  @Test func armC_aPairedAliasInsideACanvasFollowsTheInjection() throws {
    let light = try #require(renderPNG(CanvasSwatch(fill: Color.ink), colorScheme: .light))
    let dark = try #require(renderPNG(CanvasSwatch(fill: Color.ink), colorScheme: .dark))
    #expect(
      light != dark,
      "arm C: GraphicsContext did NOT follow the injected colorScheme; a paired alias inside a Canvas escapes a fixed-appearance export"
    )
  }

  // MARK: - arm T — what ambient state the arms above actually ran under

  /// Arms P and C differing proves the injection beats ambient only if ambient
  /// was *some* definite thing while they ran. Pin it, so that inference rests
  /// on a recorded value rather than on an assumption about the test host.
  /// Measured **dark** (rawValue 2) on the iPhone 17 Pro / iOS 26.5 runner. That
  /// is what makes arms P and C conclusive rather than suggestive: they rendered
  /// under ambient *dark*, and their injected-`.light` arm still came out light.
  @Test func armT_theHostsAmbientStyleIsDark() {
    let observed = UITraitCollection.current.userInterfaceStyle
    #expect(observed.rawValue == UIUserInterfaceStyle.dark.rawValue)
  }

  // MARK: - arm U — what happens with no injection at all

  /// The completion of arm A: with nothing injected, does ambient reach the
  /// renderer? `HighlightCardImageRenderer.swift:11-12` states `ImageRenderer`
  /// "renders in a default environment and does not inherit the ambient
  /// appearance"; this measures that claim directly rather than inheriting it.
  /// Interpretable only because arm T pinned ambient to dark — an uninjected
  /// render matching the injected-`.light` bytes means the renderer defaulted to
  /// light *against* ambient, confirming the claim.
  @Test func armU_anUninjectedRenderIgnoresAmbientAndDefaultsToLight() throws {
    let injectedLight = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .light))
    let injectedDark = try #require(renderPNG(Swatch(fill: Color.ink), colorScheme: .dark))
    let renderer = ImageRenderer(content: Swatch(fill: Color.ink))
    renderer.scale = 1
    renderer.isOpaque = true
    let uninjected = try #require(renderer.uiImage?.pngData())

    #expect(uninjected == injectedLight, "arm U: an uninjected render is not the light one")
    #expect(uninjected != injectedDark, "arm U: an uninjected render followed ambient dark")
  }

  // MARK: - arm A — can ambient override the injection?

  /// The injection is held fixed at `.light` while ambient is flipped, so any
  /// byte movement is ambient overriding an explicit choice — the one way a
  /// fixed-appearance export could still fail after arms P and C came back green.
  ///
  /// `performAsCurrent` rather than assigning `UITraitCollection.current`: it
  /// takes a non-`async`, non-escaping `() -> Void`, so no suspension can hand a
  /// mutated `current` to a neighbouring `@MainActor` suite running in parallel
  /// (`.serialized` is intra-suite only). It returns nothing, hence the captured
  /// locals. The `Canvas` fixture is the subject because `GraphicsContext` is the
  /// path that reads `current` at CG-draw time.
  @Test func armA_ambientCannotOverrideTheInjection() throws {
    var underLight: Data?
    var underDark: Data?
    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
      underLight = renderPNG(CanvasSwatch(fill: Color.ink), colorScheme: .light)
    }
    UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
      // Assert the flip landed from *inside* the region — outside it `current`
      // is already restored, so the same check there would be vacuous.
      #expect(UITraitCollection.current.userInterfaceStyle == .dark)
      underDark = renderPNG(CanvasSwatch(fill: Color.ink), colorScheme: .light)
    }
    #expect(
      try #require(underLight) == #require(underDark),
      "arm A: ambient appearance overrode the explicitly injected colorScheme"
    )
  }

  // MARK: - smoke check — the production path

  /// Green under every hypothesis (both palettes read raw `PasturaPalette`), so
  /// it discriminates nothing and is **not** evidence about alias coverage. Kept
  /// only to confirm the production entry point renders at all under this
  /// harness.
  @Test func smoke_theProductionRenderProducesAnImage() throws {
    let model = try #require(
      HighlightShareCard.Model(
        agent: "Alice",
        agentPosition: 0,
        rawUtterance: "Sample utterance for the render-invariance spike.",
        rawThought: nil,
        scenarioTitle: "Spike",
        modelName: nil,
        linkURL: nil,
        contentFilter: ContentFilter()))
    #expect(HighlightCardImageRenderer.render(model, colorScheme: .light) != nil)
  }
}

// MARK: - Fixtures

/// A solid fill in plain `View` content — resolved by the SwiftUI view tree.
private struct Swatch: View {
  let fill: Color

  var body: some View {
    Rectangle().fill(fill).frame(width: 24, height: 24)
  }
}

/// The same fill, resolved by `GraphicsContext` instead. This is the shape
/// `SheepAvatar` draws with, and the one `SheepAvatarPalette`'s doc comment
/// records as unverified.
private struct CanvasSwatch: View {
  let fill: Color

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(fill))
    }
    .frame(width: 24, height: 24)
  }
}
