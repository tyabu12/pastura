import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct RouteHintTests {

  // MARK: - Standalone identity-neutral contract

  @Test func differentValuesCompareEqual() {
    let a = RouteHint<String>("Foo")
    let b = RouteHint<String>("Bar")
    #expect(a == b)
  }

  @Test func nilValueComparesEqualToNonNil() {
    let nilHint = RouteHint<String>()
    let setHint = RouteHint<String>("Foo")
    #expect(nilHint == setHint)
  }

  @Test func differentValuesProduceEqualHash() {
    let a = RouteHint<String>("Foo")
    let b = RouteHint<String>("Bar")
    #expect(a.hashValue == b.hashValue)
  }

  @Test func valueIsReadable() {
    // Identity-neutral `==` does NOT mean values are interchangeable;
    // `.value` must remain readable for hint consumers.
    let hint = RouteHint<String>("Foo")
    #expect(hint.value == "Foo")
    let empty = RouteHint<String>()
    #expect(empty.value == nil)
  }

  // MARK: - Auto-synthesis interaction inside an enum

  // Mirrors the Route shape `case scenarioDetail(scenarioId: String,
  // initialName: RouteHint<String>)`. Verifies the production code path:
  // when an enum auto-synthesizes Hashable across one identity-bearing
  // value (`scenarioId`) and one identity-neutral hint, equality and hash
  // depend on the identity-bearing value only.
  private enum TestRoute: Hashable {
    case detail(id: String, hint: RouteHint<String>)
    case other(id: String, hint: RouteHint<Int>)
  }

  @Test func enumDifferingOnlyByHintValueComparesEqual() {
    let withHint = TestRoute.detail(id: "x", hint: .init("Foo"))
    let withoutHint = TestRoute.detail(id: "x", hint: .init())
    #expect(withHint == withoutHint)
  }

  @Test func enumDifferingByIdComparesUnequal() {
    let idX = TestRoute.detail(id: "x", hint: .init("Foo"))
    let idY = TestRoute.detail(id: "y", hint: .init("Foo"))
    #expect(idX != idY)
  }

  @Test func enumDifferingOnlyByHintProducesEqualHash() {
    let withHint = TestRoute.detail(id: "x", hint: .init("Foo"))
    let withoutHint = TestRoute.detail(id: "x", hint: .init())
    #expect(withHint.hashValue == withoutHint.hashValue)
  }

  @Test func enumWithDifferentCasesIsDistinguishedByDiscriminator() {
    // Different cases must still compare unequal even when both carry
    // identity-neutral hints — the case discriminator carries identity.
    let detail = TestRoute.detail(id: "x", hint: .init())
    let other = TestRoute.other(id: "x", hint: .init())
    #expect(detail != other)
  }
}
