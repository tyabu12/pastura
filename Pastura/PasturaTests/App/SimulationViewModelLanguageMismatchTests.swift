import Foundation
import Testing

@testable import Pastura

/// `.languageMismatch` event surfacing — toast (one-shot per run) +
/// aggregated count badge contract (Issue #401 / ADR-010 Out-of-Scope
/// follow-up). The toast fires exactly once per `run()` cycle; the
/// count accumulates across the burst.
@Suite("SimulationViewModelLanguageMismatch", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelLanguageMismatchTests {

  // MARK: - LanguageMismatchToast value semantics

  @Test func toastEqualityHonorsAllFields() {
    let alice = SimulationViewModel.LanguageMismatchToast(
      agent: "Alice", detected: "ja", expected: "en")
    let aliceDup = SimulationViewModel.LanguageMismatchToast(
      agent: "Alice", detected: "ja", expected: "en")
    let bob = SimulationViewModel.LanguageMismatchToast(
      agent: "Bob", detected: "ja", expected: "en")
    #expect(alice == aliceDup)
    #expect(alice != bob)
  }

  @Test func toastEqualityHandlesNilDetected() {
    let nilDetected = SimulationViewModel.LanguageMismatchToast(
      agent: "Alice", detected: nil, expected: "en")
    let nilDetectedDup = SimulationViewModel.LanguageMismatchToast(
      agent: "Alice", detected: nil, expected: "en")
    let knownDetected = SimulationViewModel.LanguageMismatchToast(
      agent: "Alice", detected: "ja", expected: "en")
    #expect(nilDetected == nilDetectedDup)
    #expect(nilDetected != knownDetected)
  }

  // MARK: - Initial state

  @Test func initialStateIsEmpty() throws {
    let (sut, _) = try makeSUT()
    #expect(sut.languageMismatchCount == 0)
    #expect(sut.pendingLanguageMismatchToast == nil)
    #expect(sut.languageMismatchToastText == nil)
  }

  // MARK: - handleEvent dispatch

  @Test func firstEventSetsPendingToastAndIncrementsCount() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    #expect(sut.languageMismatchCount == 1)
    #expect(
      sut.pendingLanguageMismatchToast
        == .init(agent: "Alice", detected: "ja", expected: "en"))
  }

  @Test func secondEventDoesNotOverwritePendingToast() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    sut.handleEvent(
      .languageMismatch(agent: "Bob", detected: "fr", expected: "en"),
      scenario: scenario)
    #expect(sut.languageMismatchCount == 2)
    #expect(sut.pendingLanguageMismatchToast?.agent == "Alice")
    #expect(sut.pendingLanguageMismatchToast?.detected == "ja")
  }

  // MARK: - Dismiss

  @Test func dismissClearsPendingButKeepsCount() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    sut.handleEvent(
      .languageMismatch(agent: "Bob", detected: "ja", expected: "en"),
      scenario: scenario)
    sut.handleEvent(
      .languageMismatch(agent: "Carol", detected: "ja", expected: "en"),
      scenario: scenario)
    #expect(sut.languageMismatchCount == 3)

    sut.dismissLanguageMismatchToast()
    #expect(sut.pendingLanguageMismatchToast == nil)
    #expect(
      sut.languageMismatchCount == 3, "Dismiss must preserve cumulative count")
  }

  @Test func eventAfterDismissDoesNotRefireToast() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    sut.dismissLanguageMismatchToast()
    #expect(sut.pendingLanguageMismatchToast == nil)

    sut.handleEvent(
      .languageMismatch(agent: "Bob", detected: "ja", expected: "en"),
      scenario: scenario)
    #expect(sut.languageMismatchCount == 2)
    #expect(
      sut.pendingLanguageMismatchToast == nil,
      "Toast must not re-fire after dismiss within the same run() cycle")
  }

  // MARK: - Toast text rendering — nil-detected leak guard

  @Test func toastTextWithDetectedDoesNotLeakOptional() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    let text = sut.languageMismatchToastText
    #expect(text != nil)
    #expect(text?.contains("Alice") == true)
    #expect(
      text?.contains("Optional") == false,
      "Toast text must not leak Optional(...) in any path")
  }

  @Test func toastTextWithNilDetectedDoesNotLeakOptionalOrNilLiteral() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: nil, expected: "en"),
      scenario: scenario)
    let text = sut.languageMismatchToastText
    #expect(text != nil)
    #expect(text?.contains("Alice") == true)
    #expect(
      text?.contains("Optional") == false,
      "nil detected must not leak as Optional(...)")
    // Allow a translated language name to contain the substring "nil" (no
    // such code exists today, but guard against false-positives if one is
    // ever added). The leak we are guarding here is the literal `String(
    // describing: nil)` rendering, which produces "nil" as a whole word.
    #expect(
      text?.contains(" nil ") == false && text?.hasSuffix(" nil") == false,
      "nil detected must not leak as the literal token 'nil'")
  }

  // MARK: - run() reset (integration)

  @Test func runResetsLanguageMismatchState() async throws {
    let (sut, scenario) = try makeSUT()

    // Pre-populate state via direct dispatch so we can observe the reset.
    sut.handleEvent(
      .languageMismatch(agent: "Alice", detected: "ja", expected: "en"),
      scenario: scenario)
    sut.handleEvent(
      .languageMismatch(agent: "Bob", detected: "ja", expected: "en"),
      scenario: scenario)
    #expect(sut.languageMismatchCount == 2)
    #expect(sut.pendingLanguageMismatchToast != nil)

    sut.speed = .instant

    // Long-running mock so the run stays in flight long enough for the
    // test to observe the reset before cancelling.
    let mock = MockLLMService(responses: [
      #"{"statement": "first"}"#,
      #"{"statement": "second"}"#,
      #"{"statement": "third"}"#,
      #"{"statement": "fourth"}"#
    ])

    let runTask = Task { await sut.run(scenario: scenario, llm: mock) }
    sut.runTask = runTask

    // Wait for the reset (run() applies it synchronously near entry,
    // before awaiting the event stream).
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while sut.languageMismatchCount > 0, ContinuousClock.now < deadline {
      await Task.yield()
    }

    #expect(sut.languageMismatchCount == 0)
    #expect(sut.pendingLanguageMismatchToast == nil)

    sut.cancelSimulation()
    await runTask.value
  }
}
