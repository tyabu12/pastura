---
paths:
  - "pages/**"
---

# Pastura LP Content Concepts

The LP at `pages/` (EN at root, JA mirror at `pages/ja/`) is largely settled. Two concepts to preserve when editing.

## 1. AIgazing / AI観測 — the genre word

Pastura's positioning rests on a single coined word: **AIgazing** (EN, AI + stargazing) and **「AI観測」** (JA, coined to echo 「天体観測」).

The word lives in two zones only:

- **Hero strip** — h1 + meta tags + adjacent HTML comment documenting the cross-locale wordplay
- **Bigger picture** coda — eyebrow + h2 between Why on-device and FAQ

Everywhere else (Capabilities cards, FAQ, footer, Why on-device body) uses concrete terms like `on-device` / 「ローカル」. The thought → concrete → thought sandwich is intentional.

The two Hero h1s are **hand-crafted per language**, NOT machine-translated. Preserve the wordplay rather than back-translating.

See #358 (EN rebrand) / #374 (JA mirror) for the design discussion.

## 2. Voice — em-dash and prose colon

Em-dash (`—`) and `Feature: explanation` colon-as-prose-separator are the most-cited markers of LLM-generated copy in 2025–2026. NEW LP copy should not pattern-match.

- **Existing em-dashes in legacy LP prose are the LP's stylistic signature — keep them.** The rule fires on new additions only.
- For new content, prefer comma / period split / parenthesis over em-dash, and period + new sentence over prose colons.
- Hyphens (`on-device`, `non-trivial`) and colons before code blocks / bullet lists are not the same trap.

The same voice rule extends to `README.md` / `CONTRIBUTING.md` additions, but this rule auto-loads on LP edits only — apply by writer judgement when editing project-root public docs.
