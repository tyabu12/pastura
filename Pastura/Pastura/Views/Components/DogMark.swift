import SwiftUI

/// The Pastura assistant mark — a dog (collie) profile rendered as pure SwiftUI shapes.
///
/// Used in two places in the demo-replay feature:
/// - 26 pt inside `PromoCard` (body row, left of promo copy) — pass default `size`.
/// - 44 pt inside `DLCompleteOverlay` (fullscreen completion state) — pass `size: 44`.
///
/// The shape is a direct SwiftUI `Canvas` translation of the `DOG_SIDE` SVG constant
/// in `docs/design/demo-replay-reference.html` (viewBox 0 0 26 26). Path coordinates
/// are expressed as fractions of the 26-unit viewBox, then multiplied by `(size / 26)`
/// to scale cleanly to any target point size.
///
/// Colors follow `design-system.md` §2.3 Moss tokens:
/// - Body fill: `Color.white` (explicit — the bubbleBackground token is also white but
///   `DogMark` appears on varied surfaces, so plain white is the right semantic).
/// - Outline / ear / tail accent: `Color.moss` (`#8A9A6C`).
/// - Eye / nose dots: `Color.mossInk` (`#3D4030`).
///
/// Combine with `.pulsing()` for the Frame 4 DL-complete animation (scale 1.0 ↔ 1.06,
/// 2.4 s ease-in-out loop). The modifier is automatically disabled when
/// `accessibilityReduceMotion` is active.
public struct DogMark: View {

  /// Point size of the bounding square. Defaults to 26 pt (PromoBody usage).
  /// Pass 44 for the `DLCompleteOverlay` variant.
  public var size: CGFloat = 26

  public var body: some View {
    Canvas { ctx, canvasSize in
      let s = canvasSize.width
      // All geometry is expressed as fractions of the 26-unit SVG viewBox.
      // Multiplying by (s / 26) maps viewBox coordinates to canvas points.
      let u = s / 26

      // MARK: Body path — dog head/profile silhouette
      // Translated from the DOG_SIDE SVG:
      //   M5 14 Q5 9, 9 7.5 L11 5 L12.5 8 Q17 8.5, 19.5 11 Q21 12.5, 21 14.5
      //   L22 16 L20 16.5 Q18.5 19, 15 19 L10.5 19 Q7 18.5, 5.5 16 Z
      var body = Path()
      body.move(to: CGPoint(x: 5 * u, y: 14 * u))
      body.addQuadCurve(
        to: CGPoint(x: 9 * u, y: 7.5 * u),
        control: CGPoint(x: 5 * u, y: 9 * u))
      body.addLine(to: CGPoint(x: 11 * u, y: 5 * u))
      body.addLine(to: CGPoint(x: 12.5 * u, y: 8 * u))
      body.addQuadCurve(
        to: CGPoint(x: 19.5 * u, y: 11 * u),
        control: CGPoint(x: 17 * u, y: 8.5 * u))
      body.addQuadCurve(
        to: CGPoint(x: 21 * u, y: 14.5 * u),
        control: CGPoint(x: 21 * u, y: 12.5 * u))
      body.addLine(to: CGPoint(x: 22 * u, y: 16 * u))
      body.addLine(to: CGPoint(x: 20 * u, y: 16.5 * u))
      body.addQuadCurve(
        to: CGPoint(x: 15 * u, y: 19 * u),
        control: CGPoint(x: 18.5 * u, y: 19 * u))
      body.addLine(to: CGPoint(x: 10.5 * u, y: 19 * u))
      body.addQuadCurve(
        to: CGPoint(x: 5.5 * u, y: 16 * u),
        control: CGPoint(x: 7 * u, y: 18.5 * u))
      body.closeSubpath()

      ctx.fill(body, with: .color(.white))
      ctx.stroke(
        body,
        with: .color(Color.moss),
        style: StrokeStyle(lineWidth: 1.3 * u, lineCap: .round, lineJoin: .round))

      // MARK: Nose dot — cx=20 cy=14.8 r=1.1
      let nosePath = Path(
        ellipseIn: CGRect(
          x: (20 - 1.1) * u, y: (14.8 - 1.1) * u,
          width: 2.2 * u, height: 2.2 * u))
      ctx.fill(nosePath, with: .color(Color.mossInk))

      // MARK: Eye dot — cx=14 cy=12 r=0.9
      let eyePath = Path(
        ellipseIn: CGRect(
          x: (14 - 0.9) * u, y: (12 - 0.9) * u,
          width: 1.8 * u, height: 1.8 * u))
      ctx.fill(eyePath, with: .color(Color.mossInk))

      // MARK: Ear detail stroke — M9 7.5 Q8 10, 8.8 12
      var ear = Path()
      ear.move(to: CGPoint(x: 9 * u, y: 7.5 * u))
      ear.addQuadCurve(
        to: CGPoint(x: 8.8 * u, y: 12 * u),
        control: CGPoint(x: 8 * u, y: 10 * u))
      ctx.stroke(
        ear,
        with: .color(Color.moss),
        style: StrokeStyle(lineWidth: 0.9 * u, lineCap: .round))

      // MARK: Back / tail accent stroke — M15 16 Q17 16.5, 19 16.2
      var tail = Path()
      tail.move(to: CGPoint(x: 15 * u, y: 16 * u))
      tail.addQuadCurve(
        to: CGPoint(x: 19 * u, y: 16.2 * u),
        control: CGPoint(x: 17 * u, y: 16.5 * u))
      ctx.stroke(
        tail,
        with: .color(Color.moss),
        style: StrokeStyle(lineWidth: 0.8 * u, lineCap: .round))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

// MARK: - Pulsing modifier

/// Internal wrapper that reads `accessibilityReduceMotion` from the environment
/// and applies the pulse animation only when motion is not restricted.
///
/// Split into a separate struct so the `@Environment` property wrapper can be
/// declared at struct scope — SwiftUI does not allow `@Environment` inside a
/// closure or a generic helper function directly.
private struct PulsingModifier: ViewModifier {

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(pulsing ? 1.06 : 1.0)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(
          // 2.4 s ease-in-out that repeats and auto-reverses (1.0 ↔ 1.06 loop).
          .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
        ) {
          pulsing = true
        }
      }
  }
}

extension View {
  /// Applies a gentle scale pulse (1.0 ↔ 1.06, 2.4 s ease-in-out loop).
  ///
  /// Automatically disabled when `accessibilityReduceMotion` is `true` —
  /// the view stays at scale 1.0 with no animation.
  public func pulsing() -> some View {
    modifier(PulsingModifier())
  }
}

// MARK: - Previews

#Preview("Sizes") {
  HStack(spacing: 24) {
    VStack(spacing: 6) {
      DogMark(size: 26)
      Text("26 pt")
        .font(.caption2)
        .foregroundStyle(Color.muted)
    }
    VStack(spacing: 6) {
      DogMark(size: 44)
      Text("44 pt")
        .font(.caption2)
        .foregroundStyle(Color.muted)
    }
  }
  .padding(24)
  .background(Color.screenBackground)
}

#Preview("Pulsing") {
  DogMark(size: 44)
    .pulsing()
    .padding(40)
    .background(Color.screenBackground)
}
