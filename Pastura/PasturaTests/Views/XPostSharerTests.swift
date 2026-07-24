import Foundation
import Testing

@testable import Pastura

/// Pure logic for the X (Twitter) web-intent share (#1096): the
/// `x.com/intent/tweet` URL shape and percent-encoding of the `text` / `url`
/// params. The UIKit side effect (`UIApplication.open`) is not tested
/// (ADR-009 — no UIKit integration); only the deterministic URL shaping is.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct XPostSharerTests {

  @Test("intentURL targets x.com/intent/tweet and percent-encodes the text param")
  func intentURLBasicShape() {
    let url = XPostSharer.intentURL(text: "hello world", link: nil)
    #expect(url?.scheme == "https")
    #expect(url?.host == "x.com")
    #expect(url?.path == "/intent/tweet")
    // Spaces must be percent-encoded, never a raw space or `+`.
    #expect(url?.absoluteString == "https://x.com/intent/tweet?text=hello%20world")
  }

  @Test("intentURL appends url= when a link is present")
  func intentURLWithLink() throws {
    let link = URL(string: "https://pastura.app/s/werewolf/")
    let url = XPostSharer.intentURL(text: "caption", link: link)
    let string = try #require(url?.absoluteString)
    #expect(string.hasPrefix("https://x.com/intent/tweet?text=caption&url="))
    // The link itself is percent-encoded (its `:` / `/` become %3A / %2F).
    #expect(string.contains("https%3A%2F%2Fpastura.app%2Fs%2Fwerewolf%2F"))
  }

  @Test("intentURL omits url= entirely when the link is nil")
  func intentURLNilLink() {
    let url = XPostSharer.intentURL(text: "caption", link: nil)
    #expect(url?.absoluteString.contains("url=") == false)
  }

  @Test("intentURL encodes an ampersand in the text so it can't corrupt the query")
  func intentURLAmpersandEncoding() throws {
    // A raw `&` in the value would be read by X as a param separator; it must
    // land as %26 (guards against URLComponents' known ampersand-passthrough).
    let url = XPostSharer.intentURL(text: "cats & dogs", link: nil)
    let string = try #require(url?.absoluteString)
    #expect(string.contains("%26"))
    #expect(!string.contains("cats & dogs"))
  }

  @Test("intentURL percent-encodes emoji in the text")
  func intentURLEmojiEncoding() throws {
    let url = XPostSharer.intentURL(text: "Pastura 🐑", link: nil)
    let string = try #require(url?.absoluteString)
    // 🐑 (U+1F411) as UTF-8 percent-encoding.
    #expect(string.contains("%F0%9F%90%91"))
  }

  @Test("intentURL appends hashtags= carrying the bare tag name")
  func intentURLWithHashtags() throws {
    let url = XPostSharer.intentURL(text: "caption", link: nil, hashtags: ShareHashtag.name)
    let string = try #require(url?.absoluteString)
    #expect(string.contains("&hashtags=Pastura"))
    // X's composer prepends the `#` itself, so a sent one would double it —
    // assert the encoded form (%23) never reaches the query.
    #expect(!string.contains("%23"))
  }

  @Test("intentURL omits hashtags= entirely when none is passed")
  func intentURLNilHashtags() {
    let url = XPostSharer.intentURL(text: "caption", link: nil)
    #expect(url?.absoluteString.contains("hashtags=") == false)
  }

  @Test("ShareHashtag derives the display form from the bare tag name")
  func shareHashtagForms() {
    #expect(ShareHashtag.name == "Pastura")
    #expect(ShareHashtag.hash == "#Pastura")
  }
}
