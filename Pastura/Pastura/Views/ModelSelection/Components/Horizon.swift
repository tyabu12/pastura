import SwiftUI

/// A 1pt-tall horizontal gradient line ("transparent → moss → transparent")
/// used between the picker header and the model list. Read as a quiet
/// horizon — pastoral motif, sets the gaze before the choice begins.
///
/// Default opacity at the center is 0.42 — the spec value. The endpoints
/// are fully transparent so the line dissolves into the page rather than
/// terminating abruptly. Decorative; `.accessibilityHidden(true)`.
struct Horizon: View {
  var color: Color = .moss
  var maxCenterOpacity: Double = 0.42
  var height: CGFloat = 1

  var body: some View {
    LinearGradient(
      gradient: Gradient(stops: [
        .init(color: color.opacity(0), location: 0.0),
        .init(color: color.opacity(maxCenterOpacity), location: 0.5),
        .init(color: color.opacity(0), location: 1.0)
      ]),
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(height: height)
    .accessibilityHidden(true)
  }
}

#Preview {
  VStack(spacing: 24) {
    Horizon()
    Horizon(maxCenterOpacity: 0.8)
    Horizon(color: .mossDark, maxCenterOpacity: 0.6)
    Horizon(height: 2)
  }
  .padding()
  .background(Color.screenBackground)
}
