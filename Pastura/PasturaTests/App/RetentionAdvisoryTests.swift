import Foundation
import Testing

@testable import Pastura

// `@MainActor` on the suite: `RetentionAdvisory` is an App-layer type and so
// is MainActor-isolated by the project's default-actor-isolation setting.
// Its `static func` is therefore a MainActor-isolated call; annotating the
// suite lets these nonisolated-context tests invoke it without hopping. (Not
// the auto-synth-conformance Pattern 5 — just a plain isolated static call.)
@Suite(.timeLimit(.minutes(1))) @MainActor
struct RetentionAdvisoryTests {
  private let threshold = RetentionAdvisory.advisoryByteThreshold

  @Test func thresholdIs250Megabytes() {
    #expect(threshold == 250 * 1024 * 1024)
  }

  @Test func belowThresholdDoesNotSurface() {
    #expect(!RetentionAdvisory.isOverAdvisoryCap(pastResultsByteCount: threshold - 1))
  }

  @Test func exactlyAtThresholdSurfaces() {
    #expect(RetentionAdvisory.isOverAdvisoryCap(pastResultsByteCount: threshold))
  }

  @Test func aboveThresholdSurfaces() {
    #expect(RetentionAdvisory.isOverAdvisoryCap(pastResultsByteCount: threshold + 1))
  }

  @Test func zeroDoesNotSurface() {
    #expect(!RetentionAdvisory.isOverAdvisoryCap(pastResultsByteCount: 0))
  }
}
