import Foundation
import Testing

@testable import Pastura

// Pins `BackgroundSimulationManager.taskIdentifier` to the Info.plist
// `BGTaskSchedulerPermittedIdentifiers` array they must agree on.
//
// Why this needs a test at all: the two live in different artifacts and are both
// derived from `PRODUCT_BUNDLE_IDENTIFIER`, which the Debug configuration suffixes
// (`app.pastura.Pastura.dev`) so a dev build can be installed alongside the App Store
// build. Nothing in the build catches a divergence — and neither does the runtime:
// `BGTaskScheduler.register` merely logs when it rejects an unpermitted identifier,
// so background continuation would ship silently dead.
//
// The test target is app-hosted, so `Bundle.main` is the real host app and this reads
// the *built* configuration's expanded values rather than the source templates.
@Suite(.timeLimit(.minutes(1)))
struct BackgroundTaskIdentifierTests {
  private static let permittedIdentifiersKey = "BGTaskSchedulerPermittedIdentifiers"

  @Test func permittedIdentifiersContainsTheRegisteredTaskIdentifier() throws {
    let permitted = try #require(
      Bundle.main.object(forInfoDictionaryKey: Self.permittedIdentifiersKey) as? [String],
      "Info.plist must carry \(Self.permittedIdentifiersKey) as an array of strings")

    #expect(
      permitted.contains(BackgroundSimulationManager.taskIdentifier),
      """
      BGTaskScheduler would reject the handler registration. \
      permitted=\(permitted) registered=\(BackgroundSimulationManager.taskIdentifier)
      """)
  }

  @Test func permittedIdentifiersAreBuildSettingExpanded() throws {
    let permitted = try #require(
      Bundle.main.object(forInfoDictionaryKey: Self.permittedIdentifiersKey) as? [String])

    // A literal `$(...)` here means Xcode did not substitute the build setting inside
    // the Info.plist file — the one assumption the derivation rests on.
    #expect(
      permitted.allSatisfy { !$0.contains("$(") },
      "unexpanded build-setting reference in \(Self.permittedIdentifiersKey): \(permitted)")
  }
}
