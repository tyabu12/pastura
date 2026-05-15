import SwiftUI

/// A tiny moss-colored diamond used as a leading glyph on the model picker
/// header ("PASTURA · SETUP") and other Pastura captions following the
/// design-system "leaf" motif.
///
/// Rendered as a rotated `RoundedRectangle` so the diamond carries a slight
/// corner softening at scale — closer to a stylized leaf than a sharp
/// diamond. The default 6 pt matches the picker spec; larger sizes are
/// supported but the corner-radius scales with `size / 6` so the silhouette
/// stays consistent.
///
/// Decoration only — always `.accessibilityHidden(true)`. No identity-bearing
/// semantics for VoiceOver to surface.
struct LeafGlyph: View {
  var size: CGFloat = 6
  var color: Color = .moss
  var opacity: Double = 0.9

  var body: some View {
    // `cornerRadius: size / 6` keeps the visual softness proportional —
    // a hard square at 6pt has the same relative roundness as at 24pt.
    RoundedRectangle(cornerRadius: size / 6, style: .continuous)
      .fill(color)
      .opacity(opacity)
      .frame(width: size, height: size)
      .rotationEffect(.degrees(45))
      // Rotation makes the rendered bounding box larger than `size` by a
      // factor of √2 along each axis. Compensate so layout siblings see
      // the visual size, not the post-rotation bounding box.
      .frame(width: size * sqrt(2), height: size * sqrt(2))
      .accessibilityHidden(true)
  }
}

#Preview {
  HStack(spacing: 16) {
    LeafGlyph()
    LeafGlyph(size: 12)
    LeafGlyph(size: 24)
    LeafGlyph(size: 24, opacity: 0.4)
  }
  .padding()
  .background(Color.screenBackground)
}
