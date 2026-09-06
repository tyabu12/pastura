import Foundation
import PasturaSharedEngine
import Testing

@testable import Pastura

/// S5-4 acceptance for the Settings > Diagnostics sample-message row
/// (ADR-023 §6 S5-4, #1681 residual of #1632).
///
/// The row exists to prove that the `appleMain` `localizedFormat` actual
/// resolves the Kotlin catalog key against `Bundle.main` — so what it must
/// show is the **Kotlin-rendered** validation message, not the bridged
/// `NSError`'s description (`SimulationException: …`). These assertions pin
/// exactly that distinction; the language the message lands in is a device
/// check, not something an `en`-resolving test runner can assert
/// (`.claude/rules/view-testing.md` § "Non-base-locale expectations").
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`, Swift ones `Pastura.X`
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite("SharedEngineDiagnostics sample message", .timeLimit(.minutes(1)))
struct SharedEngineDiagnosticsTests {

  @Test("the sample message is non-empty")
  func sampleMessageIsNonEmpty() {
    #expect(!SharedEngineDiagnostics.sampleRenderedMessage().isEmpty)
  }

  @Test("the sample message is the rendered text, not the exception description")
  func sampleMessageIsNotTheExceptionDescription() {
    #expect(!SharedEngineDiagnostics.sampleRenderedMessage().hasPrefix("SimulationException"))
  }

  @Test("the sample message equals the unwrapped Kotlin-rendered message")
  func sampleMessageMatchesDirectLoaderThrow() throws {
    var thrown: (any Error)?
    do {
      _ = try PasturaSharedEngine.ScenarioLoader().load(yaml: "agents: [")
    } catch {
      thrown = error
    }
    let error = try #require(thrown, "the malformed YAML must make the Kotlin loader throw")
    let exception = try #require(
      (error as NSError).userInfo["KotlinException"] as? PasturaSharedEngine.SimulationException)
    // Built outside `#require`: the macro re-parses a call expression, and
    // `Pastura.SimulationError(...)` inside it is read as a call *on the
    // module* ("module<Pastura> must conform to Copyable").
    let mappedOrNil: Pastura.SimulationError? = .init(shared: exception.error)
    let mapped = try #require(mappedOrNil)
    #expect(SharedEngineDiagnostics.sampleRenderedMessage() == mapped.errorDescription)
  }
}
