import SwiftUI

/// The §2.5 colours one ``SheepAvatar`` draws with, resolved for a **single,
/// fixed** appearance.
///
/// ## Why this exists
///
/// ADR-028 gate 1 slice 3 paired the §2.5 tokens, which made every
/// `Color.avatar*` alias trait-resolving. ``SheepAvatar`` is rendered inside
/// ``HighlightShareCard``, which is an `ImageRenderer` export path — and
/// `ImageRenderer` does not inherit the ambient environment. Reading the
/// aliases from there would tie the shared image's sheep to whatever the export
/// injects — the same shape ``HighlightCardPalette`` was created to prevent one
/// layer up. That palette pins six tokens and contains no avatar token, so its
/// guard did not reach this far down.
///
/// What that costs is that `light` and `dark` collapse into each other and the
/// caller's choice goes inert — **not** a dark export silently rendering light,
/// which #1337 measured cannot happen under an injection.
///
/// So every value here is read from **raw `PasturaPalette`**, which is fixed
/// sRGB — the sanctioned explicit-appearance accessor (see
/// `DesignTokens+SwiftUI.swift`'s `Color` extension header). The `Color.avatar*`
/// aliases are deliberately **not** read here.
///
/// ## Why the caller picks, rather than the palette reading the environment
///
/// The alternative was an `.ambient` case built from the trait-resolving
/// aliases, letting SwiftUI resolve them at draw time. #1337 measured that it
/// would have rendered correctly: the avatar draws inside a `Canvas`, and
/// `GraphicsContext` resolves a paired alias against the *injected*
/// `colorScheme` exactly as plain `View` content does, with ambient state
/// reaching neither.
///
/// It is rejected anyway. Selecting a fixed palette *before* the `Canvas` means
/// only concrete sRGB values ever reach it, so the export does not depend on a
/// platform behaviour that is Apple's to change and that nothing in the shipped
/// suite pins. The appearance question is answered by ordinary `@Environment` in
/// ``SheepAvatar``. Measurement: ADR-028 § Amendment 2026-08-06 (#1337).
///
/// ## Only five members
///
/// `avatarEar`, `avatarEarInner` and `avatarNose` are absent because no
/// renderer draws them — neither this app's `Canvas` nor `sheepAvatar()` in
/// `docs/design/demo-replay-reference.html`, which is the source of truth for
/// §2.5's **light** values only (that prototype has no dark half).
/// They remain tokens (see their declarations), but they are not part of what
/// gets painted.
struct SheepAvatarPalette {
  /// Wool fill — the five silhouette circles.
  let body: Color
  /// Face oval, drawn on the body.
  let face: Color
  /// Horn strokes, drawn on the body.
  let horn: Color
  /// Both eyes, drawn on the face.
  let eye: Color
  /// Specular sheen dot, drawn on the face. Carries its own alpha.
  let highlight: Color

  /// The palette for `character` in `colorScheme`.
  ///
  /// - Parameter colorScheme: the appearance to render for. Callers inside the
  ///   app pass the ambient one; fixed-appearance export paths
  ///   (``HighlightShareCard``) pass the appearance they are exporting.
  static func resolved(
    for character: SheepAvatar.Character, colorScheme: ColorScheme
  ) -> SheepAvatarPalette {
    colorScheme == .dark ? dark(for: character) : light(for: character)
  }

  private static func light(for character: SheepAvatar.Character) -> SheepAvatarPalette {
    switch character {
    case .alice:
      return SheepAvatarPalette(
        body: PasturaPalette.avatarBodyAlice.color, face: PasturaPalette.avatarFaceAlice.color,
        horn: PasturaPalette.avatarHornAlice.color, eye: PasturaPalette.avatarEye.color,
        highlight: PasturaPalette.avatarHighlight.color)
    case .bob:
      return SheepAvatarPalette(
        body: PasturaPalette.avatarBodyBob.color, face: PasturaPalette.avatarFaceBob.color,
        horn: PasturaPalette.avatarHornBob.color, eye: PasturaPalette.avatarEye.color,
        highlight: PasturaPalette.avatarHighlight.color)
    case .carol:
      return SheepAvatarPalette(
        body: PasturaPalette.avatarBodyCarol.color, face: PasturaPalette.avatarFaceCarol.color,
        horn: PasturaPalette.avatarHornCarol.color, eye: PasturaPalette.avatarEye.color,
        highlight: PasturaPalette.avatarHighlight.color)
    case .dave:
      return SheepAvatarPalette(
        body: PasturaPalette.avatarBodyDave.color, face: PasturaPalette.avatarFaceDave.color,
        horn: PasturaPalette.avatarHornDave.color, eye: PasturaPalette.avatarEye.color,
        highlight: PasturaPalette.avatarHighlight.color)
    }
  }

  private static func dark(for character: SheepAvatar.Character) -> SheepAvatarPalette {
    switch character {
    case .alice:
      return SheepAvatarPalette(
        body: PasturaPalette.nightAvatarBodyAlice.color,
        face: PasturaPalette.nightAvatarFaceAlice.color,
        horn: PasturaPalette.nightAvatarHornAlice.color,
        eye: PasturaPalette.nightAvatarEye.color,
        highlight: PasturaPalette.nightAvatarHighlight.color)
    case .bob:
      return SheepAvatarPalette(
        body: PasturaPalette.nightAvatarBodyBob.color,
        face: PasturaPalette.nightAvatarFaceBob.color,
        horn: PasturaPalette.nightAvatarHornBob.color,
        eye: PasturaPalette.nightAvatarEye.color,
        highlight: PasturaPalette.nightAvatarHighlight.color)
    case .carol:
      return SheepAvatarPalette(
        body: PasturaPalette.nightAvatarBodyCarol.color,
        face: PasturaPalette.nightAvatarFaceCarol.color,
        horn: PasturaPalette.nightAvatarHornCarol.color,
        eye: PasturaPalette.nightAvatarEye.color,
        highlight: PasturaPalette.nightAvatarHighlight.color)
    case .dave:
      return SheepAvatarPalette(
        body: PasturaPalette.nightAvatarBodyDave.color,
        face: PasturaPalette.nightAvatarFaceDave.color,
        horn: PasturaPalette.nightAvatarHornDave.color,
        eye: PasturaPalette.nightAvatarEye.color,
        highlight: PasturaPalette.nightAvatarHighlight.color)
    }
  }
}
