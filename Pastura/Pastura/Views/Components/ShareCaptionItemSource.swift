import OSLog
import UIKit

/// A share caption that varies by destination, for the system share sheet.
///
/// `UIActivityViewController` takes its items up front, before the user has
/// chosen where the content is going — so a plain `String` item reaches every
/// destination identically. `UIActivityItemSource` closes that gap: the
/// framework calls ``activityViewController(_:itemForActivityType:)`` *after*
/// the pick, handing over the chosen activity type, so the item can differ per
/// target. That is the only way to reach "X gets the brand hashtag, Messages
/// and Mail do not" from the system sheet.
///
/// The system sheet is unavoidable for the highlight card: X exposes no
/// image-attach deep link, so the card image cannot go through the
/// ``XPostSharer`` web intent the way a scenario link can (#1096). Where the
/// destination *is* known up front — `ScenarioShareSheet`'s "Post to X" tab —
/// the tag rides X's own `hashtags=` param instead, and this type is not
/// involved.
///
/// **Failure mode is silence.** If ``xActivityTypes`` does not match what the
/// installed X app reports, every destination simply receives `baseCaption` —
/// the current behaviour, no breakage, but also no hashtag. See
/// ``xActivityTypes`` for how the identifier is (re-)pinned.
///
/// `nonisolated` is load-bearing, and is the exception to the CLAUDE.md rule
/// that `Views/` takes the default MainActor isolation. `UIActivityItemSource`
/// is imported **unannotated**: asked to print the requirement's type, the
/// compiler gives `(UIActivityViewController) -> Any` with no `@MainActor`,
/// where a genuinely isolated requirement prints one (`UIScrollViewDelegate`'s
/// `scrollViewDidScroll` → `(@MainActor (UIScrollView) -> Void)?`). So UIKit
/// makes no main-thread promise about these callbacks, and the sibling
/// declaration in the same header says as much: `UIActivityItemProvider`'s
/// `item` is documented "called on secondary thread when user selects an
/// activity". A MainActor-isolated witness would compile clean and then trap on
/// the executor precondition the first time UIKit called it off-main, with no
/// diagnostic — see `.claude/rules/swift-isolation.md` Pattern 7 for the probe
/// (and for why the obvious header/apinotes grep cannot answer this).
/// Nothing is given up by dropping the isolation: every stored member is an
/// immutable `Sendable` constant. The `Sendable` conformance makes that last
/// sentence compiler-checked rather than a promise in prose — adding a `var`
/// breaks the build instead of quietly re-opening the race.
nonisolated final class ShareCaptionItemSource: NSObject, UIActivityItemSource, Sendable {

  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "ShareCaption")

  /// The caption every non-X destination receives verbatim.
  ///
  /// Passed in per instance rather than read from a shared constant: the
  /// highlight card's caption is model-independent while `ScenarioShareSheet`'s
  /// carries the scenario name, and flattening the two would silently swap one
  /// surface's copy for the other's.
  let baseCaption: String

  /// Activity types that route to X.
  ///
  /// For a third-party target, `UIActivity.ActivityType` is that share
  /// extension's **bundle identifier** — a value Apple does not publish and X
  /// does not document, so it cannot be derived, only observed. The set is
  /// pinned from a real-device run: share to X, then read the identifier this
  /// type logs from ``activityViewController(_:itemForActivityType:)``. The
  /// iOS Simulator cannot serve that observation (no X app ⇒ no extension),
  /// and `UIActivity.ActivityType.postToTwitter` is not a substitute — Apple
  /// removed the built-in social activities from the share sheet in iOS 11.
  ///
  /// Matching is **exact**, not by prefix, so a rename ships a missing hashtag
  /// rather than tagging some unrelated extension that happens to share a
  /// vendor prefix. Re-pin from the log when X renames.
  ///
  /// The current value was read off a real device on 2026-07-24. Do not
  /// "correct" it to `…Tweetie2.Share`, which is what Apple's usual
  /// `<app-bundle-id>.<suffix>` convention predicts — that guess was tried
  /// first and observed to be wrong. Only the log is authoritative here.
  static let xActivityTypes: Set<String> = ["com.atebits.Tweetie2.ShareExtension"]

  init(baseCaption: String) {
    self.baseCaption = baseCaption
  }

  // MARK: - Pure logic (unit-tested)

  /// The caption for `activityType`: `baseCaption` plus the brand hashtag for
  /// an X destination, `baseCaption` verbatim for everything else — including
  /// `nil`, which the framework passes when no specific target applies.
  ///
  /// The tag is appended here rather than carried in the localized string so
  /// the `ja` and `en` captions cannot drift into different tags — see
  /// ``ShareHashtag``.
  func caption(for activityType: UIActivity.ActivityType?) -> String {
    guard let rawValue = activityType?.rawValue,
      Self.xActivityTypes.contains(rawValue)
    else { return baseCaption }
    return "\(baseCaption) \(ShareHashtag.hash)"
  }

  // MARK: - UIActivityItemSource (side-effecting; not unit-tested per ADR-009)

  /// A representative value of the real item so the sheet can type the item
  /// and offer the right destinations. Returns the caption itself, never `""`
  /// — an empty placeholder makes some share extensions drop the text item.
  func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
    baseCaption
  }

  func activityViewController(
    _ controller: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    // The only channel through which the real identifier becomes knowable, so
    // `xActivityTypes` can be pinned or re-pinned. `.info` (not `.debug`) so
    // the line survives on a non-Debug device build, and `privacy: .public`
    // because an activity type is a vendor bundle identifier — public API
    // surface, never user content.
    Self.logger.info(
      "share destination activityType=\(activityType?.rawValue ?? "nil", privacy: .public)")
    return caption(for: activityType)
  }
}
