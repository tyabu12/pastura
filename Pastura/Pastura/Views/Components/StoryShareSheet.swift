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

/// A Pastura-branded share sheet (#1083, #1096) offering a card preview and a
/// horizontal row of circular destination icons — the Instagram/X native
/// share-sheet pattern, preferred over burying share paths in the system
/// sheet's action row.
///
/// This sheet shares the specific **utterance card** (an agent's line). Scenario
/// -level sharing (X post / copy link) lives on ``ScenarioShareSheet`` instead,
/// reached from the Scenario Detail screen — a scenario link is not about one
/// utterance. Destinations here, each routed to its medium-native form:
/// - **Share** → the system share sheet (card **image** + caption + link) via
///   the host's `onSystemShare` closure. The host dismisses this sheet first,
///   then presents `ShareSheet` (dismiss-then-present — see
///   ``HighlightStoryShareModifier`` — so a nested `.sheet` can never stall
///   presentation). X-with-image lives here (X has no image deep link).
/// - **Stories** (shown only when ``InstagramStoriesSharer/isAvailableNow``)
///   hands the square card to Instagram as a sticker on the moss gradient 9:16
///   background — Instagram composites the two, so the app never renders 9:16.
/// - **Save Image** → writes the rasterized card to the photo library.
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
        ShareDestinationTab(
          label: String(localized: "Share"),
          fill: ShareDestinationFill.moss, action: requestSystemShare
        ) {
          ShareTabSymbol(systemName: "square.and.arrow.up", tint: .white)
        }
        if InstagramStoriesSharer.isAvailableNow {
          ShareDestinationTab(
            label: String(localized: "Stories"),
            fill: ShareDestinationFill.instagram, action: shareToInstagram
          ) {
            ShareTabSymbol(systemName: "camera.fill", tint: .white)
          }
        }
        ShareDestinationTab(
          label: String(localized: "Save Image"),
          fill: ShareDestinationFill.neutral, action: saveImage
        ) {
          ShareTabSymbol(systemName: "square.and.arrow.down", tint: Color.ink)
        }
      }
      .padding(.horizontal, Spacing.l)
    }
  }

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
    // Request **add-only** access explicitly. Reaching `performChanges` with an
    // undetermined status makes Photos prompt for full read-write access, which
    // requires `NSPhotoLibraryUsageDescription` — absent here (we ship only the
    // add-only key), so that path crashes. `.addOnly` uses the key we declare.
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.error) }
        return
      }
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      } completionHandler: { success, _ in
        Task { @MainActor in
          UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        }
      }
    }
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
