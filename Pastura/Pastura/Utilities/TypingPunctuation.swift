import Foundation

/// Extra pause (in milliseconds) inserted after a character is revealed
/// during typing animation, so the reader briefly registers sentence
/// structure. Values match common visual-novel conventions (Kirikiri /
/// Ren'Py range of 200–400ms for sentence ends, ~100ms for commas).
///
/// Returns 0 for characters that shouldn't trigger a pause.
///
/// This is a pure, dependency-free function so it can be reused when the
/// pseudo-typing animation is replaced by real token-by-token LLM streaming
/// (Phase 2 roadmap). Streaming handlers classify the **last character**
/// of the accumulated response buffer after each token arrives — identical
/// inputs, identical outputs.
///
/// - Parameter character: The character just revealed (or just received
///   from the streamed token).
/// - Returns: Extra pause in milliseconds to insert before revealing the
///   next character. `0` means no pause.
nonisolated func punctuationPauseMs(after character: Character) -> Int {
  // Sentence terminators. Includes full-width variants for Japanese input
  // and typographic substitutes occasionally used in LLM output.
  let sentenceEnders: Set<Character> = [
    "。", ".", "!", "?", "！", "？", "…"
  ]
  // Light commas and pauses. Full-width and half-width variants.
  let commas: Set<Character> = [
    "、", ",", "，"
  ]

  if sentenceEnders.contains(character) { return 300 }
  if commas.contains(character) { return 120 }
  return 0
}

/// Extra pause (in milliseconds) inserted between the statement and the
/// inner-thought sections of an agent output when both are being typed.
/// Functions as a rhetorical beat — the reader registers the end of the
/// spoken line before the private thought starts.
nonisolated let statementToThoughtPauseMs: Int = 300

/// Estimated wall-clock time (in milliseconds) the ``AgentOutputRow``
/// reveal animation spends typing `primary` followed by `thought` at
/// `charsPerSecond`, used by the demo replay's proportional turn-dwell floor
/// (``ReplayViewModel``) to hold the next turn until the bubble finishes.
///
/// Mirrors `AgentOutputRow.startAnimationIfNeeded`'s loop **exactly**, reusing
/// the same per-character ``punctuationPauseMs(after:)`` walk and the same
/// ``statementToThoughtPauseMs`` boundary beat (not just the same constants),
/// so the estimate and the animation cannot drift:
/// - `ceil(totalChars / cps * 1000)` base reveal time (one tick per grapheme),
/// - plus `punctuationPauseMs` summed over every revealed character,
/// - plus one `statementToThoughtPauseMs` beat iff **both** `primary` and
///   `thought` are non-empty (the reveal loop fires it when the counter
///   crosses the non-empty primary into a non-empty thought).
///
/// Pure and dependency-free (primitive inputs only — never a `TurnOutput`,
/// keeping the Utilities layer free of a Models dependency). Callers resolve
/// the segments via ``TurnOutput/revealedSegments(for:includeThought:)`` and
/// pass the strings down.
///
/// Returns `0` when `charsPerSecond <= 0` (mirrors the reveal loop's
/// `cps > 0` guard → snap to full, no dwell) or when there is nothing to type.
///
/// - Parameters:
///   - primary: The decorated primary text the row types first.
///   - thought: The private-thought text typed after the primary (empty when
///     the THINKING section is collapsed).
///   - charsPerSecond: Reveal rate; `<= 0` disables the estimate.
/// - Returns: Estimated typing duration in milliseconds.
nonisolated func typingDurationMs(
  primary: String, thought: String, charsPerSecond: Double
) -> Int {
  guard charsPerSecond > 0 else { return 0 }
  let full = primary + thought
  guard !full.isEmpty else { return 0 }

  let base = Int((Double(full.count) / charsPerSecond * 1000).rounded(.up))
  let punctuation = full.reduce(0) { $0 + punctuationPauseMs(after: $1) }
  let boundary =
    (!primary.isEmpty && !thought.isEmpty) ? statementToThoughtPauseMs : 0
  return base + punctuation + boundary
}
