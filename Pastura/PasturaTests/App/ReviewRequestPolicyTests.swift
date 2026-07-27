import Foundation
import Testing

@testable import Pastura

/// Eligibility tests for the App Store review prompt (#1279).
///
/// Scoped to the pure decision function only — the `UserDefaults`-backed
/// version stamp is process-wide state that would race sibling suites
/// (`testing.md` § "Splitting a Suite Across Files"), and it is a two-line
/// accessor pair mirroring ``FeatureFlags``.
@Suite(.timeLimit(.minutes(1)))
struct ReviewRequestPolicyTests {

  // MARK: - Threshold semantics

  /// Change-detector for the "prompt on the user's 3rd run" product decision.
  /// The constant counts runs *before* the one that just finished, so 2 here
  /// means 3 total. A failure is not a bug — it means the engagement bar moved
  /// and this expectation (plus the PR/issue rationale) needs updating.
  @Test func minimumPriorCompletedRunsMeansThirdRun() {
    #expect(ReviewRequestPolicy.minimumPriorCompletedRuns == 2)
  }

  @Test func eligibleOnTheThirdRun() {
    #expect(
      ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 2, degradedTurnCount: 0,
        lastRequestedVersion: nil, currentVersion: "1.1"))
  }

  @Test func notEligibleOnTheFirstTwoRuns() {
    for prior in 0...1 {
      #expect(
        !ReviewRequestPolicy.isEligible(
          priorCompletedRunCount: prior, degradedTurnCount: 0,
          lastRequestedVersion: nil, currentVersion: "1.1"))
    }
  }

  @Test func stillEligibleWellPastTheThreshold() {
    #expect(
      ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 42, degradedTurnCount: 0,
        lastRequestedVersion: nil, currentVersion: "1.1"))
  }

  // MARK: - Degradation gate (ADR-021)

  @Test func notEligibleAfterADegradedRun() {
    #expect(
      !ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 10, degradedTurnCount: 1,
        lastRequestedVersion: nil, currentVersion: "1.1"))
  }

  // MARK: - Once-per-version stamp

  @Test func notEligibleWhenAlreadyRequestedForThisVersion() {
    #expect(
      !ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 10, degradedTurnCount: 0,
        lastRequestedVersion: "1.1", currentVersion: "1.1"))
  }

  @Test func eligibleAgainAfterAVersionBump() {
    #expect(
      ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 10, degradedTurnCount: 0,
        lastRequestedVersion: "1.1", currentVersion: "1.2"))
  }

  // MARK: - Persisted key

  /// The `UserDefaults` key is a **migration contract**, not an
  /// implementation detail: renaming it resets the stamp for every existing
  /// user, so they get asked again on a version they were already asked on.
  /// Nothing else in the codebase pins the literal — the coordinator's tests
  /// read back through the same accessor and are agnostic to it.
  ///
  /// Uses an isolated store so the assertion never touches `.standard`.
  @Test func versionStampPersistsUnderItsDocumentedKey() throws {
    let suiteName = "app.pastura.tests.policy.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    ReviewRequestPolicy.markRequested(version: "1.1", defaults: defaults)

    #expect(defaults.string(forKey: "lastReviewRequestVersion") == "1.1")
    #expect(ReviewRequestPolicy.lastRequestedVersion(defaults: defaults) == "1.1")
  }

  // MARK: - Unreadable version fails closed

  /// Without a readable version there is nothing to stamp, so an "eligible"
  /// verdict would re-ask on every single completed run. Both the `nil` and
  /// the empty-string shapes must fail closed.
  @Test func notEligibleWhenCurrentVersionIsUnreadable() {
    #expect(
      !ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 10, degradedTurnCount: 0,
        lastRequestedVersion: nil, currentVersion: nil))
    #expect(
      !ReviewRequestPolicy.isEligible(
        priorCompletedRunCount: 10, degradedTurnCount: 0,
        lastRequestedVersion: nil, currentVersion: ""))
  }
}
