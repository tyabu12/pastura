/* Pastura LP — fade-up animation runtime.
   Vanilla port of handoff_animations/anim-app.reference.jsx. Drives:
   • .hero-fx entrance on page load via .is-entered on the host
   • .reveal-fx scroll reveal via IntersectionObserver → .is-in
   Honours prefers-reduced-motion (CSS handles the reset; JS skips
   the observer wiring so the final state shows immediately).

   Defensive fallbacks layered for static-page robustness:
   • Missing IntersectionObserver → reveal everything immediately.
   • Stalled script execution → setTimeout safety net (1200ms) so a
     hiccupped CDN can't strand visitors at opacity:0.
   The CSS keeps elements at opacity:0 until JS toggles classes, so
   every path that returns without revealing must call revealAll(). */

(function () {
  "use strict";

  function ready(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    } else {
      fn();
    }
  }

  ready(function () {
    var host = document.querySelector(".anim-host");
    if (!host) return;

    var revealed = false;
    function revealAll() {
      if (revealed) return;
      revealed = true;
      host.classList.add("is-entered");
      var targets = host.querySelectorAll(".reveal-fx");
      for (var i = 0; i < targets.length; i++) {
        targets[i].classList.add("is-in");
      }
    }

    // 1200ms safety net — if anything below throws or the script
    // never reaches the IO wiring, force the final state so the
    // page is at least readable.
    var safetyTimer = setTimeout(revealAll, 1200);

    var prm =
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (prm) {
      clearTimeout(safetyTimer);
      revealAll();
      return;
    }

    // Force a frame so the initial (opacity:0) state paints before
    // .is-entered flips it on — otherwise the transition can miss.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        host.classList.add("is-entered");
      });
    });

    var targets = host.querySelectorAll(".reveal-fx");

    if (!("IntersectionObserver" in window)) {
      // Old browser — graceful degrade: show everything immediately,
      // skip the entrance transition.
      clearTimeout(safetyTimer);
      for (var j = 0; j < targets.length; j++) {
        targets[j].classList.add("is-in");
      }
      return;
    }

    var io = new IntersectionObserver(
      function (entries) {
        for (var k = 0; k < entries.length; k++) {
          if (entries[k].isIntersecting) {
            entries[k].target.classList.add("is-in");
            io.unobserve(entries[k].target);
          }
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.06 }
    );

    // Anything already on screen at mount → reveal without waiting.
    // rootMargin: "0px 0px -8% 0px" biases the observer against
    // already-visible content, so above-the-fold sections must take
    // the immediate path or they never fire.
    var viewportH = window.innerHeight;
    for (var m = 0; m < targets.length; m++) {
      var rect = targets[m].getBoundingClientRect();
      if (rect.top < viewportH * 0.92 && rect.bottom > 0) {
        targets[m].classList.add("is-in");
      } else {
        io.observe(targets[m]);
      }
    }

    // We made it through the wiring successfully — cancel the safety
    // net so we don't double-add classes (no-op but spares the cycles).
    clearTimeout(safetyTimer);
  });
})();
