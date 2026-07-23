import SwiftUI
import UIKit

/// Identity wrapper for presenting ``ScenarioShareSheet`` via `.sheet(item:)`.
struct ScenarioShareContext: Identifiable {
  let id = UUID()
  let scenarioName: String
  /// Public scenario link (`LocalizedPublicPages.sharedScenario`). Optional —
  /// X / copy / system-share all handle a missing link without force-unwrap.
  let link: URL?
}

/// Wraps the heterogeneous system-share payload so it can drive `.sheet(item:)`.
private struct ScenarioSystemShareItems: Identifiable {
  let id = UUID()
  let items: [Any]
}

/// A Pastura-branded sheet for sharing a whole **scenario** (its public link),
/// as opposed to ``StoryShareSheet`` which shares one utterance card image.
/// Reached from the Scenario Detail toolbar (#1096). Same Instagram/X-native
/// icon-row aesthetic, minus the card preview — a scenario has no card, so a
/// scenario-name header stands in.
///
/// Destinations:
/// - **Post to X** → ``XPostSharer`` web intent, scenario-aware caption + link.
/// - **Copy Link** → copies the scenario link to the pasteboard.
/// - **Share** → the system share sheet (caption + link) via `onSystemShare`
///   (dismiss-then-present — see ``ScenarioShareModifier`` — so a nested
///   `.sheet` can never stall presentation).
struct ScenarioShareSheet: View {
  let context: ScenarioShareContext
  /// Invoked with the caption + link activity items when the user picks the
  /// system share sheet. The modifier dismisses this sheet first, then presents
  /// `ShareSheet`.
  let onSystemShare: ([Any]) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: Spacing.l) {
      header
      Divider()
      destinationRow
    }
    .padding(.top, Spacing.xl)
    .padding(.bottom, Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.screenBackground)
    .presentationDetents([.height(260)])
    .presentationDragIndicator(.visible)
  }

  private var header: some View {
    VStack(spacing: Spacing.xs) {
      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(Color.moss)
      Text(context.scenarioName)
        .font(.headline)
        .foregroundStyle(Color.ink)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.l)
    .accessibilityElement(children: .combine)
  }

  private var destinationRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.xs) {
        ShareDestinationTab(
          label: String(localized: "Post to X"),
          fill: ShareDestinationFill.xBlack, action: postToX
        ) {
          ShareTabXGlyph()
        }
        ShareDestinationTab(
          label: String(localized: "Copy Link"),
          fill: ShareDestinationFill.neutral, action: copyLink
        ) {
          ShareTabSymbol(systemName: "link", tint: Color.ink)
        }
        ShareDestinationTab(
          label: String(localized: "Share"),
          fill: ShareDestinationFill.moss, action: requestSystemShare
        ) {
          ShareTabSymbol(systemName: "ellipsis", tint: .white)
        }
      }
      .padding(.horizontal, Spacing.l)
    }
  }

  /// Scenario-aware X post caption (name-bearing, unlike the utterance card's
  /// model-independent caption). Form B (`String(format: String(localized:))`)
  /// per the i18n format-string convention.
  private var caption: String {
    String(
      format: String(localized: "Watching “%@” play out in Pastura 🐑"),
      context.scenarioName)
  }

  private func postToX() {
    // Destination is known up front here, so the tag rides X's own `hashtags=`
    // param. The system-share path can't do that — see ``ShareCaptionItemSource``.
    XPostSharer.share(text: caption, link: context.link, hashtags: ShareHashtag.name)
    dismiss()
  }

  private func copyLink() {
    guard let link = context.link else {
      dismiss()
      return
    }
    UIPasteboard.general.url = link
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    dismiss()
  }

  /// Hands the caption + link to the host's system-share path. Does not dismiss
  /// here — the modifier dismisses via `context = nil` and re-presents on
  /// `onDismiss`.
  private func requestSystemShare() {
    var items: [Any] = [caption]
    if let link = context.link { items.append(link) }
    onSystemShare(items)
  }
}

/// Presents ``ScenarioShareSheet`` and bridges its "Share" action to the system
/// share sheet using **dismiss-then-present**: the custom sheet is dismissed
/// first (`context = nil`), then the staged items are presented from the
/// sheet's `onDismiss`, so only one sheet is ever active (a nested `.sheet`
/// would risk a presentation stall on iOS — mirrors ``HighlightStoryShareModifier``).
struct ScenarioShareModifier: ViewModifier {
  @Binding var context: ScenarioShareContext?
  @State private var pendingSystemShareItems: ScenarioSystemShareItems?
  @State private var presentedSystemShareItems: ScenarioSystemShareItems?

  func body(content: Content) -> some View {
    content
      .sheet(item: $context, onDismiss: presentPendingSystemShare) { ctx in
        ScenarioShareSheet(
          context: ctx,
          onSystemShare: { items in
            pendingSystemShareItems = ScenarioSystemShareItems(items: items)
            context = nil
          })
      }
      .sheet(item: $presentedSystemShareItems) { ShareSheet(activityItems: $0.items) }
  }

  private func presentPendingSystemShare() {
    guard let pending = pendingSystemShareItems else { return }
    pendingSystemShareItems = nil
    presentedSystemShareItems = pending
  }
}

extension View {
  /// Presents the scenario ``ScenarioShareSheet`` bound to `context`, including
  /// the system-share fallback. See ``ScenarioShareModifier``.
  func scenarioShareSheet(context: Binding<ScenarioShareContext?>) -> some View {
    modifier(ScenarioShareModifier(context: context))
  }
}
