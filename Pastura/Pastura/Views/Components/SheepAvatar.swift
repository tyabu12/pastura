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
  public var size: CGFloat = 48

  public var body: some View {
    Canvas { ctx, canvasSize in
      // All geometry is expressed as fractions of the 28-unit SVG viewBox.
      // Multiplying by `unit` maps viewBox coordinates to canvas points.
      let unit = canvasSize.width / 28

      // --- Wool body (five circles forming a cloud silhouette) ---
      let bodyColor = character.bodyColor
      let woolCircles: [WoolCircle] = [
        WoolCircle(centerX: 14, centerY: 15, radius: 8),
        WoolCircle(centerX: 9, centerY: 13, radius: 3.2),
        WoolCircle(centerX: 19, centerY: 13, radius: 3.2),
        WoolCircle(centerX: 11, centerY: 18, radius: 3),
        WoolCircle(centerX: 17, centerY: 18, radius: 3)
      ]
      for circle in woolCircles {
        let path = Path(
          ellipseIn: CGRect(
            x: (circle.centerX - circle.radius) * unit,
            y: (circle.centerY - circle.radius) * unit,
            width: circle.radius * 2 * unit,
            height: circle.radius * 2 * unit))
        ctx.fill(path, with: .color(bodyColor))
      }

      // --- Face oval (character-specific darker shade) ---
      let facePath = Path(
        ellipseIn: CGRect(
          x: (14 - 4) * unit, y: (15.5 - 4.2) * unit,
          width: 8 * unit, height: 8.4 * unit))
      ctx.fill(facePath, with: .color(character.faceColor))

      // --- Eyes (two dark circles) ---
      let eyeColor = Color.avatarEye
      for eyeCenterX in [CGFloat(12.6), 15.4] {
        let eyePath = Path(
          ellipseIn: CGRect(
            x: (eyeCenterX - 0.7) * unit, y: (14.8 - 0.7) * unit,
            width: 1.4 * unit, height: 1.4 * unit))
        ctx.fill(eyePath, with: .color(eyeColor))
      }

      // --- Highlight dot (top-left of face; adds cartoon sheen) ---
      let highlightPath = Path(
        ellipseIn: CGRect(
          x: (11.6 - 0.5) * unit, y: (13.5 - 0.5) * unit,
          width: 1.0 * unit, height: 1.0 * unit))
      ctx.fill(highlightPath, with: .color(Color.avatarHighlight))

      // --- Horns (two short curved strokes) ---
      let hornColor = character.hornColor
      var leftHorn = Path()
      leftHorn.move(to: CGPoint(x: 10.5 * unit, y: 11.5 * unit))
      leftHorn.addQuadCurve(
        to: CGPoint(x: 11 * unit, y: 9.5 * unit),
        control: CGPoint(x: 10 * unit, y: 10 * unit))
      ctx.stroke(
        leftHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: unit, lineCap: .round))

      var rightHorn = Path()
      rightHorn.move(to: CGPoint(x: 17.5 * unit, y: 11.5 * unit))
      rightHorn.addQuadCurve(
        to: CGPoint(x: 17 * unit, y: 9.5 * unit),
        control: CGPoint(x: 18 * unit, y: 10 * unit))
      ctx.stroke(
        rightHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: unit, lineCap: .round))
    }
    .frame(width: size, height: size)
    .accessibilityLabel(character.accessibilityLabel)
  }

  private struct WoolCircle {
    let centerX: CGFloat
    let centerY: CGFloat
    let radius: CGFloat
  }
}

// MARK: - Character helpers

extension SheepAvatar.Character {

  /// Resolves an agent name to a ``SheepAvatar/Character`` for avatar
  /// rendering. Returns the matching canonical character (case-insensitive,
  /// trimmed) for the four demo-replay names (`Alice` / `Bob` / `Carol` /
  /// `Dave`); for any other name, falls back to a deterministic bucket via
  /// a UTF-8 byte-sum modulo the character count.
  ///
  /// ## Determinism contract
  ///
  /// Same input → same character, across runs and processes. The fallback
  /// hash is intentionally weak (collisions are acceptable) — agents that
  /// share a bucket simply share an avatar color, which is visually
  /// indistinguishable from other reasonable assignment schemes.
  ///
  /// Normalization (trim + lowercase) runs *before* both the direct match
  /// and the byte-sum. Inputs like `"Alice "` and `"ALICE"` map to the
  /// same character as `"alice"`; `"User1"` and `"user1"` land in the
  /// same fallback bucket.
  ///
  /// Why NOT `String.hashValue`: Swift randomizes hash seeds per process,
  /// so the same name would map to different buckets across launches —
  /// that would let agents' avatar colors flicker between app runs.
  public static func forAgent(_ name: String) -> SheepAvatar.Character {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "alice": return .alice
    case "bob": return .bob
    case "carol": return .carol
    case "dave": return .dave
    default:
      let sum = normalized.utf8.reduce(0) { $0 &+ Int($1) }
      let cases = SheepAvatar.Character.allCases
      return cases[sum % cases.count]
    }
  }

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
