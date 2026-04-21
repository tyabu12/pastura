import SwiftUI

/// A sheep-head avatar used in the demo replay chat rows and simulation view.
///
/// Rendered as pure SwiftUI shapes — no image assets — so it scales cleanly
/// to any ``size`` and costs nothing at bundle time.
///
/// ```swift
/// SheepAvatar(character: .alice)               // 42 pt default
/// SheepAvatar(character: .dave, size: 32)      // smaller variant
/// ```
public struct SheepAvatar: View {

  /// The four named sheep characters, each with a distinct wool color.
  public enum Character: CaseIterable {
    /// Alice — cream wool. Gentle first voice.
    case alice
    /// Bob — sage wool. Agreeable / calm.
    case bob
    /// Carol — pink wool. Observer.
    case carol
    /// Dave — slate wool. Wolf / central figure.
    case dave
  }

  public let character: Character
  public var size: CGFloat = 42

  public var body: some View {
    Canvas { ctx, canvasSize in
      let s = canvasSize.width
      // All geometry is expressed as fractions of the 28-unit SVG viewBox.
      // Multiplying by (s / 28) maps viewBox coordinates to canvas points.
      let u = s / 28

      // --- Wool body (five circles forming a cloud silhouette) ---
      let bodyColor = character.bodyColor
      let woolCircles: [(CGFloat, CGFloat, CGFloat)] = [
        (14, 15, 8),
        (9, 13, 3.2),
        (19, 13, 3.2),
        (11, 18, 3),
        (17, 18, 3)
      ]
      for (cx, cy, r) in woolCircles {
        var path = Path(
          ellipseIn: CGRect(
            x: (cx - r) * u, y: (cy - r) * u,
            width: r * 2 * u, height: r * 2 * u))
        ctx.fill(path, with: .color(bodyColor))
        // Prevent canvas from reusing path variable across iterations.
        path = Path()
        _ = path
      }

      // --- Face oval (character-specific darker shade) ---
      let facePath = Path(
        ellipseIn: CGRect(
          x: (14 - 4) * u, y: (15.5 - 4.2) * u,
          width: 8 * u, height: 8.4 * u))
      ctx.fill(facePath, with: .color(character.faceColor))

      // --- Eyes (two dark circles) ---
      let eyeColor = Color.avatarEye
      for cx in [CGFloat(12.6), 15.4] {
        let eyePath = Path(
          ellipseIn: CGRect(
            x: (cx - 0.7) * u, y: (14.8 - 0.7) * u,
            width: 1.4 * u, height: 1.4 * u))
        ctx.fill(eyePath, with: .color(eyeColor))
      }

      // --- Highlight dot (top-left of face; adds cartoon sheen) ---
      let highlightPath = Path(
        ellipseIn: CGRect(
          x: (11.6 - 0.5) * u, y: (13.5 - 0.5) * u,
          width: 1.0 * u, height: 1.0 * u))
      ctx.fill(highlightPath, with: .color(Color.avatarHighlight))

      // --- Horns (two short curved strokes) ---
      let hornColor = character.hornColor
      var leftHorn = Path()
      leftHorn.move(to: CGPoint(x: 10.5 * u, y: 11.5 * u))
      leftHorn.addQuadCurve(
        to: CGPoint(x: 11 * u, y: 9.5 * u),
        control: CGPoint(x: 10 * u, y: 10 * u))
      ctx.stroke(
        leftHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: u, lineCap: .round))

      var rightHorn = Path()
      rightHorn.move(to: CGPoint(x: 17.5 * u, y: 11.5 * u))
      rightHorn.addQuadCurve(
        to: CGPoint(x: 17 * u, y: 9.5 * u),
        control: CGPoint(x: 18 * u, y: 10 * u))
      ctx.stroke(
        rightHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: u, lineCap: .round))
    }
    .frame(width: size, height: size)
    .accessibilityLabel(character.accessibilityLabel)
  }
}

// MARK: - Character helpers

extension SheepAvatar.Character {

  /// Wool / body fill — matches the per-character `avatarAlice/Bob/Carol/Dave` token.
  var bodyColor: Color {
    switch self {
    case .alice: return Color.avatarAlice
    case .bob: return Color.avatarBob
    case .carol: return Color.avatarCarol
    case .dave: return Color.avatarDave
    }
  }

  /// Face oval fill — a darker accent derived from the HTML reference.
  /// No dedicated token exists for these; the values mirror the reference
  /// prototype's `sheepAvatar()` color map.
  var faceColor: Color {
    switch self {
    case .alice:
      return Color(.sRGB, red: 0xC9 / 255.0, green: 0xA9 / 255.0, blue: 0x79 / 255.0, opacity: 1)
    case .bob:
      return Color(.sRGB, red: 0x8A / 255.0, green: 0x9A / 255.0, blue: 0x6C / 255.0, opacity: 1)
    case .carol:
      return Color(.sRGB, red: 0xB8 / 255.0, green: 0x87 / 255.0, blue: 0x7C / 255.0, opacity: 1)
    case .dave:
      return Color(.sRGB, red: 0x6B / 255.0, green: 0x68 / 255.0, blue: 0x58 / 255.0, opacity: 1)
    }
  }

  /// Horn stroke color — darker shade of the body; mirrors reference prototype.
  var hornColor: Color {
    switch self {
    case .alice:
      return Color(.sRGB, red: 0xB2 / 255.0, green: 0x93 / 255.0, blue: 0x64 / 255.0, opacity: 1)
    case .bob:
      return Color(.sRGB, red: 0x6F / 255.0, green: 0x7F / 255.0, blue: 0x54 / 255.0, opacity: 1)
    case .carol:
      return Color(.sRGB, red: 0x9C / 255.0, green: 0x6E / 255.0, blue: 0x64 / 255.0, opacity: 1)
    case .dave:
      return Color(.sRGB, red: 0x4F / 255.0, green: 0x4C / 255.0, blue: 0x3F / 255.0, opacity: 1)
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .alice: return "Alice"
    case .bob: return "Bob"
    case .carol: return "Carol"
    case .dave: return "Dave"
    }
  }
}

// MARK: - Previews

#Preview("All characters") {
  HStack(spacing: 16) {
    ForEach(SheepAvatar.Character.allCases, id: \.accessibilityLabel) { character in
      VStack(spacing: 4) {
        SheepAvatar(character: character)
        Text(character.accessibilityLabel)
          .textStyle(Typography.captionName)
          .foregroundStyle(Color.inkSecondary)
      }
    }
  }
  .padding()
  .background(Color.screenBackground)
}

#Preview("Multiple sizes") {
  HStack(spacing: 20) {
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 32)
      Text("32").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 42)
      Text("42").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 56)
      Text("56").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
  }
  .padding()
  .background(Color.screenBackground)
}
