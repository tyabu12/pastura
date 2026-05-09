/// Round-counter pair consumed by `GameHeader`'s row-2 ROUND fragment.
///
/// Wraps the `current` / `total` integers as a single optional value so the
/// pair-or-nothing semantic is encoded in the type system: a caller cannot
/// construct "current without total" or vice versa. Replaces the previous
/// `currentRound: Int? + totalRounds: Int?` parameters whose mutual
/// requirement was only enforced at the test-input level (#313).
///
/// Lives next to `GameHeaderStatus` in `Views/Components/` because it is a
/// presentation shape, not a domain entity — the wrapper only describes how
/// the header should display a round counter, not what a round means in the
/// scenario engine. If a future caller in `Engine/` or `Models/` needs
/// round-pair semantics, lift to `Models/` then; today there is no such
/// caller. The peer-type naming (`GameHeader<Concept>` rather than a bare
/// `Round`) mirrors the existing `GameHeaderStatus` convention and avoids a
/// generic-name collision in the global namespace.
///
/// `Sendable` is annotated ahead of need so the type can cross actor
/// boundaries cleanly when (a) a future ViewModel-side construction path
/// emerges, or (b) the `Views/Components/` directory is extracted into its
/// own SPM module. Today no producer crosses isolation, but two `let Int`
/// fields are trivially safe so the conformance is free.
public struct GameHeaderRound: Sendable, Equatable {
  /// Round-counter numerator (1-based; matches `formatRoundLabel`'s
  /// `Round %lld / %lld` source key).
  public let current: Int
  /// Round-counter denominator.
  public let total: Int

  public init(current: Int, total: Int) {
    self.current = current
    self.total = total
  }
}
