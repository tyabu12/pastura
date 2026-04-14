import SwiftUI
import UIKit

/// A SwiftUI wrapper around `UIActivityViewController` for the iOS share sheet.
///
/// `activityItems` is typed as `[Any]` to accept heterogeneous payloads — callers
/// commonly pass `[String, URL]` so messaging activities receive the text body
/// while file-oriented activities (Save to Files, AirDrop) pick up the URL.
/// See Apple's documentation for `UIActivityViewController` for the list of
/// types each built-in activity accepts.
struct ShareSheet: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    // No dynamic updates needed — the sheet's contents are fixed once presented.
  }
}
