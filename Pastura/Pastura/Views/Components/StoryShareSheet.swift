import Photos
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

/// Layout constants for the horizontal destination row. Extracted as a named
/// enum so a change-detector unit test can pin them (ADR-009 view-testing
/// rule): the row is a visual-only surface with no manual test trigger, so
/// drift is caught by asserting these values rather than rendering the View.
enum ShareDestinationLayout {
  /// Diameter of each circular destination icon.
  static let iconDiameter: CGFloat = 56
  /// SF Symbol / glyph point size inside the icon circle.
  static let iconGlyphSize: CGFloat = 24
  /// Fixed width of one icon-plus-label tab (drives the horizontal scroll).
  static let tabWidth: CGFloat = 76
  /// On-screen size of the (down-scaled) 360 pt card preview.
  static let previewSide: CGFloat = 176
}

/// A Pastura-branded share sheet (#1083, #1096) offering a card preview and a
/// horizontal row of circular destination icons — the Instagram/X native
/// share-sheet pattern, preferred over burying share paths in the system
/// sheet's action row.
///
/// Destinations, each routed to its medium-native form:
/// - **Share** → the system share sheet (card **image** + caption + link) via
///   the host's `onSystemShare` closure. The host dismisses this sheet first,
///   then presents `ShareSheet` (dismiss-then-present — see
///   ``HighlightStoryShareModifier`` — so a nested `.sheet` can never stall
///   presentation). X-with-image lives here (X has no image deep link).
/// - **Stories** (shown only when ``InstagramStoriesSharer/isAvailableNow``)
///   hands the square card to Instagram as a sticker on the moss gradient 9:16
///   background — Instagram composites the two, so the app never renders 9:16.
/// - **Post to X** → the ``XPostSharer`` web intent (caption + link, no image).
/// - **Save Image** → writes the rasterized card to the photo library.
/// - **Copy Link** → copies the scenario link (shown only when a link exists).
///
/// The preview is a **live** ``HighlightShareCard`` (not the rasterized image),
/// so a rasterization failure on any destination can never blank it.
struct StoryShareSheet: View {
  let context: HighlightShareContext
  /// Invoked with the ready-to-share item when the user picks the system share
  /// sheet. The bridging modifier dismisses this sheet, then the host presents
  /// its existing `ShareSheet`.
  let onSystemShare: (HighlightShareItem) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: Spacing.l) {
      preview
      Divider()
      destinationRow
    }
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
      // Clip in card space (before scaling) at the same radius as the exported
      // sticker, so the preview shows the rounded corners the user will get.
      .clipShape(
        RoundedRectangle(
          cornerRadius: HighlightCardImageRenderer.storyStickerCornerRadius,
          style: .continuous)
      )
      .scaleEffect(ShareDestinationLayout.previewSide / HighlightShareCard.side)
      .frame(
        width: ShareDestinationLayout.previewSide,
        height: ShareDestinationLayout.previewSide
      )
      // Decorative preview — the destination icons carry the actions.
      .accessibilityHidden(true)
  }

  /// Horizontal, scrollable row of destination icons. Scrolls on the narrowest
  /// devices (5 tabs at 76 pt exceed the SE width) — matching how Instagram/X
  /// present their own app rows.
  private var destinationRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.xs) {
        destinationTab(
          label: String(localized: "Share"),
          fill: AnyShapeStyle(mossGradient), action: requestSystemShare
        ) {
          icon("square.and.arrow.up", tint: .white)
        }
        if InstagramStoriesSharer.isAvailableNow {
          destinationTab(
            label: String(localized: "Stories"),
            fill: AnyShapeStyle(instagramGradient), action: shareToInstagram
          ) {
            icon("camera.fill", tint: .white)
          }
        }
        destinationTab(
          label: String(localized: "Post to X"),
          fill: AnyShapeStyle(Color.black), action: postToX
        ) {
          // The double-struck 𝕏 (U+1D54F) stands in for the X wordmark; the
          // "Post to X" label carries the meaning, so the glyph is decorative.
          Text(verbatim: "𝕏")
            .font(.system(size: ShareDestinationLayout.iconGlyphSize, weight: .bold))
            .foregroundStyle(.white)
        }
        destinationTab(
          label: String(localized: "Save Image"),
          fill: AnyShapeStyle(neutralFill), action: saveImage
        ) {
          icon("square.and.arrow.down", tint: Color.ink)
        }
        if context.model.linkURL != nil {
          destinationTab(
            label: String(localized: "Copy Link"),
            fill: AnyShapeStyle(neutralFill), action: copyLink
          ) {
            icon("link", tint: Color.ink)
          }
        }
      }
      .padding(.horizontal, Spacing.l)
    }
  }

  /// One icon-over-label destination tab: a circular tinted icon with a caption
  /// beneath, sized to ``ShareDestinationLayout/tabWidth``.
  private func destinationTab(
    label: String,
    fill: AnyShapeStyle,
    action: @escaping () -> Void,
    @ViewBuilder icon: () -> some View
  ) -> some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        ZStack {
          Circle()
            .fill(fill)
            .frame(
              width: ShareDestinationLayout.iconDiameter,
              height: ShareDestinationLayout.iconDiameter)
          icon()
        }
        Text(label)
          .font(.caption2)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
          // Degrade gracefully at large Dynamic Type instead of truncating the
          // longer labels ("Post to X" / "Save Image") inside the fixed tab.
          .minimumScaleFactor(0.85)
      }
      .frame(width: ShareDestinationLayout.tabWidth)
    }
    .buttonStyle(.plain)
  }

  /// An SF Symbol sized for the icon circle.
  private func icon(_ systemName: String, tint: Color) -> some View {
    Image(systemName: systemName)
      .font(.system(size: ShareDestinationLayout.iconGlyphSize, weight: .semibold))
      .foregroundStyle(tint)
  }

  /// Moss brand gradient for the primary (system share) destination.
  private var mossGradient: LinearGradient {
    LinearGradient(
      colors: [Color.moss, Color.mossDark], startPoint: .topLeading,
      endPoint: .bottomTrailing)
  }

  /// Instagram-recognizable warm→violet gradient. Raw RGB (not palette tokens)
  /// because it deliberately evokes Instagram's brand ramp, not Pastura's moss.
  private var instagramGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color(red: 0.98, green: 0.55, blue: 0.12),
        Color(red: 0.84, green: 0.16, blue: 0.46),
        Color(red: 0.35, green: 0.36, blue: 0.84)
      ], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  /// Neutral chip fill for the utility (save / copy) destinations.
  private var neutralFill: Color { Color.ink.opacity(0.08) }

  /// Rasterizes the card and hands it to Instagram Stories. Guards the two
  /// nil-producing steps (`render` → `UIImage?`, `pngData()` → `Data?`) with a
  /// silent no-op, matching ``HighlightCardImageRenderer``'s render-fail UX.
  private func shareToInstagram() {
    guard
      let appID = StoryShareConfig.facebookAppID,
      let image = HighlightCardImageRenderer.renderStorySticker(
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

  /// Opens the X composer pre-filled with the shared caption + scenario link
  /// (no image — X has no image deep link; ``XPostSharer``). Reuses the same
  /// caption as the system-sheet path so the two can't drift across ja/en.
  private func postToX() {
    XPostSharer.share(text: HighlightShareItem.caption, link: context.model.linkURL)
    dismiss()
  }

  /// Writes the opaque card image to the photo library (add-only —
  /// `NSPhotoLibraryAddUsageDescription`). Guards the render-nil step with a
  /// silent no-op. Uses `PHPhotoLibrary.performChanges` rather than
  /// `UIImageWriteToSavedPhotosAlbum(_:nil,nil,nil)` so the haptic reflects the
  /// **real** outcome — the nil-completion form fires no callback, so a
  /// "success" haptic would also sound when the user denies add-only access.
  private func saveImage() {
    guard
      let image = HighlightCardImageRenderer.render(
        context.model, colorScheme: context.colorScheme)
    else {
      dismiss()
      return
    }
    PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAsset(from: image)
    } completionHandler: { success, _ in
      Task { @MainActor in
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
      }
    }
    dismiss()
  }

  /// Copies the scenario link to the pasteboard. Guarded on a non-nil link (the
  /// tab is hidden when nil), so the guard is defensive; a success haptic
  /// confirms the copy.
  private func copyLink() {
    guard let link = context.model.linkURL else {
      dismiss()
      return
    }
    UIPasteboard.general.url = link
    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

  /// Mounts both highlight share surfaces: the system-share `ShareSheet`
  /// (`item`, #1070) and the custom ``StoryShareSheet`` (`context`, #1083),
  /// wired so the story sheet's "Share via…" dismisses and falls back to the
  /// system sheet. Applied by ResultDetailView and SimulationView.
  func highlightShareSurfaces(
    item: Binding<HighlightShareItem?>,
    context: Binding<HighlightShareContext?>
  ) -> some View {
    self
      .sheet(item: item) { ShareSheet(activityItems: $0.activityItems) }
      .highlightStoryShare(context: context, onSystemShare: { item.wrappedValue = $0 })
  }
}
