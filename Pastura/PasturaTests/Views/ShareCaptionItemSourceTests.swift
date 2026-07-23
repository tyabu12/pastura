import Testing
import UIKit

@testable import Pastura

/// Pure destination-branching logic for ``ShareCaptionItemSource`` (#1263).
///
/// **What these tests can and cannot prove.** They pin the *decision shape* —
/// an X destination gets the hashtag, everything else gets the caption
/// verbatim — and nothing else. They deliberately cannot prove that
/// ``ShareCaptionItemSource/xActivityTypes`` holds the identifier the X share
/// extension actually reports: the test constructs its X input *from that same
/// set*, so it passes identically whether the pinned value is right or wrong.
/// Only device QA against the real X app can confirm the identifier; a green
/// run here is not evidence the feature fires. See the type's doc-comment for
/// how the identifier is re-pinned.
///
/// The `UIActivityItemSource` conformance itself (placeholder item, the
/// framework's post-pick callback) is not tested — that is UIKit integration,
/// out of scope per ADR-009, the same line ``XPostSharerTests`` draws around
/// `UIApplication.open`.
///
/// The suite is deliberately **not** `@MainActor`: UIKit hands this type its
/// callbacks with no main-thread guarantee, so being reachable from a
/// nonisolated context is part of the contract, and a `@MainActor` suite would
/// stop compiling the moment that isolation regressed.
@Suite(.timeLimit(.minutes(1)))
struct ShareCaptionItemSourceTests {

  private static let base = "Watching AI agents play out a scenario in Pastura 🐑"

  // Every pinned identifier is exercised, not just an arbitrary one: `Set` has
  // no order, so `.first` would silently cover only one of them once a second
  // identifier is pinned — which the type's doc-comment anticipates.
  @Test("Every X destination receives the base caption plus the brand hashtag")
  func xDestinationAppendsHashtag() {
    let source = ShareCaptionItemSource(baseCaption: Self.base)
    #expect(ShareCaptionItemSource.xActivityTypes.isEmpty == false)
    for rawValue in ShareCaptionItemSource.xActivityTypes {
      #expect(source.caption(for: UIActivity.ActivityType(rawValue)) == "\(Self.base) #Pastura")
    }
  }

  @Test("The X variant differs from the base by the hashtag suffix and nothing else")
  func xVariantOnlyAppends() {
    let source = ShareCaptionItemSource(baseCaption: Self.base)
    for rawValue in ShareCaptionItemSource.xActivityTypes {
      let caption = source.caption(for: UIActivity.ActivityType(rawValue))
      // Guards the #1082 invariant on the new branch: the caption carries the
      // caller's text plus a tag, and never grows a link or any other payload.
      #expect(caption.hasPrefix(Self.base))
      #expect(caption.dropFirst(Self.base.count) == " #Pastura")
    }
  }

  // Negative control — without this the suite would pass even if the
  // implementation tagged every destination unconditionally.
  @Test("Non-X destinations receive the base caption verbatim")
  func nonXDestinationsAreUntouched() {
    let source = ShareCaptionItemSource(baseCaption: Self.base)
    for activityType in [
      UIActivity.ActivityType.message, .mail, .copyToPasteboard, .postToFacebook
    ] {
      #expect(source.caption(for: activityType) == Self.base)
    }
  }

  @Test("A nil activity type receives the base caption verbatim")
  func nilActivityTypeIsUntouched() {
    let source = ShareCaptionItemSource(baseCaption: Self.base)
    #expect(source.caption(for: nil) == Self.base)
  }

  @Test("The base caption is carried per instance, not read from a shared constant")
  func baseCaptionIsPerInstance() {
    // `ScenarioShareSheet`'s caption is scenario-name-bearing while the
    // highlight card's is model-independent, so the source must never flatten
    // them onto one static string.
    let scenarioCaption = "Watching “Werewolf” play out in Pastura 🐑"
    #expect(
      ShareCaptionItemSource(baseCaption: scenarioCaption).caption(for: nil) == scenarioCaption)
    #expect(ShareCaptionItemSource(baseCaption: Self.base).caption(for: nil) == Self.base)
  }
}
