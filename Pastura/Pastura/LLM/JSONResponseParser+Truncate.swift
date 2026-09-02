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
  /// - **Start marker** — cut **only** after the first structural `{`. A *leading* one is
  ///   a template-header echo with the payload still behind it; cutting there deletes the
  ///   payload deterministically (the template config reproduces on every retry) →
  ///   `parse_failed` → `retriesExhausted` → an ADR-021 turn skip. One after the `{` is a
  ///   fabricated next turn, and leaving *it* uncovered would not be benign:
  ///   `extractFromCodeBlock` runs **before** the balanced-brace scan and takes `firstMatch`
  ///   unconditionally, so a fenced continuation would be accepted silently.
  ///
  /// - **End marker** — split on the marker literal, because #1422 holds a ChatML backend
  ///   byte-identical to the pre-#1422 hardcoded `<|im_end|>` cut:
  ///   - **`.chatML.end`**: cut from the first occurrence anywhere, string-blind.
  ///   - **Every other end marker**: string-aware, and cut only **after** the first
  ///     structural `{` — the same gate as the start arm, for the same reason. A leading
  ///     `<turn|>` is Gemma echoing its template's turn boundary, and the index-0 cut was
  ///     deterministic payload destruction (#1452). The gate is a search *origin*, so a
  ///     second occurrence after the `{` still truncates a fabricated continuation.
  ///     String-awareness matters here because a mid-value cut fails silently: the repair
  ///     pipeline closes the quote and brace and persists a truncated value.
  ///
  /// Three accepted gaps remain:
  ///
  /// 1. `<|im_end|>` inside a string value still cuts mid-value. Pre-existing; closing it
  ///    would move ChatML behaviour, which #1422 holds fixed.
  /// 2. A *leading* `<|im_end|>` still cuts at index 0 and destroys the payload →
  ///    `parse_failed` → retry. Gating it would make `<|im_end|>{"fake":1}` an accepted
  ///    fabricated object, the #1422 counter-example; on llama.cpp the `stopSequence` ends
  ///    generation at `<|im_end|>` anyway, so the shape reaches this parser only through
  ///    a backend with no stop sequence.
  /// 3. For a non-ChatML marker, `<turn|>{"fake":1}` — marker, then an object with nothing
  ///    before it — is **accepted**. The object is the only candidate, and rejecting it
  ///    deterministically is the #1452 skip again; it is also what pre-#1422 Gemma did,
  ///    having had no end arm at all. The finer rule (#1452 option 2: gate only when the
  ///    text after the marker holds no balanced object) was rejected as code against a
  ///    shape the corpus has never shown (`docs/models/eval-log.md` § "Spelled-out
  ///    chat-template markers").
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

    // First structural `{`, shared by both gated arms. `nil` when no string scan was
    // needed (only ChatML's end marker can fire then, and it is ungated) or when the text
    // has no structural brace — nothing parses in that case, so the non-ChatML end arm
    // falls back to a from-0 search rather than going inert.
    let firstBrace: Int? = machine.flatMap { machine in
      chars.indices.first(where: { chars[$0] == "{" && !machine.isInsideString(at: $0) })
    }

    // End arm — see the doc comment for the per-literal split and the three accepted
    // gaps. String-blindness measured on `{"note": "… <turn|> …"}`: accepted, repair
    // `unclosed_string+unclosed_brace`. Reachable for a *newly* added marker because
    // `stopSequence` strips only `<|im_end|>` by decision (#1451), so `<turn|>` is the
    // first end marker that survives generation.
    for marker in markers where !marker.end.isEmpty {
      let index: Int? =
        if marker.end == ChatTurnMarkers.chatML.end || machine == nil {
          Self.firstIndex(of: marker.end, in: chars, from: 0)
        } else if let machine {
          Self.firstIndex(
            of: marker.end, in: chars, from: firstBrace.map { $0 + 1 } ?? 0,
            outsideStringsOf: machine)
        } else {
          nil
        }
      if let index {
        cut = min(cut, index)
      }
    }

    // Start arm — cuts only after the first structural `{`, and skips markers
    // inside string literals.
    if let machine, let firstBrace,
      markers.contains(where: { !$0.start.isEmpty && text.contains($0.start) }) {
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
