/// The brand hashtag carried by X-bound shares, in the two forms the two share
/// paths need.
///
/// Deliberately **not** routed through `Localizable.xcstrings`: a hashtag is a
/// brand token that is identical in every locale, and a catalog entry would let
/// the `ja` and `en` values drift apart into two different tags. Registered as a
/// permanent carve-out in `docs/i18n/leak-detection.md` so the Tier-2 audit
/// recognizes it rather than re-flagging it every run.
///
/// `nonisolated` despite living in `Views/`: both members are immutable
/// `Sendable` constants with no UI affinity, and ``ShareCaptionItemSource``
/// reads them from a nonisolated context (its `UIActivityItemSource`
/// conformance carries no main-thread guarantee — see that type).
nonisolated enum ShareHashtag {

  /// Bare tag name, no leading `#`. This is the form the X web intent's
  /// `hashtags=` parameter expects — X documents "Omit a preceding '#' from
  /// each hashtag; the Post composer will automatically add the proper
  /// space-separated hashtag by language."
  static let name = "Pastura"

  /// Display form, for the paths where nothing downstream will add the `#` for
  /// us — i.e. text appended straight onto a caption for the system share
  /// sheet (see ``ShareCaptionItemSource``).
  static var hash: String { "#\(name)" }
}
