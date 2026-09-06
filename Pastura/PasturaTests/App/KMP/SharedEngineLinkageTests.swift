import PasturaSharedEngine
import Testing

@testable import Pastura

/// S5-1 acceptance: proves `SharedEngineLinkage.objcRuntimeNames` resolves
/// from the **app target**, not only from the `tools/kmp-gate-spike` SPM
/// package (ADR-023 §6 ruling (d)).
///
/// Pins the Objective-C export prefix. The *source-level* unprefixed naming
/// is not asserted here — it is proven by `SharedEngineLinkage` compiling at
/// all (see that type's doc comment for why the two facts differ).
@Suite(.timeLimit(.minutes(1)))
struct SharedEngineLinkageTests {
  @Test("§5 boundary types keep their PSE Objective-C runtime prefix")
  func boundaryTypesKeepObjCPrefix() {
    // Measured on the iOS simulator slice on 2026-08-30 — same values as the
    // macOS gate-spike measurement.
    #expect(
      SharedEngineLinkage.objcRuntimeNames == ["PSESimulationEngine", "PSEGenerationRequest"])
  }
}
