import PasturaSharedEngine
import Testing

@testable import Pastura

/// S5-1 acceptance: proves `SharedEngineLinkage.objcRuntimeNames` resolves
/// from the **app target** (ADR-023 §6 ruling (d)). It was written when the
/// Stage-2 gate spike's SPM package was the only place the names resolved;
/// that package is retired (S5-5) and the app target is the only consumer.
///
/// Pins the Objective-C export prefix. The *source-level* unprefixed naming
/// is not asserted here — it is proven by `SharedEngineLinkage` compiling at
/// all (see that type's doc comment for why the two facts differ).
@Suite(.timeLimit(.minutes(1)))
struct SharedEngineLinkageTests {
  @Test("§5 boundary types keep their PSE Objective-C runtime prefix")
  func boundaryTypesKeepObjCPrefix() {
    // Measured on the iOS simulator slice on 2026-08-30 — same values as the
    // macOS measurement taken on the (now retired) Stage-2 gate spike.
    #expect(
      SharedEngineLinkage.objcRuntimeNames == ["PSESimulationEngine", "PSEGenerationRequest"])
  }
}
