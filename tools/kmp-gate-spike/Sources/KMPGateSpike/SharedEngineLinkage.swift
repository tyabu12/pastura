import PasturaSharedEngine

/// Proves the staged `PasturaSharedEngine.xcframework` actually links and pins
/// the shape of its exported ADR-023 §5 surface.
///
/// Two distinct facts, proven two different ways — they are easy to conflate:
///
/// 1. **Source-level naming.** Kotlin/Native exports these types with a `PSE`
///    Objective-C prefix, but each carries a `swift_name` attribute, so Swift
///    source refers to them unprefixed. Nothing asserts this at runtime: the
///    proof is that this file names `SimulationEngine` and compiles. Drop the
///    attributes and every call site in this package stops building.
/// 2. **Runtime naming.** `String(describing:)` reports the *Objective-C*
///    runtime name, which keeps the prefix — `swift_name` renames the
///    reference, not the class. That is what `objcRuntimeNames` pins, so a
///    change to the export prefix fails loudly here rather than surfacing as a
///    confusing symbol mismatch at Stage 5.
nonisolated public enum SharedEngineLinkage {
  /// Objective-C runtime names of the §5.1 entry point and a §5.2 payload
  /// type. Referencing the metatypes is the linkage check — it does not run
  /// the engine.
  public static var objcRuntimeNames: [String] {
    [
      String(describing: SimulationEngine.self),
      String(describing: GenerationRequest.self)
    ]
  }
}
