import Testing

@testable import KMPGateSpike

@Suite("Shared engine linkage")
struct SharedEngineLinkageTests {
  /// Pins the Objective-C export prefix. The *source-level* unprefixed naming
  /// is not asserted here — it is proven by `SharedEngineLinkage` compiling at
  /// all (see that type's doc comment for why the two facts differ).
  @Test("§5 boundary types keep their PSE Objective-C runtime prefix")
  func boundaryTypesKeepObjCPrefix() {
    #expect(
      SharedEngineLinkage.objcRuntimeNames == ["PSESimulationEngine", "PSEGenerationRequest"])
  }
}
