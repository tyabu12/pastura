import PasturaSharedEngine
import Testing

@testable import Pastura

/// S5-2 PR-A acceptance: the Kotlin → Swift `OutputSchema` converter the
/// Stage-5 `LLMBackend` adapter needs to keep GBNF-constrained decoding alive
/// across the K/N boundary (#1647).
///
/// Kotlin types are spelled `PasturaSharedEngine.X` throughout — `OutputSchema`
/// is one of the shadowed twins (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite(.timeLimit(.minutes(1)))
struct OutputSchemaBridgeTests {

  @Test("field names, order and kinds survive the conversion")
  func convertsFieldsInOrder() {
    let shared = PasturaSharedEngine.OutputSchema(fields: [
      PasturaSharedEngine.OutputSchema.Field(
        name: "action", kind: PasturaSharedEngine.OutputSchema.KindChoice.shared),
      PasturaSharedEngine.OutputSchema.Field(
        name: "inner_thought", kind: PasturaSharedEngine.OutputSchema.KindStringKind.shared)
    ])

    let converted = OutputSchema(shared: shared)

    #expect(
      converted
        == OutputSchema(fields: [
          OutputSchema.Field(name: "action", kind: .choice),
          OutputSchema.Field(name: "inner_thought", kind: .string)
        ]))
  }

  @Test("a nil Kotlin schema maps to nil — no constrained decoding")
  func nilMapsToNil() {
    #expect(OutputSchema.fromShared(nil) == nil)
  }

  @Test("an empty field list converts to an empty Swift schema")
  func emptyFieldsConvert() {
    let shared = PasturaSharedEngine.OutputSchema(fields: [])

    #expect(OutputSchema.fromShared(shared) == OutputSchema(fields: []))
  }
}
