# Home redesign — D3 mocks

Visual referents for the bottom-tab Home redesign (see
[ADR-016](../../decisions/ADR-016.md)). Confirmed 2026-06-14 after
HTML → headless-Chrome iteration on the
[design system](../design-system.md).

These are **static HTML mocks**, not production SwiftUI. They fix the
target layout and the 4-tab information architecture so the multi-phase
implementation (P0–P6) has a single source of truth for "what it should
look like."

## Files

| File | Screen |
|------|--------|
| `d3-with.html` | 牧場 (Home) tab — with a resumable (中断中) simulation card |
| `d3-without.html` | 牧場 (Home) tab — no resumable simulation (枠ごと非表示) |
| `tab-search.html` | さがす (shared-scenario search) tab |
| `tab-history.html` | 観察履歴 (history) tab |
| `tab-settings.html` | 設定 (settings) tab |
| `app-icon.png` | App icon asset embedded by `d3-with/without.html` (`src="app-icon.png"`) — a real binary dependency, not regenerable |

The frame is a 390×844 pt iPhone viewport.

## PNG regeneration

The rendered PNGs are intentionally **not** committed — they are derived
artifacts. Regenerate any of them from the HTML when you need a raster
preview (run from the repo root — input and output are both
repo-root-relative):

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless \
  --screenshot=docs/design/home-redesign/d3-with.png \
  --window-size=390,844 --force-device-scale-factor=2 \
  docs/design/home-redesign/d3-with.html
```

The mock frame is a fixed 390 pt width, so headless-Chrome horizontal
overflow clipping does not apply here.
