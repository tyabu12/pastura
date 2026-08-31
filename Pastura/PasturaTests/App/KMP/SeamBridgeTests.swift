import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// S5-2 PR-B acceptance for the two seam bridges — ``EngineLoggerBridge`` and
/// ``LanguageDetectorBridge``, the App-side adapters that let Kotlin's
/// `SimulationEngine(detector:logger:random:)` reach the Swift concretes
/// (`OSLogEngineLogger` / `NLLanguageDetector`) unchanged (ADR-023 §5, #1647).
///
/// The bridges are called directly with the Kotlin enum statics rather than
/// through an engine run: what is under test is the enum mapping, and a run
/// would only exercise whichever levels its scenario happens to emit.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite("Kotlin seam bridges", .timeLimit(.minutes(1)))
struct SeamBridgeTests {

  // MARK: - EngineLoggerBridge

  @Test("every Kotlin level × privacy pair maps to a distinct Swift pair")
  func levelAndPrivacyMapDistinctly() {
    let recorder = RecordingEngineLogger()
    let bridge = EngineLoggerBridge(logger: recorder)

    let levels: [(PasturaSharedEngine.EngineLogLevel, Pastura.EngineLogLevel)] = [
      (.debug, .debug),
      (.info, .info),
      (.warning, .warning)
    ]
    let privacies: [(PasturaSharedEngine.EngineLogPrivacy, Pastura.EngineLogPrivacy)] = [
      (.public_, .public),
      (.private_, .private)
    ]

    for (kotlinLevel, swiftLevel) in levels {
      for (kotlinPrivacy, swiftPrivacy) in privacies {
        bridge.log(
          level: kotlinLevel,
          category: "StreamingDiag",
          message: "\(kotlinLevel.name)/\(kotlinPrivacy.name)",
          privacy: kotlinPrivacy)

        let last = recorder.lines.last
        #expect(last?.level == swiftLevel)
        #expect(last?.privacy == swiftPrivacy)
        #expect(last?.category == "StreamingDiag")
        #expect(last?.message == "\(kotlinLevel.name)/\(kotlinPrivacy.name)")
      }
    }

    // A mapping that collapsed onto a fallback would leave fewer than six
    // distinct pairs — this is the assertion a wrong identity comparison
    // reddens.
    #expect(recorder.lines.count == 6)
    let pairs = Set(recorder.lines.map { "\($0.level)/\($0.privacy)" })
    #expect(pairs.count == 6)
  }

  @Test("category and message cross the seam verbatim")
  func categoryAndMessagePassThrough() {
    let recorder = RecordingEngineLogger()
    let bridge = EngineLoggerBridge(logger: recorder)

    bridge.log(
      level: .info,
      category: "Simulation",
      message: "round 3 · agent Bob",
      privacy: .public_)

    #expect(recorder.lines.count == 1)
    #expect(recorder.lines.first?.category == "Simulation")
    #expect(recorder.lines.first?.message == "round 3 · agent Bob")
  }

  // MARK: - LanguageDetectorBridge

  @Test("a detected code is forwarded unchanged")
  func detectorForwardsHit() {
    let bridge = LanguageDetectorBridge(detector: StubLanguageDetector(result: "ja"))
    #expect(bridge.detect(text: "こんにちは、世界。") == "ja")
  }

  @Test("nil — the skip value — survives the seam as nil")
  func detectorForwardsSkip() {
    let bridge = LanguageDetectorBridge(detector: StubLanguageDetector(result: nil))
    #expect(bridge.detect(text: "ok") == nil)
  }

  @Test("the production NLLanguageDetector reaches Kotlin through the bridge")
  func detectorForwardsProductionConcrete() {
    let bridge = LanguageDetectorBridge(detector: NLLanguageDetector())
    #expect(bridge.detect(text: "今日は良い天気ですね。散歩に行きましょう。") == "ja")
  }
}

// MARK: - Test doubles

/// Records what the bridge forwards.
///
/// `nonisolated` + `Mutex`-guarded because Kotlin calls `EngineLogger.log`
/// from `Dispatchers.Default`; the direct-call tests above run on one thread,
/// but the double must model the real call contract
/// (`.claude/rules/swift-isolation.md` Pattern 7).
nonisolated final class RecordingEngineLogger: Pastura.EngineLogger, Sendable {
  struct Line: Sendable, Equatable {
    let level: Pastura.EngineLogLevel
    let category: String
    let message: String
    let privacy: Pastura.EngineLogPrivacy
  }

  private let state = Mutex<[Line]>([])

  var lines: [Line] { state.withLock { $0 } }

  func log(
    _ level: Pastura.EngineLogLevel,
    category: String,
    _ message: String,
    privacy: Pastura.EngineLogPrivacy
  ) {
    state.withLock {
      $0.append(Line(level: level, category: category, message: message, privacy: privacy))
    }
  }
}

/// A fixed-answer ``LanguageDetector`` — `NLLanguageRecognizer` is a
/// confidence-thresholded classifier, so a stub is what makes the `nil` case
/// deterministic.
nonisolated struct StubLanguageDetector: Pastura.LanguageDetector {
  let result: String?

  func detect(text: String) -> String? { result }
}
