import SwiftUI

/// Identity wrapper for presenting ``StoryShareSheet`` via `.sheet(item:)` —
/// carries the composed card model plus the explicit appearance
/// (``HighlightCardImageRenderer`` / ``HighlightShareCard`` do not read
/// `colorScheme` from the environment). (#1083)
struct HighlightShareContext: Identifiable {
  let id = UUID()
  let model: HighlightShareCard.Model
  let colorScheme: ColorScheme
}

/// A Pastura-branded share sheet (#1083) offering a card preview and explicit
/// share destinations — the "Spotify pattern" for story-share discoverability,
/// preferred over burying the story path in the system sheet's action row.
///
/// - **Instagram Stories** (shown only when ``InstagramStoriesSharer/isAvailableNow``)
///   rasterizes the square card and hands it to Instagram as a sticker on the
///   moss gradient 9:16 background — Instagram composites the two, so the app
///   never renders a 9:16 image.
/// - **Share via…** routes to the system share sheet through the host's
///   `onSystemShare` closure. The host dismisses this sheet first, then presents
///   `ShareSheet` (dismiss-then-present — see ``HighlightStoryShareModifier`` —
///   so a nested `.sheet` can never stall presentation).
///
/// The preview is a **live** ``HighlightShareCard`` (not the rasterized image),
/// so a rasterization failure on the Instagram path can never blank it.
struct StoryShareSheet: View {
  let context: HighlightShareContext
  /// Invoked with the ready-to-share item when the user picks the system share
  /// sheet. The bridging modifier dismisses this sheet, then the host presents
  /// its existing `ShareSheet`.
  let onSystemShare: (HighlightShareItem) -> Void

  @Environment(\.dismiss) private var dismiss

  /// On-screen size of the (down-scaled) 360 pt card preview.
  private let previewSide: CGFloat = 200

  var body: some View {
    VStack(spacing: Spacing.xl) {
      preview
      destinations
    }
    .padding(.horizontal, Spacing.l)
    .padding(.top, Spacing.xl)
    .padding(.bottom, Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.screenBackground)
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private var preview: some View {
    // Fixed-size card scaled to the preview box; `.scaleEffect` doesn't change
    // layout size, so the outer `.frame` reserves the scaled footprint.
    HighlightShareCard(model: context.model, colorScheme: context.colorScheme)
      .frame(width: HighlightShareCard.side, height: HighlightShareCard.side)
      .scaleEffect(previewSide / HighlightShareCard.side)
      .frame(width: previewSide, height: previewSide)
      .clipShape(RoundedRectangle(cornerRadius: Radius.bubbleBody, style: .continuous))
      // Decorative preview — the destination buttons carry the actions.
      .accessibilityHidden(true)
  }

  private var destinations: some View {
    VStack(spacing: Spacing.s) {
      if InstagramStoriesSharer.isAvailableNow {
        Button(action: shareToInstagram) {
          Label(String(localized: "Instagram Stories"), systemImage: "camera.circle.fill")
        }
        .buttonStyle(PasturaPrimaryButtonStyle())
        .frame(maxWidth: .infinity)
      }
      Button(action: requestSystemShare) {
        Label(String(localized: "Share via…"), systemImage: "square.and.arrow.up")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.ink)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
      }
    }
  }

  /// Rasterizes the card and hands it to Instagram Stories. Guards the two
  /// nil-producing steps (`render` → `UIImage?`, `pngData()` → `Data?`) with a
  /// silent no-op, matching ``HighlightCardImageRenderer``'s render-fail UX.
  private func shareToInstagram() {
    guard
      let appID = StoryShareConfig.facebookAppID,
      let image = HighlightCardImageRenderer.render(
        context.model, colorScheme: context.colorScheme),
      let png = image.pngData()
    else { return }
    InstagramStoriesSharer.share(
      stickerImagePNG: png,
      topColorHex: StoryBackgroundGradient.topHex,
      bottomColorHex: StoryBackgroundGradient.bottomHex,
      appID: appID)
    dismiss()
  }

  /// Hands the composed share item to the host's system-share path. Does not
  /// dismiss here — the modifier dismisses via `context = nil` and re-presents
  /// on `onDismiss`. Falls back to a plain dismiss if rendering fails.
  private func requestSystemShare() {
    guard
      let item = HighlightCardImageRenderer.makeShareItem(
        context.model, colorScheme: context.colorScheme)
    else {
      dismiss()
      return
    }
    onSystemShare(item)
  }
}

/// Presents ``StoryShareSheet`` for a highlight and bridges its "Share via…"
/// action to the host's system share sheet using **dismiss-then-present**: the
/// custom sheet is dismissed first (`context = nil`), then `onSystemShare`
/// fires from the sheet's `onDismiss` so only one sheet is ever active — a
/// nested `.sheet` would risk a presentation stall on iOS (#1083).
struct HighlightStoryShareModifier: ViewModifier {
  @Binding var context: HighlightShareContext?
  let onSystemShare: (HighlightShareItem) -> Void
  @State private var pendingSystemShareItem: HighlightShareItem?

  func body(content: Content) -> some View {
    content.sheet(item: $context, onDismiss: presentPendingSystemShare) { ctx in
      StoryShareSheet(
        context: ctx,
        onSystemShare: { item in
          pendingSystemShareItem = item
          context = nil
        })
    }
  }

  private func presentPendingSystemShare() {
    guard let item = pendingSystemShareItem else { return }
    pendingSystemShareItem = nil
    onSystemShare(item)
  }
}

extension View {
  /// Presents the highlight ``StoryShareSheet`` bound to `context`, forwarding
  /// the system-share fallback to `onSystemShare` (the host then presents its
  /// existing `.sheet(item:)` `ShareSheet`). See ``HighlightStoryShareModifier``.
  func highlightStoryShare(
    context: Binding<HighlightShareContext?>,
    onSystemShare: @escaping (HighlightShareItem) -> Void
  ) -> some View {
    modifier(HighlightStoryShareModifier(context: context, onSystemShare: onSystemShare))
  }
}
