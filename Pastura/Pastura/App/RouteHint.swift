import Foundation

// MARK: - RouteHint
//
// ⚠️ IDENTITY-NEUTRAL by design. Two `RouteHint` values with different
//    `.value` compare equal under `==` and hash to the same bucket.
//    DO NOT treat `==` between RouteHints as `.value` interchangeability —
//    always read `.value` from the specific instance you hold.
//
// Why this exists: `Route` enum cases sometimes need to carry render-time
// hints (e.g. an `initialName` to show in the navigation title before the
// destination view's async load completes). Putting such hints into normal
// associated values pollutes the enum's auto-synthesized Hashable: two
// pushes with the same `scenarioId` but different hints would compare
// unequal, silently breaking `AppRouter.pushIfOnTop(expected:next:)`
// guards that callers naturally write without specifying the hint.
//
// `RouteHint<T>`'s `==` is always `true` and `hash(into:)` is a no-op,
// so embedding `RouteHint<T>` inside an enum case lets the enum's
// auto-synthesized Hashable continue to use only the *identity-bearing*
// associated values (e.g. `scenarioId`) for equality.
//
// See `docs/decisions/ADR-008.md` for the full rationale (alternatives
// considered, KMP / state-restoration impact). Operational rule lives in
// `.claude/rules/navigation.md` § "Render-time hints — RouteHint".

/// A render-time hint that does NOT participate in `Equatable` /
/// `Hashable` identity.
///
/// Wrap render-only state — placeholder strings, animation parameters,
/// presentation flags — in `RouteHint<T>` when adding it as an
/// associated value of a `Route` (or any other Hashable enum) so that
/// the enum's identity remains solely about *where in the navigation
/// tree* we are, not *what hint we happened to carry on this push*.
///
/// The wrapped `value` is read normally via `.value`; only `==` and
/// `hashValue` are blind to it.
///
/// ```swift
/// enum Route: Hashable {
///   case scenarioDetail(
///     scenarioId: String,
///     initialName: RouteHint<String> = .init()
///   )
/// }
///
/// // These two compare ==, hash to the same bucket:
/// let a = Route.scenarioDetail(scenarioId: "x", initialName: .init("Foo"))
/// let b = Route.scenarioDetail(scenarioId: "x", initialName: .init())
/// // a == b  →  true (intentional)
///
/// // ⚠️ But their `.value` differs — never substitute one for the other
/// // when reading the hint:
/// // case .scenarioDetail(_, let hint): hint.value  // "Foo" vs nil
/// ```
// `nonisolated` because `Hashable`'s `==` / `hash(into:)` requirements
// are nonisolated; under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
// custom impls would inherit MainActor and crash the conformance.
// `Route` enum gets this for free via auto-synthesized Hashable;
// `RouteHint` provides explicit impls so it must opt out of the default.
nonisolated struct RouteHint<T: Hashable & Sendable>: Hashable, Sendable {
  /// The wrapped value. Read this directly — `==` is identity-neutral
  /// and gives no information about whether `.value` is set.
  let value: T?

  init(_ value: T? = nil) {
    self.value = value
  }

  // Identity-neutral: every RouteHint compares equal to every other
  // RouteHint of the same generic type.
  static func == (lhs: Self, rhs: Self) -> Bool { true }

  // Identity-neutral: contributes nothing to the hash. The Hashable
  // contract `a == b → a.hashValue == b.hashValue` is satisfied because
  // every pair compares equal and every pair contributes the same
  // (zero) bits to the hasher.
  func hash(into hasher: inout Hasher) {}
}
