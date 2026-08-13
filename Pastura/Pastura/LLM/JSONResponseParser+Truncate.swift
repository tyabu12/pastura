import Foundation

/// Hallucinated-turn truncation, split out of `JSONResponseParser.swift` (which sits at the
/// `file_length` cap `swiftlint --strict` treats as fatal).
///
/// `nonisolated` on the **extension** is load-bearing: a plain sibling-file extension of a
/// `nonisolated` type inherits MainActor, and the diagnostic then fires at the *call site*
/// in the main file rather than here (`.claude/rules/swift-isolation.md` Pattern 3).
nonisolated extension JSONResponseParser {
  /// Truncate at the first hallucinated turn boundary, keying on the loaded model's own
  /// markers rather than a hardcoded ChatML literal (#1422).
  ///
  /// ### The two arms are deliberately asymmetric
  ///
  /// The markers mean different things where they appear, so one predicate for both would
  /// be wrong in one direction or the other.
  ///
  /// - **End marker** — a boundary wherever it occurs: cut from the first occurrence to
  ///   end-of-string, no `firstBrace` gate. String-aware for every end marker **except
  ///   `.chatML.end`**, keyed on that literal so a ChatML backend stays byte-identical to
  ///   pre-#1422. Everything else is guarded because a mid-value cut fails silently: the
  ///   repair pipeline closes the quote and brace and persists a truncated value.
  ///
  /// - **Start marker** — cut **only** after the first structural `{`. A *leading* one is
  ///   a template-header echo with the payload still behind it; cutting there deletes the
  ///   payload deterministically (the template config reproduces on every retry) →
  ///   `parse_failed` → `retriesExhausted` → an ADR-021 turn skip. One after the `{` is a
  ///   fabricated next turn, and leaving *it* uncovered would not be benign:
  ///   `extractFromCodeBlock` runs **before** the balanced-brace scan and takes `firstMatch`
  ///   unconditionally, so a fenced continuation would be accepted silently.
  ///
  /// Two accepted gaps remain, both ChatML-only by construction:
  ///
  /// 1. `<|im_end|>` inside a string value still cuts mid-value. Pre-existing; closing it
  ///    would move ChatML behaviour, which #1422 holds fixed.
  /// 2. A *leading* end marker cuts at that index and destroys the payload →
  ///    `parse_failed` → retry. Left as-is: a `> firstBrace` guard is not strictly safer,
  ///    because it makes `<|im_end|>{"fake":1}` an accepted fabricated object where today
  ///    it fails and retries. Tracked in #1452.
  ///
  /// ### Substring search, not regex
  ///
  /// Interpolating a descriptor value into a pattern is a live trap: Gemma's `<|turn>`
  /// contains a bare `|`, which compiles as `<` **or** `turn>` and would cut at the first
  /// `<` anywhere in the output — mass payload destruction for the default shipped model.
  /// The old pattern's trailing `.*` also does nothing a prefix slice does not.
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

    // End arm — see the doc comment for the asymmetry and the two accepted gaps.
    // String-blindness measured on `{"note": "… <turn|> …"}`: accepted, repair
    // `unclosed_string+unclosed_brace`. Reachable for a *newly* added marker because
    // `stopSequence` still strips only `<|im_end|>` (#1451), so `<turn|>` is the first
    // end marker that survives generation.
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
  /// A distinct name rather than a defaulted parameter on ``firstIndex(of:in:from:)``,
  /// which would make every existing 3-argument call ambiguous.
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
