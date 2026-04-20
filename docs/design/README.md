# docs/design/

Visual/UX design artefacts — design tokens, per-screen visual references, and
design briefs or prompts that inform but do not bind engineering.

**Boundary with sibling directories:**

- `docs/specs/` — binding product/engineering contracts (data formats,
  component design, Go/No-Go criteria). Answers *what the code must do*.
- `docs/decisions/` — ADRs. Answers *why we chose this approach*.
- `docs/design/` (this dir) — visual/UX artefacts. Answers *how it should
  look and feel*.

Each file carries a `Status` header indicating its binding level (draft,
exploration, ship-aligned). A design artefact that describes behaviour or
state must defer to the relevant spec or ADR.
