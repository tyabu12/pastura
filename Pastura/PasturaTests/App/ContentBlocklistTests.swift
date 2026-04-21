import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ContentBlocklistTests {
  @Test func loadFromBundleReturnsNonEmpty() {
    let patterns = ContentBlocklist.load(from: Bundle(for: DatabaseManager.self))
    #expect(!patterns.isEmpty)
  }

  @Test func loadFromBundleStripsCommentsAndBlanks() {
    let patterns = ContentBlocklist.load(from: Bundle(for: DatabaseManager.self))
    #expect(!patterns.contains(where: { $0.hasPrefix("#") }))
    #expect(!patterns.contains(""))
  }

  @Test func loadFromBundlePatternsHaveNoWhitespace() {
    let patterns = ContentBlocklist.load(from: Bundle(for: DatabaseManager.self))
    for pattern in patterns {
      #expect(
        pattern == pattern.trimmingCharacters(in: .whitespaces),
        "Pattern '\(pattern)' has untrimmed whitespace"
      )
    }
  }

  @Test func parseSkipsCommentLines() {
    let text = """
      # leading comment
      fuck
      # mid comment
      shit
      """
    #expect(ContentBlocklist.parse(text) == ["fuck", "shit"])
  }

  @Test func parseSkipsBlankLines() {
    let text = """
      fuck

      shit

      """
    #expect(ContentBlocklist.parse(text) == ["fuck", "shit"])
  }

  @Test func parseTrimsWhitespace() {
    let text = "  fuck  \n\tshit\t"
    #expect(ContentBlocklist.parse(text) == ["fuck", "shit"])
  }

  @Test func parseHandlesEmptyInput() {
    #expect(ContentBlocklist.parse("") == [])
  }

  @Test func parseHandlesCommentOnlyInput() {
    #expect(ContentBlocklist.parse("# only a comment") == [])
  }
}
