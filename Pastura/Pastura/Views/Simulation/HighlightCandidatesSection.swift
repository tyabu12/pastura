import SwiftUI

/// The end-of-run "Share a highlight" section (#1070 Stage 2): lists
/// automatic share-highlight candidates surfaced from the run's turns.
/// Tapping a row invokes the caller-supplied `onShare` closure, which opens
/// the existing share-card sheet with the same `(agent, output, phaseType)`
/// triple the row previews — no re-derivation.
///
/// Callers should only mount this view when `candidates` is non-empty; the
/// body still guards internally so an empty array renders nothing.
struct HighlightCandidatesSection: View {
  let candidates: [HighlightCandidate]
  let onShare: (HighlightCandidate) -> Void

  var body: some View {
    if !candidates.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(String(localized: "Share a highlight"))
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Color.ink)

        Text(String(localized: "Turn a standout moment into a card. Tap to open the share card."))
          .font(.system(size: 11.5))
          .foregroundStyle(Color.muted)
          .padding(.bottom, 8)

        VStack(spacing: 9) {
          ForEach(candidates) { candidate in
            Button {
              onShare(candidate)
            } label: {
              row(for: candidate)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              String(format: String(localized: "Share %@'s highlight"), candidate.agent))
          }
        }
      }
    }
  }

  private func row(for candidate: HighlightCandidate) -> some View {
    HStack(spacing: 11) {
      SheepAvatar(character: .forAgent(candidate.agent, position: nil), size: 40)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(candidate.agent)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.ink)
            .lineLimit(1)

          reasonChip(for: candidate.reason)
        }

        Text(candidate.previewText)
          .font(.system(size: 12))
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(2)
          .truncationMode(.tail)
      }

      Spacer(minLength: 8)

      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 15))
        .foregroundStyle(Color.muted)
    }
    .padding(11)
    .background(RoundedRectangle(cornerRadius: 14).fill(Color.bubbleBackground))
  }

  private func reasonChip(for reason: HighlightReason) -> some View {
    let style = ChipStyle(reason: reason)
    // `style.word` is already `String(localized:)`-resolved; compose verbatim
    // so the emoji-prefixed string isn't re-read as a LocalizedStringKey lookup
    // (`.claude/rules/i18n.md` § convenience-init label trap).
    return Text(verbatim: "\(style.emoji) \(style.word)")
      .font(.system(size: 10, weight: .bold))
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(Capsule().fill(style.background))
      .foregroundStyle(style.textColor)
  }

  /// Emoji + localized word + capsule colors for a candidate's reason chip.
  ///
  /// All three arms are the design-system §2.6 `<family>Soft` fill +
  /// `<family>Ink` text pairing — for `.revealed` on the opaque `mossSoft`
  /// ground see `ContradictionBadge` for the derivation (#1407).
  ///
  /// Internal rather than `private` so `DesignTokensTests+MossSoftGround` can
  /// pin which token the `.revealed` arm reads.
  struct ChipStyle {
    let emoji: String
    let word: String
    let background: Color
    let textColor: Color

    init(reason: HighlightReason) {
      switch reason {
      case .contradiction:
        emoji = "🃏"
        word = String(localized: "Contradiction")
        background = Color.warningSoft
        textColor = Color.warningInk
      case .revealed:
        emoji = "🎯"
        word = String(localized: "Revealed")
        background = Color.mossSoft
        textColor = Color.mossInk
      case .reaction:
        emoji = "💥"
        word = String(localized: "Turning point")
        background = Color.infoSoft
        textColor = Color.infoInk
      }
    }
  }
}

#Preview {
  HighlightCandidatesSection(
    candidates: [
      HighlightCandidate(
        id: UUID(),
        agent: "Bob",
        output: TurnOutput(fields: [
          "statement": "I'll cooperate for sure, trust me — then betrayed everyone next turn."
        ]),
        phaseType: .speakAll,
        reason: .contradiction),
      HighlightCandidate(
        id: UUID(),
        agent: "Carol",
        output: TurnOutput(fields: [
          "statement": "Everyone calm down. I think Alice is the suspicious one here."
        ]),
        phaseType: .speakAll,
        reason: .revealed),
      HighlightCandidate(
        id: UUID(),
        agent: "Alice",
        output: TurnOutput(fields: [
          "statement": "Wait — if the storm just hit, we should regroup now."
        ]),
        phaseType: .speakAll,
        reason: .reaction)
    ],
    onShare: { _ in }
  )
  .padding()
}
