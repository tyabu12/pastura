import SwiftUI

/// The small half-circle leaf accent that marks a Pastura "run" surface.
///
/// Visual translation of `header_reference.html`'s `.gh-leaf`
/// (border-radius 50%/0 + rotate 45°) using SwiftUI's trim-on-`Circle`
/// approximation.
///
/// It leads ``GameHeader``'s title row on the live simulation and the DL-time
/// demo, so it reads as "this is a run in progress". The gallery highlight's
/// run figure borrows it for the same reason — the excerpt is a real run, just
/// a finished and quoted one — which is why the shape moved out of
/// `GameHeader`'s private scope rather than being copied.
///
/// The default ``size`` is the 9pt `GameHeader` has always applied at its call
/// site; it lives here now so the two consumers cannot drift apart.
struct LeafIcon: View {
  var size: CGFloat = 9

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.5)
      .fill(Color.moss.opacity(0.75))
      .rotationEffect(.degrees(45))
      .frame(width: size, height: size)
  }
}
