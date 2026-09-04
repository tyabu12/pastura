import Foundation
import StoreKit
import Testing

@testable import Pastura

/// Covers `BuildChannel.isSandboxEnvironment(_:)`, the pure half of the
/// channel hint (ADR-023 §6 S5-3 H7 prerequisite).
///
/// Only the pure function is exercised here: `resolveIsSandboxOrDebug()` is
/// hard-wired to `true` under `#if DEBUG` and the unit suite only ever runs in
/// a Debug build, so the StoreKit branch is unreachable from the suite. That
/// is exactly why the environment classification is factored out.
@Suite(.timeLimit(.minutes(1)))
struct BuildChannelTests {
  @Test("sandbox is the TestFlight / App Review / local-Release channel")
  func sandboxIsRecognised() {
    #expect(BuildChannel.isSandboxEnvironment(.sandbox) == true)
  }

  @Test("xcode (local StoreKit configuration) is a non-production channel")
  func xcodeIsRecognised() {
    #expect(BuildChannel.isSandboxEnvironment(.xcode) == true)
  }

  @Test("production is not the sandbox channel")
  func productionIsNotSandbox() {
    #expect(BuildChannel.isSandboxEnvironment(.production) == false)
  }
}
