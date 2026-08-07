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
/// The default ``size`` is the 9pt `GameHeader` used to apply at its call site.
/// Keeping it here is what stops the two consumers drifting — both take the
/// default rather than each naming a number.
///
/// ⚠️ Resize through ``size``, not an outer `.frame()`. The frame is applied
/// **inside** `body`, so an enclosing one would centre a 9pt leaf in a larger
/// box rather than growing it.
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
