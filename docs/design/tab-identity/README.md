# Tab identity — Home / Search / Past Results differentiation

Design source-of-truth for the **tab-identity** redesign (issue #767). The
Home (牧場), Search (さがす), and Past Results (過去の結果) tab roots share
~70–80% of their layout — the same `PasturaCard(.grouped)` + `PasturaRowDivider`
row anatomy, deliberately unified across browse tabs in #684. The shared shape
is correct as component reuse, but it makes "which tab am I on?" hard to read at
a glance, especially mid-scroll where the editorial header is gone.

The fix keeps the shared **tokens** (respecting #684) and instead diverges each
tab's **layout shape** + header identity — colour-theming is not an option since
moss is Pastura's only brand colour (design-system § 2.3). Direction chosen:
**案C 中庸** — distinct row silhouette per tab, not a full grid/redesign.

| Tab | Shape | "answers the question" |
|-----|-------|------------------------|
| ホーム | editorial — resume hero + compact icon rows | "what do I do next?" |
| さがす | catalog — landscape cards with a leading art tile | "what's available?" |
| 過去の結果 | timeline — rail + day headers + nodes | "what have I done?" |

## Files

| File | Content |
|------|---------|
| `lookbook.html` | 390×844 phone frames, rows = tabs, columns = 現状 / 案C 中庸 (chosen) / 案B 大胆. The approved visual target. |

Open `lookbook.html` in a browser for the full-size comparison, or render a PNG
via headless Chrome:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --hide-scrollbars \
  --screenshot=docs/design/tab-identity/lookbook.png \
  --window-size=1310,3220 --force-device-scale-factor=1.5 \
  docs/design/tab-identity/lookbook.html
```

The rendered PNG is a derived artifact — not committed.

## Rollout — 3 PRs (lowest-risk first)

1. **PR1 — 過去の結果 timeline** (#767). Presentation-only; the
   `ResultsViewModel` date-bucket grouping is unchanged. Aggregate root only;
   the pushed per-scenario detail keeps the grouped list. **Shipped deviation
   from the mock:** the editorial big-title header (eyebrow + large "Past
   Results") was dropped after on-device review — the always-on `.searchable`
   drawer rendered above it, inverting the title→search order. The shipped
   timeline keeps the familiar inline nav title + "N records" subtitle; its tab
   identity comes from the rail/node shape alone.
2. **PR2 — さがす catalog cards** (planned).
3. **PR3 — ホーム hero + compact rows** (planned). After PR3, revisit whether
   `ScenarioSummaryRow` (shared by Home + Search today) can be retired.
