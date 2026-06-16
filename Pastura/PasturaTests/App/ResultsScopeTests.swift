import Testing

@testable import Pastura

/// Pins the type-checked chrome-keying contract that replaced the former
/// empty-string `scenarioId` sentinel (#633). `ResultsView`'s
/// `PushBackChrome` reads ``ResultsScope/isPushedDetail`` to decide whether
/// to show the custom back-chrome, so a regression here would silently put
/// a dead back chevron on the History-tab root or drop it from a pushed
/// detail (ADR-016 D4).
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ResultsScopeTests {

  @Test func aggregateIsNotPushedDetail() {
    // History-tab root — no parent to pop to, so no back-chrome.
    #expect(ResultsScope.aggregate.isPushedDetail == false)
  }

  @Test func scenarioIsPushedDetail() {
    // Per-scenario detail push — needs the custom back-chrome.
    #expect(ResultsScope.scenario("word_wolf").isPushedDetail == true)
  }

  @Test func scenarioIsPushedDetailRegardlessOfId() {
    // The distinction is the case, not the payload: even an empty id is a
    // `.scenario` push (the empty-string-means-aggregate sentinel is gone).
    #expect(ResultsScope.scenario("").isPushedDetail == true)
  }
}
