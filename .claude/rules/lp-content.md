---
paths:
  - "web/**"
---

# Pastura LP Content Concepts

The LP lives in the Astro project at `web/src/pages/` (EN `index.astro` at the site root, JA mirror at `web/src/pages/ja/`).

## 1. AIgazing / AI観測 — the genre word

Positioning rests on one coined word: **AIgazing** (EN, AI + stargazing) and **「AI観測」** (JA, echoing 「天体観測」). It lives in two zones only — the **Hero strip** (h1 + meta tags + the adjacent wordplay comment) and the **Bigger picture** coda. Everywhere else uses concrete terms like `on-device` / 「ローカル」; the sandwich is intentional.

The two Hero h1s are **hand-crafted per language, NOT machine-translated** — preserve the wordplay rather than back-translating. The OG card mirrors the genre word into an image via `web/tools/og-card/generate-og.mjs`: edit the generator and re-run, never hand-edit `og-card{,-ja}.png`.

## 2. Voice — em-dash and prose colon

Em-dash (`—`) and the `Feature: explanation` colon-as-prose-separator are the most-cited markers of LLM-generated copy; new LP copy should not pattern-match. Prefer comma / period split / parenthesis over em-dash, and period + new sentence over prose colons.

**Existing em-dashes in legacy LP prose are the LP's signature — keep them.** The rule fires on new additions only. Hyphens (`on-device`) and colons before code blocks or bullet lists are not the same trap. It extends to `README.md` / `CONTRIBUTING.md` additions, which this file does not load for.

## 3. Source mechanics — .astro authoring traps

Three silent divergences between source and rendered output — the build succeeds, the page looks wrong.

- **A wrapped JA sentence becomes a visible mid-sentence space.** A newline + indent inside a Japanese sentence renders as a space (Latin-token spaces are unaffected). Keep every JA sentence on one source line, in any JA `.astro` prose.
- **`{...}` is evaluated as JS even inside `<pre>`.** Pass code through `<Code code={...}>`, which HTML-escapes the prop at build time (`web/src/pages/docs/scenario.astro`).
- **Pin the highlight theme so fences match `<Code>`.** `<Code>` sets `theme="github-light"`, but Markdown fences via `<Content />` inherit Shiki's `github-dark` unless `web/astro.config.mjs` sets `markdown.shikiConfig.theme`. The background is forced to `--page` by `web/public/css/page.css` `.page-prose pre.astro-code`, whose `!important` has consumers outside `/docs/`.

## 4. The sheep SVG ships twice, and nothing guards the pair

The hero figure inlines `<svg class="sheep">` in both locale pages; `web/src/components/SheepAvatar.astro` carries one more for the share landing pages. They are byte-identical apart from `data-tone`, and no page renders both — no build or diff check can catch a divergence.

Geometry source of truth is `Pastura/Pastura/Views/Components/SheepAvatar.swift`; per-tone fills are shared in `web/public/css/base.css` `.sheep[data-tone]`. **Editing the geometry means editing both places.**
