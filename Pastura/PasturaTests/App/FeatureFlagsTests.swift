import Foundation
import Testing

@testable import Pastura

// Tests for `FeatureFlags.keepRunningOnLeaveEnabled` (Phase B PR2, ADR-017):
// the opt-in flag that suppresses the leave dialog and parks a run silently.
//
// Serialized: the tests mutate the shared `UserDefaults.standard` key, so they
// must not interleave with each other. Each test removes the key on exit so the
// suite leaves no residue (and the unset-default test is order-independent).
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FeatureFlagsTests {
  private static let key = "keepRunningOnLeaveEnabled"

  @Test func defaultsToFalseWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.key)
    defer { UserDefaults.standard.removeObject(forKey: Self.key) }

    #expect(
      FeatureFlags.keepRunningOnLeaveEnabled == false,
      "opt-in flag is off until the user enables it")
  }

  @Test func reflectsPersistedValue() {
    defer { UserDefaults.standard.removeObject(forKey: Self.key) }

    FeatureFlags.setKeepRunningOnLeave(true)
    #expect(FeatureFlags.keepRunningOnLeaveEnabled == true)

    FeatureFlags.setKeepRunningOnLeave(false)
    #expect(
      FeatureFlags.keepRunningOnLeaveEnabled == false,
      "an explicit off is distinguished from unset and honoured")
  }

  // MARK: - viewerPredictionEnabled (#915) — opt-out flag (default true)

  private static let predictionKey = "viewerPredictionEnabled"

  @Test func viewerPredictionDefaultsToTrueWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.predictionKey)
    defer { UserDefaults.standard.removeObject(forKey: Self.predictionKey) }

    #expect(
      FeatureFlags.viewerPredictionEnabled == true,
      "opt-out flag is on until the user disables it")
  }

  @Test func viewerPredictionReflectsPersistedValue() {
    defer { UserDefaults.standard.removeObject(forKey: Self.predictionKey) }

    FeatureFlags.setViewerPredictionEnabled(false)
    #expect(
      FeatureFlags.viewerPredictionEnabled == false,
      "an explicit off is distinguished from the on-by-default and honoured")

    FeatureFlags.setViewerPredictionEnabled(true)
    #expect(FeatureFlags.viewerPredictionEnabled == true)
  }

  // MARK: - h7CrashProbeEnabled (ADR-023 §6 S5-3 H7) — opt-in flag (default false)

  private static let h7CrashProbeKey = "h7CrashProbeEnabled"

  @Test func h7CrashProbeDefaultsToFalseWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.h7CrashProbeKey)
    defer { UserDefaults.standard.removeObject(forKey: Self.h7CrashProbeKey) }

    #expect(
      FeatureFlags.h7CrashProbeEnabled == false,
      "the diagnostics row stays hidden until the 5-tap gesture opts in")
  }

  @Test func h7CrashProbeReflectsPersistedValue() {
    defer { UserDefaults.standard.removeObject(forKey: Self.h7CrashProbeKey) }

    FeatureFlags.setH7CrashProbeEnabled(true)
    #expect(FeatureFlags.h7CrashProbeEnabled == true)

    FeatureFlags.setH7CrashProbeEnabled(false)
    #expect(
      FeatureFlags.h7CrashProbeEnabled == false,
      "an explicit off is distinguished from unset and honoured")
  }
}
