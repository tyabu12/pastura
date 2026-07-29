# docs/design/ds/ — Claude Design component library

HTML preview cards mirroring `docs/design/design-system.md`, synced to
the claude.ai/design project **"Pastura Design System"** for design
exploration: generate screen/component variations there, then feed
accepted decisions back into design-system.md and SwiftUI.

## Source-of-truth layering

1. **`docs/design/design-system.md`** — authoritative for tokens,
   components, motion, and copy norms.
2. **`ds/` (this directory)** — its visual mirror. Never invent values
   here; change the doc first.
3. **`Pastura/Pastura/Views/DesignTokens*.swift`** — the shipped
   implementation of the same tokens.

**Exception — avatar palette (§2.5), light half only:** the origin of the
**light** values is `docs/design/demo-replay-reference.html`'s `sheepAvatar()`
function. design-system.md and `ds/` both mirror it.

The **dark** values have no origin there — that prototype is light-only — so
they follow the normal layering: design-system.md §2.9 is authoritative and
`ds/colors-avatar-dark.html` is its mirror (ADR-028 gate 1 slice 3).

Note the prototype and the app have already diverged in what they *draw*:
`sheepAvatar()` emits body, face, eyes and horns; `SheepAvatar.swift` draws
those plus a highlight dot, and neither draws the ear or nose the tokens
describe. The exception is about **values**, not about the drawing.

## Drift guard

`scripts/check_design_tokens_css.py --check` (CI job
`design-tokens-drift`) asserts every color literal in
`DesignTokens*.swift` — both `hex: 0xRRGGBB` and rgba-constructor
forms — appears in `tokens.css`, and that every `ds/*.html` first line
carries a `@dsCard` marker. Token additions in Swift therefore fail CI
until mirrored here. The cards' *layout* (inline CSS) is not guarded —
review visually.

## File conventions

- `tokens.css` — design tokens only (custom properties + the §3.2 type
  utility classes). `card.css` — shared card chrome, no tokens.
- One card per HTML file. First line MUST be
  `<!-- @dsCard group="..." name="..." subtitle="..." -->` — the
  Design System pane builds its card index from this marker.
- Groups in use: `Colors`, `Type`, `Spacing`, `Components`, `Motion`,
  `Brand` (aligned with design-system.md section naming).
- Cards are self-contained: Google Fonts links + relative
  `tokens.css` / `card.css` links; component-local layout stays in the
  card's inline `<style>`.
- Capture names and copy follow the §1/§7 voice (no celebratory tone,
  no emoji).

## Syncing to claude.ai/design

Push via the `DesignSync` tool from a Claude Code session (project
"Pastura Design System"):

1. `list_projects` → confirm the target projectId.
2. `finalize_plan` with `localDir` = this directory and the exact file
   list (writes/deletes).
3. `write_files` with `localPath` entries for every card + both CSS
   files.

Sync after merge (main is the canonical state), or push a single card
mid-PR to validate a new card shape. The remote project is a mirror of
this directory — treat repo state as the source when they diverge.

## Verifying a card locally

```bash
python3 scripts/check_design_tokens_css.py --check
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --screenshot=/tmp/card.png --window-size=1500,1100 \
  --hide-scrollbars "file://$PWD/docs/design/ds/<card>.html"
```

Use a window wider than 2x the card's 720px max-width — headless
Chrome silently clips horizontal overflow at the window edge.
