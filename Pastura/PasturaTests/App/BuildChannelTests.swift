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

/// Covers `BuildChannel.resolve(environment:receiptURL:)`, the pure
/// decision behind `resolveIsSandboxOrDebug()`'s Release arm (#1677).
///
/// The branch that *reaches* the receipt fallback — `AppTransaction.shared`
/// throwing — is unreachable from the suite for the same `#if DEBUG` reason
/// as above, so the decision is factored into a pure function and the
/// StoreKit-failure input is modelled as `environment == nil`.
@Suite(.timeLimit(.minutes(1)))
struct BuildChannelResolveTests {
  private static let sandboxReceipt = URL(fileURLWithPath: "/app/StoreKit/sandboxReceipt")
  private static let productionReceipt = URL(fileURLWithPath: "/app/StoreKit/receipt")

  @Test("a StoreKit answer wins over the receipt name, in both directions")
  func environmentWins() {
    #expect(BuildChannel.resolve(environment: .sandbox, receiptURL: Self.productionReceipt) == true)
    #expect(BuildChannel.resolve(environment: .production, receiptURL: Self.sandboxReceipt) == false)
  }

  @Test("StoreKit failure + sandboxReceipt → sandbox (the TestFlight shape)")
  func fallbackSandboxReceipt() {
    #expect(BuildChannel.resolve(environment: nil, receiptURL: Self.sandboxReceipt) == true)
  }

  @Test("StoreKit failure + production receipt → App Store shape")
  func fallbackProductionReceipt() {
    #expect(BuildChannel.resolve(environment: nil, receiptURL: Self.productionReceipt) == false)
  }

  @Test("StoreKit failure + no receipt URL → safe default")
  func fallbackNoReceipt() {
    #expect(BuildChannel.resolve(environment: nil, receiptURL: nil) == false)
  }
}
