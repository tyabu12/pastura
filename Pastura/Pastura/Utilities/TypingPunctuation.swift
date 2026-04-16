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
