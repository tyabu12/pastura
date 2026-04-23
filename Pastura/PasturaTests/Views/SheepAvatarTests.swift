import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SheepAvatarTests {

  // MARK: - forAgent(_:) — direct matches for demo-replay characters

  @Test func forAgentMatchesAliceCaseInsensitive() {
    #expect(SheepAvatar.Character.forAgent("Alice") == .alice)
    #expect(SheepAvatar.Character.forAgent("alice") == .alice)
    #expect(SheepAvatar.Character.forAgent("ALICE") == .alice)
  }

  @Test func forAgentMatchesBobCaseInsensitive() {
    #expect(SheepAvatar.Character.forAgent("Bob") == .bob)
    #expect(SheepAvatar.Character.forAgent("bob") == .bob)
  }

  @Test func forAgentMatchesCarolCaseInsensitive() {
    #expect(SheepAvatar.Character.forAgent("Carol") == .carol)
    #expect(SheepAvatar.Character.forAgent("CAROL") == .carol)
  }

  @Test func forAgentMatchesDaveCaseInsensitive() {
    #expect(SheepAvatar.Character.forAgent("Dave") == .dave)
    #expect(SheepAvatar.Character.forAgent("dave") == .dave)
  }

  // MARK: - Normalization

  @Test func forAgentTrimsLeadingAndTrailingWhitespace() {
    // "Alice " and "Alice" should resolve to the same character — trailing
    // whitespace is a common user-authoring slip in scenario YAMLs and must
    // not push the name into the byte-sum fallback bucket.
    #expect(SheepAvatar.Character.forAgent("Alice ") == .alice)
    #expect(SheepAvatar.Character.forAgent("  Alice") == .alice)
    #expect(SheepAvatar.Character.forAgent("\tAlice\n") == .alice)
  }

  @Test func forAgentDeterministicForSameInput() {
    // Same input → same character, across invocations. Byte-sum fallback
    // must not pull from any non-deterministic source (e.g. Swift's
    // randomized String.hashValue).
    let first = SheepAvatar.Character.forAgent("AgentZZZ")
    let second = SheepAvatar.Character.forAgent("AgentZZZ")
    let third = SheepAvatar.Character.forAgent("AgentZZZ")
    #expect(first == second)
    #expect(second == third)
  }

  // MARK: - Edge cases — fallback must never crash

  @Test func forAgentEmptyStringReturnsSomeCharacter() {
    // Empty string → byte-sum 0 → deterministic bucket. Must not crash.
    // Not asserting which character — just that it resolves.
    let result = SheepAvatar.Character.forAgent("")
    #expect(SheepAvatar.Character.allCases.contains(result))
  }

  @Test func forAgentWhitespaceOnlyNormalizesToEmpty() {
    // "   " → trimmed to "" → same bucket as empty.
    let whitespace = SheepAvatar.Character.forAgent("   ")
    let empty = SheepAvatar.Character.forAgent("")
    #expect(whitespace == empty)
  }

  @Test func forAgentNonASCIIDoesNotCrash() {
    // Japanese / emoji / mixed — UTF-8 byte representation must be handled
    // without crashing. Semantic arbitrariness is accepted (documented).
    let japanese = SheepAvatar.Character.forAgent("あり")
    let emoji = SheepAvatar.Character.forAgent("🐑")
    let mixed = SheepAvatar.Character.forAgent("Agent🐑")
    #expect(SheepAvatar.Character.allCases.contains(japanese))
    #expect(SheepAvatar.Character.allCases.contains(emoji))
    #expect(SheepAvatar.Character.allCases.contains(mixed))
  }

  // MARK: - Distribution sanity (not exhaustive)

  @Test func forAgentSpreadsShortAsciiNamesAcrossBuckets() {
    // User1..User9 — we don't require perfect uniformity, but "all 9 names
    // land in the same bucket" would be an obvious poor-avalanche bug. At
    // least 2 distinct buckets across 9 inputs is a very loose sanity gate.
    let names = (1...9).map { "User\($0)" }
    let characters = Set(names.map { SheepAvatar.Character.forAgent($0) })
    #expect(characters.count >= 2, "byte-sum % 4 degenerated: all 9 names → same character")
  }

  @Test func forAgentKnownNameNotAffectedByByteSumCollision() {
    // "Alice" summed as bytes = 65+108+105+99+101 = 478, % 4 = 2 (.carol).
    // The direct lookup MUST win over the byte-sum bucket — this test
    // guards against a regression where normalization skips the direct
    // check and falls straight through to the hash.
    #expect(SheepAvatar.Character.forAgent("Alice") == .alice)
    #expect(SheepAvatar.Character.forAgent("Alice") != .carol)
  }
}
