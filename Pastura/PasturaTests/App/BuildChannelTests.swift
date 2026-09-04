import Foundation
import Testing

@testable import Pastura

/// Covers `BuildChannel.isSandboxReceipt(_:)`, the pure half of the channel
/// hint (ADR-023 §6 S5-3 H7 prerequisite).
///
/// Only the pure function is exercised here: `BuildChannel.isSandboxOrDebug`
/// is hard-wired to `true` under `#if DEBUG` and the unit suite only ever
/// runs in a Debug build, so the receipt branch is unreachable from the
/// suite. That is exactly why the receipt classification is factored out.
@Suite(.timeLimit(.minutes(1)))
struct BuildChannelTests {
  @Test("a sandboxReceipt path is the TestFlight / App Review / local-Release channel")
  func sandboxReceiptIsRecognised() {
    let url = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/StoreKit/sandboxReceipt")
    #expect(BuildChannel.isSandboxReceipt(url) == true)
  }

  @Test("a production receipt path is not the sandbox channel")
  func productionReceiptIsNotSandbox() {
    let url = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/StoreKit/receipt")
    #expect(BuildChannel.isSandboxReceipt(url) == false)
  }

  @Test("a missing receipt URL is not the sandbox channel")
  func missingReceiptIsNotSandbox() {
    #expect(BuildChannel.isSandboxReceipt(nil) == false)
  }
}
