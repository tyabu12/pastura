import Foundation

/// Phase label formatting for ``ModelDownloadHostView``. Lifted out of the
/// host-view file so the per-`PhaseType` switch (one new case per phase
/// added project-wide) can grow without nudging the host file over its
/// `file_length` budget. Final wording follows the copy pass per spec
/// §2 decision 13.
extension ModelDownloadHostView {

  func currentPhaseLabel(viewModel: ReplayViewModel) -> String {
    guard let phase = viewModel.currentPhase else { return "" }
    let name = Self.phaseDisplayName(phase)
    if let round = viewModel.currentRound {
      return "\(name)ラウンド \(round)"
    }
    return name
  }

  /// Human-readable Japanese label for a phase type. Keeps `PhaseType` free
  /// of view-layer formatting concerns.
  static func phaseDisplayName(_ phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return "発言"
    case .speakEach: return "個別発言"
    case .vote: return "投票"
    case .choose: return "選択"
    case .scoreCalc: return "スコア計算"
    case .assign: return "割当"
    case .eliminate: return "脱落"
    case .summarize: return "要約"
    case .conditional: return "条件分岐"
    case .eventInject: return "イベント注入"
    }
  }
}
