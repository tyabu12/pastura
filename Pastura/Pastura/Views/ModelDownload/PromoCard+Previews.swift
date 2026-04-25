import SwiftUI

// Lifted from `PromoCard.swift` so that file stays under swiftlint's
// 400-line cap after the inline-cancel UX addition.

#Preview("Downloading 35%") {
  PromoCard(
    modelState: .downloading(progress: 0.35),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Downloading 35% with cancel") {
  PromoCard(
    modelState: .downloading(progress: 0.35),
    replayHadStarted: true,
    onRetry: {},
    onCancel: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Downloading 95%") {
  PromoCard(
    modelState: .downloading(progress: 0.95),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Error after start (retry)") {
  PromoCard(
    modelState: .error("ネットワーク接続が切れました"),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Error after start (retry + cancel)") {
  PromoCard(
    modelState: .error("ネットワーク接続が切れました"),
    replayHadStarted: true,
    onRetry: {},
    onCancel: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}
