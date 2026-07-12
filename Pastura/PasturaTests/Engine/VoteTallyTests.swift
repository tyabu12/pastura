import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct VoteTallyTests {
  @Test func clearWinnerByCount() {
    let winner = VoteTally.winner(["Alice": 3, "Bob": 1, "Carol": 2])
    #expect(winner?.key == "Alice")
    #expect(winner?.value == 3)
  }

  @Test func tieResolvesToNameDescending() {
    // Alice and Bob both have 2; canonical tie-break is name desc, so "Bob".
    let winner = VoteTally.winner(["Alice": 2, "Bob": 2])
    #expect(winner?.key == "Bob")
    #expect(winner?.value == 2)
  }

  @Test func emptyReturnsNil() {
    #expect(VoteTally.winner([:]) == nil)
  }
}
