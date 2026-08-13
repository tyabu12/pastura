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
  ///   belongs to a turn that is not this one. Cut unguarded, from the first
  ///   occurrence to end-of-string. This is the pre-#1422 behaviour, generalized
  ///   from one hardcoded string to a set, so a ChatML backend is byte-identical.
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

    // End arm — unguarded and string-blind. String-blindness is a known,
    // accepted gap (a marker spelled inside a JSON string value cuts
    // mid-string): closing it would change behaviour for ChatML backends,
    // which this change holds fixed. See the PR body for #1422.
    for marker in markers where !marker.end.isEmpty {
      if let index = Self.firstIndex(of: marker.end, in: chars, from: 0) {
        cut = min(cut, index)
      }
    }

    // Start arm — needs string context, so pay for the scan only if some
    // start marker actually occurs at all.
    if markers.contains(where: { !$0.start.isEmpty && text.contains($0.start) }) {
      let machine = StringStateMachine(text)
      if let firstBrace = chars.indices.first(where: {
        chars[$0] == "{" && !machine.isInsideString(at: $0)
      }) {
        for marker in markers where !marker.start.isEmpty {
          var searchFrom = firstBrace + 1
          while let index = Self.firstIndex(of: marker.start, in: chars, from: searchFrom) {
            // A marker inside a string literal is payload content, not a turn
            // boundary — skip past it and keep looking.
            if !machine.isInsideString(at: index) {
              cut = min(cut, index)
              break
            }
            searchFrom = index + 1
          }
        }
      }
    }

    return cut == chars.count ? text : String(chars[..<cut])
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
