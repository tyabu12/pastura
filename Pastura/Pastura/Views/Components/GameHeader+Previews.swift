import SwiftUI

// Previews live in a sibling file because GameHeader.swift hit
// SwiftLint's 400-line `file_length` cap after the row-split refactor
// (#312). The preview suite is naturally self-contained — extracting
// it keeps the main file focused on the View + helpers + a11y label
// composition without touching public-API surface.

#Preview("Demo (preset + phase, no tok/s)") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "ワードウルフ",
      status: .demoing,
      round: GameHeaderRound(current: 1, total: 4),
      phaseLabel: "個別発言",
      extendsIntoTopSafeArea: true
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Simulating") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .simulating,
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: "negotiation",
      tokensPerSecond: 16.5
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Paused") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .paused,
      round: GameHeaderRound(current: 2, total: 5),
      phaseLabel: "negotiation",
      tokensPerSecond: 12.3
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("Sim — Completed") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: "囚人のジレンマ",
      status: .completed,
      round: GameHeaderRound(current: 5, total: 5),
      phaseLabel: "scoreboard"
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

#Preview("First-frame fallback (initialName)") {
  VStack(spacing: 0) {
    GameHeader(
      scenarioName: nil,
      initialName: "ワードウルフ",
      status: .simulating,
      phaseLabel: "loading"
    )
    Spacer()
  }
  .background(Color.screenBackground)
}

// Worst-case truncation preview: longest localized status label
// (`Simulating`) crossed with a long Japanese scenario name on the
// narrowest iPhone form factor. Sim's `ToolbarItem(.principal)` slot
// is even narrower than the `body`'s rendering width — this preview
// approximates the principal-slot constraint by clamping width. If
// the title doesn't truncate cleanly with the pill staying intact,
// the truncation contract (`.lineLimit(1) + .truncationMode(.tail)`
// on title; `.fixedSize + .layoutPriority(1)` on pill) has regressed.
#Preview("Sim — narrow / long-title truncation contract") {
  VStack(spacing: 12) {
    ForEach(
      [
        GameHeaderStatus.simulating,
        GameHeaderStatus.paused,
        GameHeaderStatus.completed,
        GameHeaderStatus.demoing
      ],
      id: \.self
    ) { status in
      GameHeader(
        scenarioName: "とても長い日本語のシナリオ名で切り詰めを検証する",
        status: status,
        round: GameHeaderRound(current: 12, total: 100),
        phaseLabel: "発言ラウンド",
        tokensPerSecond: 16.5
      )
      .frame(width: 320)  // approximates iPhone SE principal-slot width
    }
    Spacer()
  }
  .background(Color.screenBackground)
}
