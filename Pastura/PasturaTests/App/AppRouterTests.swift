import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppRouterTests {

  @Test func startsEmpty() {
    let router = AppRouter()
    #expect(router.path.isEmpty)
  }

  @Test func pushAppendsRoute() {
    let router = AppRouter()
    router.push(.shareBoard)
    #expect(router.path == [.shareBoard])
    router.push(.scenarioDetail(scenarioId: "x"))
    #expect(router.path == [.shareBoard, .scenarioDetail(scenarioId: "x")])
  }

  @Test func popRemovesLast() {
    let router = AppRouter()
    router.push(.shareBoard)
    router.push(.scenarioDetail(scenarioId: "x"))
    router.pop()
    #expect(router.path == [.shareBoard])
  }

  @Test func popOnEmptyIsNoOp() {
    let router = AppRouter()
    router.pop()
    #expect(router.path.isEmpty)
  }

  @Test func popToRootClearsPath() {
    let router = AppRouter()
    router.push(.shareBoard)
    router.push(.scenarioDetail(scenarioId: "x"))
    router.push(.simulation(scenarioId: "x"))
    router.popToRoot()
    #expect(router.path.isEmpty)
  }

  @Test func replacePathOverwrites() {
    let router = AppRouter()
    router.push(.shareBoard)
    router.replacePath([.results(scenarioId: "y"), .resultDetail(simulationId: "z")])
    #expect(router.path == [.results(scenarioId: "y"), .resultDetail(simulationId: "z")])
  }

  @Test func replacePathWithEmptyClearsPath() {
    let router = AppRouter()
    router.push(.shareBoard)
    router.push(.scenarioDetail(scenarioId: "x"))
    router.replacePath([])
    #expect(router.path.isEmpty)
  }

  @Test func replacePathFromEmptySeedsPath() {
    let router = AppRouter()
    router.replacePath([.shareBoard, .scenarioDetail(scenarioId: "x")])
    #expect(router.path == [.shareBoard, .scenarioDetail(scenarioId: "x")])
  }

  // MARK: - pushIfOnTop guard

  @Test func pushIfOnTopAppendsWhenExpectedMatches() {
    let router = AppRouter()
    let scenario = makeGalleryScenario(id: "asch_v1")
    router.push(.galleryScenarioDetail(scenario: scenario))

    let pushed = router.pushIfOnTop(
      expected: .galleryScenarioDetail(scenario: scenario),
      next: .scenarioDetail(scenarioId: "asch_v1"))

    #expect(pushed)
    #expect(router.path.last == .scenarioDetail(scenarioId: "asch_v1"))
    #expect(router.path.count == 2)
  }

  @Test func pushIfOnTopSkipsWhenExpectedDoesNotMatch() {
    let router = AppRouter()
    // User has already navigated away (e.g. popped back to Share Board).
    router.push(.shareBoard)

    let scenario = makeGalleryScenario(id: "asch_v1")
    let pushed = router.pushIfOnTop(
      expected: .galleryScenarioDetail(scenario: scenario),
      next: .scenarioDetail(scenarioId: "asch_v1"))

    #expect(!pushed)
    #expect(router.path == [.shareBoard])
  }

  @Test func pushIfOnTopSkipsWhenPathIsEmpty() {
    let router = AppRouter()
    let pushed = router.pushIfOnTop(
      expected: .shareBoard,
      next: .scenarioDetail(scenarioId: "x"))
    #expect(!pushed)
    #expect(router.path.isEmpty)
  }

  @Test func pushIfOnTopSkipsWhenExpectedIsMidStackNotTop() {
    // Pins the `top` semantics: `expected` being anywhere in the path is
    // not enough — it must be the current top. Guards against a future
    // well-meaning refactor that loosens the check to `path.contains`.
    let router = AppRouter()
    router.push(.shareBoard)
    router.push(.scenarioDetail(scenarioId: "x"))  // shareBoard is now mid-stack

    let pushed = router.pushIfOnTop(
      expected: .shareBoard,
      next: .results(scenarioId: "y"))
    #expect(!pushed)
    #expect(router.path == [.shareBoard, .scenarioDetail(scenarioId: "x")])
  }

  // MARK: - RouteHint identity-neutrality (ADR-008)

  @Test func pushIfOnTopMatchesIdenticalScenarioIdRegardlessOfHint() {
    // Pins the contract: `RouteHint<String>` initialName is identity-
    // neutral, so `expected` and `top` need only agree on `scenarioId`.
    // Future code paths that omit the hint when constructing `expected`
    // (or pass a different hint than what was actually pushed) must
    // still match.
    let router = AppRouter()
    router.push(.scenarioDetail(scenarioId: "x", initialName: .init("Foo")))

    let pushed = router.pushIfOnTop(
      expected: .scenarioDetail(scenarioId: "x"),  // initialName defaulted (nil)
      next: .simulation(scenarioId: "x"))

    #expect(pushed)
    #expect(router.path.count == 2)
    #expect(router.path.last == .simulation(scenarioId: "x"))
  }

  @Test func pushIfOnTopFailsWhenScenarioIdDiffers() {
    // Symmetric pin: scenarioId remains the identity-bearing field.
    // Two `.scenarioDetail` values with different ids must never match,
    // regardless of whether their hints agree.
    let router = AppRouter()
    router.push(.scenarioDetail(scenarioId: "x", initialName: .init("Foo")))

    let pushed = router.pushIfOnTop(
      expected: .scenarioDetail(scenarioId: "y", initialName: .init("Foo")),
      next: .simulation(scenarioId: "y"))

    #expect(!pushed)
    #expect(router.path.count == 1)
  }

  // MARK: - Helpers

  private func makeGalleryScenario(id: String) -> GalleryScenario {
    GalleryScenario(
      id: id, title: id, category: .experimental,
      description: "", author: "",
      recommendedModel: "", estimatedInferences: 0,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: "h", addedAt: "2026-04-15")
  }
}
