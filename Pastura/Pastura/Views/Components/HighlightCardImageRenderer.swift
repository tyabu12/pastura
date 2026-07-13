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
    var items: [Any] = [image, caption]
    if let linkURL { items.append(linkURL) }
    return items
  }

  /// Short marketing caption giving share targets minimal context about what
  /// the image is, plus an app pointer. Static (model-independent) and
  /// localized; kept URL-free per the ordering note on ``activityItems``.
  private var caption: String {
    String(localized: "Watching AI agents play out a scenario in Pastura 🐑")
  }
}
