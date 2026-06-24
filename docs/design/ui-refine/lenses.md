# ui-refine — rotating critique lenses

A run uses **exactly one** lens, so each pass goes deep on a single concern
instead of shallow across all of them. The lens is the anti-flood "depth over
breadth" mechanism (mechanism 2 in [README](README.md)).

## Deterministic weekday selection

The lens is chosen by ISO weekday — `date +%u` returns **1 (Mon) … 7 (Sun)** —
indexing directly into the seven lenses below. Seven lenses over seven weekdays
gives a clean 1:1 mapping with **no modulo, no off-by-one, no out-of-range day**,
and every lens runs exactly once per week.

```sh
# In the skill: read today's lens id (1–7).
LENS=$(date +%u)        # 1=Mon … 7=Sun → lens index, no arithmetic needed
```

| `date +%u` | Weekday | Lens |
|:---------:|---------|------|
| 1 | Mon | L1 — Accessibility |
| 2 | Tue | L2 — Information hierarchy & visual weight |
| 3 | Wed | L3 — Cross-screen consistency |
| 4 | Thu | L4 — Motion & feedback |
| 5 | Fri | L5 — Empty / error / edge states |
| 6 | Sat | L6 — Copy & tone |
| 7 | Sun | L7 — Affordance & discoverability |

To run a specific lens regardless of the weekday (e.g. to re-check one concern),
pass it explicitly to the skill instead of reading `date +%u`.

## The lenses

Each lens names the [design-system](../design-system.md) sections it is anchored
to. A proposal under a lens MUST cite at least one of that lens's anchors (or a
named HIG / WCAG guideline) — mechanism 4. Section titles are in Japanese in the
design system; the numbers are stable.

### L1 — Accessibility
Contrast ratios, Dynamic Type behaviour, VoiceOver labels/traits, tap-target
size, Reduce Motion. Ask: would this fail for a low-vision, large-text, or
VoiceOver user?
- Anchors: § 8 アクセシビリティ; § 2.4 Meta Contrast Presets; § 2.9 Dark Mode;
  WCAG SC 1.4.3 / 1.4.4 / 2.5.5.

### L2 — Information hierarchy & visual weight
What the eye lands on first, type scale, spacing rhythm, density. Ask: does the
most important thing on this screen read as the most important?
- Anchors: § 3 タイポグラフィ (esp. § 3.2 スケール); § 4 スペーシング / レイアウト;
  § 2.2 Ink.

### L3 — Cross-screen consistency
The same concept rendered differently across screens; a component used where a
shared one exists; token drift. Ask: does this screen reuse the system, or
reinvent it?
- Anchors: § 9 他画面への展開ガイド; § 5 コンポーネント定義; § 2 カラートークン.

### L4 — Motion & feedback
Transitions, loading/progress affordances, state-change feedback, perceived
latency. Ask: does the UI acknowledge every user action and every wait?
- Anchors: § 6 モーション / アニメーション; § 2.7 Interactive States;
  § 5.5 DL Progress Dots.

### L5 — Empty / error / edge states
First-run/empty inventory, error and failure surfaces, long-content overflow,
truncation, boundary values. Ask: what does this screen look like with zero, or
with way too much?
- Anchors: § 2.6 Alert Family; § 5 コンポーネント定義; § 7 コピーライティング
  (§ 完了画面).

### L6 — Copy & tone
Microcopy voice, terminology consistency, clarity vs. cuteness, button verbs.
Ask: does this copy match the product's voice and say the right thing plainly?
- Anchors: § 7 コピーライティング (§ トーン); § 1 デザイン哲学 (Voice).

### L7 — Affordance & discoverability
Whether tappable things look tappable, whether features are findable, whether
gestures are signalled. Ask: would a first-time user know this is interactive,
and find what they need?
- Anchors: § 2.8 Link / Action; § 5.10 Primary Button; § 5.9 Browse Card;
  § 2.7 Interactive States.

## Adding / reordering lenses

If the catalog ever changes count, the weekday mapping breaks its 1:1 property —
re-derive the selection rule (and update the table above) so it stays total and
in-range for all of `date +%u` 1…7. Keeping it exactly seven is the simplest
invariant.
