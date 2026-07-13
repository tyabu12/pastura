import SwiftUI
import UIKit

/// Rasterizes a ``HighlightShareCard`` to a `UIImage` for the system share
/// sheet (issue #1070).
///
/// First `ImageRenderer` use in the codebase. Two deliberate settings:
/// - `scale = 3` exports the 360 pt card at 1080 px regardless of the device's
///   native scale, so shared cards are a consistent resolution.
/// - the `colorScheme` is passed **explicitly** into the card *and* the render
///   environment — `ImageRenderer` renders in a default environment and does
///   not inherit the ambient appearance, so without this a dark-mode user's
///   card would rasterize light (see the ``HighlightShareCard`` doc-comment).
@MainActor
enum HighlightCardImageRenderer {

  /// The export scale (360 pt → 1080 px).
  static let scale: CGFloat = 3

  /// Renders the card, or `nil` if `ImageRenderer` produced no image.
  static func render(
    _ model: HighlightShareCard.Model, colorScheme: ColorScheme
  ) -> UIImage? {
    let card = HighlightShareCard(model: model, colorScheme: colorScheme)
      .environment(\.colorScheme, colorScheme)
    let renderer = ImageRenderer(content: card)
    renderer.scale = scale
    // The card fills a solid background, so an opaque bitmap is correct and
    // avoids a needless alpha channel in the shared PNG.
    renderer.isOpaque = true
    return renderer.uiImage
  }

  /// Corner radius in the card's 360 pt space (×3 at export → 120 px on the
  /// 1080 px sticker) for the Instagram Stories sticker. Rounded like X's
  /// share-to-Stories card — a visual sign-off knob, tweak freely. (#1083)
  static let storyStickerCornerRadius: CGFloat = 40

  /// Rounded-corner, transparent-background variant for the Instagram Stories
  /// sticker (#1083). Clips the square card to a rounded rectangle and renders
  /// with alpha so the corners fall away to transparency — Instagram then
  /// composites the *rounded* card onto the moss gradient background (à la X),
  /// instead of a hard square. Distinct from ``render`` (opaque square), which
  /// stays the system-share card.
  static func renderStorySticker(
    _ model: HighlightShareCard.Model, colorScheme: ColorScheme
  ) -> UIImage? {
    let card = HighlightShareCard(model: model, colorScheme: colorScheme)
      .clipShape(
        RoundedRectangle(cornerRadius: storyStickerCornerRadius, style: .continuous)
      )
      .environment(\.colorScheme, colorScheme)
    let renderer = ImageRenderer(content: card)
    renderer.scale = scale
    // Alpha ON (unlike `render`): the corners outside the rounded rect must be
    // transparent so Instagram's gradient shows through them.
    renderer.isOpaque = false
    return renderer.uiImage
  }

  /// Builds a ready-to-share item, or `nil` when rendering fails — the call
  /// site then simply does not present the share sheet (a silent no-op is the
  /// intended UX for the rare render failure).
  static func makeShareItem(
    _ model: HighlightShareCard.Model, colorScheme: ColorScheme
  ) -> HighlightShareItem? {
    guard let image = render(model, colorScheme: colorScheme) else { return nil }
    return HighlightShareItem(image: image, linkURL: model.linkURL)
  }
}

/// A rendered highlight card packaged for `.sheet(item:)` + ``ShareSheet``.
///
/// Centralizes the `activityItems` composition so the image and caption are
/// always shared and the link is appended only when present — the optional
/// link means a missing URL can never force-unwrap.
struct HighlightShareItem: Identifiable {
  let id = UUID()
  let image: UIImage
  let linkURL: URL?

  /// Heterogeneous payload for `UIActivityViewController`: the card image, a
  /// short caption for context, then the burned-in link (when set) so
  /// messaging targets also get a tappable URL.
  ///
  /// Order is image → caption → URL. The caption is a **separate** activity
  /// item from the URL and never embeds it — the link is already its own item
  /// (issue #1082), so folding it into the caption would duplicate it. The
  /// caption is unconditional (shared even when `linkURL` is nil) so a
  /// URL-less share still carries the app pointer as context.
  var activityItems: [Any] {
    var items: [Any] = [image, Self.caption]
    if let linkURL { items.append(linkURL) }
    return items
  }

  /// Short marketing caption giving share targets minimal context about what
  /// the image is, plus an app pointer. Model-independent and localized; kept
  /// URL-free per the ordering note on ``activityItems``.
  ///
  /// Exposed as a single shared source (not a private instance property) so the
  /// X web-intent post (``XPostSharer``) reuses the exact same localized string
  /// — a duplicated literal would drift between the system-sheet caption and
  /// the X post text across ja/en (#1096).
  static var caption: String {
    String(localized: "Watching AI agents play out a scenario in Pastura 🐑")
  }
}
