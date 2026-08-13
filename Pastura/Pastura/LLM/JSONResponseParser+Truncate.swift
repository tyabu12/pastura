import Foundation

/// Hallucinated-turn truncation, split out of `JSONResponseParser.swift`
/// (which sits at the `file_length` cap the pre-commit `swiftlint --strict`
/// treats as fatal).
///
/// `nonisolated` on the **extension** is load-bearing, not decoration: a plain
/// sibling-file extension of a `nonisolated` type inherits MainActor under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the diagnostic then fires
/// at the *call site* in the main file rather than here
/// (`.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension JSONResponseParser {
  /// Truncate at the first hallucinated turn boundary, keying on the loaded
  /// model's own markers rather than a hardcoded ChatML literal (#1422).
  ///
  /// ### The two arms are deliberately asymmetric
  ///
  /// The markers mean different things where they appear, so one predicate for
  /// both would be wrong in one direction or the other.
  ///
  /// - **End marker** — a turn boundary wherever it occurs: everything after it
  ///   belongs to a turn that is not this one. Cut with no `firstBrace` gate,
  ///   from the first occurrence to end-of-string. String-aware for every end
  ///   marker **except ChatML's own**, which stays blind so a ChatML backend is
  ///   byte-identical to pre-#1422 — the one exception the acceptance criterion
  ///   requires, and the reason the check is keyed on `.chatML.end` by literal.
  ///   Everything else is guarded, because a mid-value cut does not fail loudly:
  ///   the repair pipeline closes the quote and brace and persists a truncated
  ///   value.
  ///
  /// - **Start marker** — cut **only** at an occurrence after the first
  ///   structural `{`. A *leading* start marker is the model echoing its own
  ///   template header with the real payload still behind it; cutting there
  ///   deletes the payload, and deterministically so (the backend's template
  ///   config reproduces on every retry) → `parse_failed` → `retriesExhausted`
  ///   → an ADR-021 turn skip. One *after* the first `{` is a fabricated next
  ///   turn, and leaving it uncovered is not benign: `extractFromCodeBlock`
  ///   runs **before** the balanced-brace scan and takes `firstMatch`
  ///   unconditionally, so a fenced fabricated continuation is extracted and
  ///   accepted silently.
  ///
  /// ### Substring search, not regex
  ///
  /// Interpolating a descriptor value into a pattern is a live trap rather than
  /// a style question: Gemma's `<|turn>` contains a bare `|`, which compiles as
  /// the alternation `<` **or** `turn>` and would cut at the first `<` anywhere
  /// in the output — mass payload destruction for the default shipped model.
  /// The trailing `.*` of the old pattern also does nothing a prefix slice does
  /// not.
  ///
  /// - Parameters:
  ///   - text: Output text, already stripped of thinking tags.
  ///   - markers: The effective set, from `LLMService.knownTurnMarkers`.
  /// - Returns: `text` up to the earliest qualifying cut point, or `text`
  ///   unchanged when no marker qualifies.
  func truncateAtTurnMarkers(_ text: String, markers: [ChatTurnMarkers]) -> String {
    guard !markers.isEmpty, !text.isEmpty else { return text }
    let chars = Array(text)
    var cut = chars.count

    // Both arms may need string context. Pay for the scan only when something
    // actually calls for it: any start marker present, or any *non-ChatML* end
    // marker present (the ChatML end marker stays string-blind — see below).
    let needsStringScan =
      markers.contains(where: { !$0.start.isEmpty && text.contains($0.start) })
      || markers.contains(where: {
        !$0.end.isEmpty && $0.end != ChatTurnMarkers.chatML.end && text.contains($0.end)
      })
    let machine = needsStringScan ? StringStateMachine(text) : nil

    // End arm — no `firstBrace` gate (accepted gap 2 below), and string-aware
    // for every end marker EXCEPT ChatML's own.
    //
    // The asymmetry is not cosmetic. String-blindness corrupts silently: the cut
    // lands mid-value, the repair pipeline closes the quote and the brace, and
    // the truncated value parses and persists as the agent's answer. Measured on
    // `{"note": "… <turn|> …"}` — accepted, repair `unclosed_string+unclosed_brace`.
    // It is reachable for a *newly* added marker because `stopSequence` still
    // strips only `<|im_end|>` (#1451), so `<turn|>` is the first end marker that
    // survives generation. Guarding it is provably ChatML-neutral, which is the
    // whole reason the exception is keyed on the literal rather than on "the
    // first marker" or "the descriptor's own": ChatML backends must stay
    // byte-identical, and `.chatML.end` is exactly the value that was already
    // shipping blind.
    //
    // Two accepted gaps remain, both ChatML-only by construction now:
    //
    // 1. `<|im_end|>` inside a string value still cuts mid-value. Pre-existing
    //    and left alone: closing it would move ChatML behaviour, which #1422
    //    holds fixed. Worth closing on its own merits, separately.
    // 2. A *leading* end marker (before the first structural `{`) cuts at that
    //    index and destroys the entire payload → parse_failed → retry.
    //    Deliberately unchanged: the obvious `> firstBrace` guard is not
    //    strictly safer, because it makes `<|im_end|>{"fake":1}` an accepted
    //    fabricated object where today it fails and retries. Tracked in #1452.
    for marker in markers where !marker.end.isEmpty {
      let index: Int? =
        if marker.end == ChatTurnMarkers.chatML.end || machine == nil {
          Self.firstIndex(of: marker.end, in: chars, from: 0)
        } else if let machine {
          Self.firstIndex(of: marker.end, in: chars, from: 0, outsideStringsOf: machine)
        } else {
          nil
        }
      if let index {
        cut = min(cut, index)
      }
    }

    // Start arm — cuts only after the first structural `{`, and skips markers
    // inside string literals.
    if let machine,
      markers.contains(where: { !$0.start.isEmpty && text.contains($0.start) }),
      let firstBrace = chars.indices.first(where: {
        chars[$0] == "{" && !machine.isInsideString(at: $0)
      }) {
      for marker in markers where !marker.start.isEmpty {
        if let index = Self.firstIndex(
          of: marker.start, in: chars, from: firstBrace + 1, outsideStringsOf: machine) {
          cut = min(cut, index)
        }
      }
    }

    return cut == chars.count ? text : String(chars[..<cut])
  }

  /// First index at or after `from` where `needle` matches **outside** a JSON
  /// string literal. An occurrence inside one is payload content, not a turn
  /// boundary, so it is skipped and the scan continues past it.
  ///
  /// Deliberately a distinct name rather than a defaulted parameter on
  /// ``firstIndex(of:in:from:)``: a default would make every existing 3-argument
  /// call ambiguous.
  private static func firstIndex(
    of needle: String, in chars: [Character], from: Int,
    outsideStringsOf machine: StringStateMachine
  ) -> Int? {
    var searchFrom = from
    while let index = firstIndex(of: needle, in: chars, from: searchFrom) {
      if !machine.isInsideString(at: index) { return index }
      searchFrom = index + 1
    }
    return nil
  }

  /// First index in `chars` at or after `from` where `needle`'s characters
  /// match. Character-offset based so results line up with
  /// ``StringStateMachine/insideStringFlags``, which is indexed the same way.
  private static func firstIndex(
    of needle: String, in chars: [Character], from: Int
  ) -> Int? {
    let pattern = Array(needle)
    guard !pattern.isEmpty, from >= 0, chars.count >= pattern.count else { return nil }
    let last = chars.count - pattern.count
    guard from <= last else { return nil }
    for start in from...last
    where chars[start..<(start + pattern.count)].elementsEqual(pattern) {
      return start
    }
    return nil
  }
}
