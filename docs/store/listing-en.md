# App Store listing — English (primary locale)

> ASC input values for the `en-US` localization. Character counts are measured
> against ASC limits (Unicode code points; trailing newline excluded).
> This is a **port of the LP voice** (`web/src/pages/index.astro`), not new copy —
> genre word (`AIgazing`) confined to the opening hook and the "bigger picture"
> coda per `.claude/rules/lp-content.md`.
>
> **Final copy review**: a separate Fable session performed the pre-submission
> pass (2026-07-07); the required accuracy fix (scoping on-device claims to
> inference / your data, not "zero cloud calls") and term-alignment fixes are
> applied below. A later copy-polish pass (2026-07-07) applied a `model → LLM`
> term-alignment to the two conceptual references (`local LLMs`, "The LLM lives
> on your phone") to match the Name/Subtitle (`Local LLMs`); the download-artifact
> references ("pick a model", "before the model finishes downloading") stay
> `model` on purpose.

## App name (global, not locale-specific)

```
Pastura - Local LLMs simulator
```

Confirmed globally-unique store Name (`docs/release-setup.md` Part B2). Home-screen name stays `Pastura` (from `CFBundleName`). — 30 chars.

## Subtitle

```
Like stargazing, but for LLMs
```

**29 / 30 chars.** ✓

## Promotional Text

> Editable anytime without review — use for timely notes (new scenarios/models).

```
Watch AI agents reason, negotiate, and bluff, all on your iPhone and fully offline. New scenarios and models land regularly. No account, nothing leaves your device.
```

**164 / 170 chars.** ✓

## Description

> First 2–3 lines are the pre-fold region (most important). Renders as plain
> text in ASC — ALL-CAPS headers + `•` bullets are the plain-text convention.

```
AIgazing. Like stargazing, but for local LLMs.

Pastura is a closed pasture for AI agents, running entirely on your iPhone. You write a scenario. The agents act it out. You step back and watch their speech, their inner voice, their votes and scores arrive in real time.

You can't chat with them, and that's the point. Once you join in, the agents start reacting to you, and the natural exchange between them disappears. Pastura isn't a chat app for talking to an LLM. It's an app for watching LLM agents think.

Everything runs on-device. No account, no sign-up, and none of your data ever leaves your phone. Airplane mode is fine.

WHAT YOU CAN DO
• Run built-in scenarios like Word Wolf or Prisoner's Dilemma
• Write your own in a visual editor, or switch to YAML for full control
• Browse a curated gallery of shared scenarios and import with one tap
• Swap between local LLMs, and see how the same scenario changes
• Watch speech, inner voice, votes, and scores arrive live
• Export any run as Markdown to keep, paste, or share

WHY ON-DEVICE
The LLM lives on your phone, not on someone else's server. That settles privacy, cost, and latency in one move. Inference never touches a server. Zero monthly bill. Zero telemetry, zero analytics. Your scenarios, transcripts, and results never leave the device.

The first time you pick a model, Pastura downloads it once (around 3 GB, Wi-Fi recommended). After that, it's yours and it's offline. While you wait, a built-in demo run plays so you can see what observation looks like before the model finishes downloading.

A BIGGER PICTURE
Stargazing taught us to look up at the stars. AIgazing teaches us to look at the agent. We rarely stop to observe our AI. Pastura is a quiet window into that, on-device, yours alone. Whether it tells you something about them, or about you, is left as a question for the observer.

Requires a device with 6.5 GB of RAM or more (iPhone 15 Pro and newer). Free, with no subscription and no in-app purchases.
```

**1,991 / 4,000 chars.** ✓ — Pre-fold opener: 46 chars (`AIgazing. Like stargazing, but for local LLMs.`).

## Keywords

> Comma-separated, ≤100 chars total. **No spaces after commas** (ASC counts them).
> Excludes words already in Name/Subtitle (`Pastura`, `Local`, `LLMs`, `simulator`,
> `stargazing`) — those are already indexed.

```
AI agents,on-device,offline,multi-agent,roleplay,Gemma,Qwen,private AI,scenario,Word Wolf,observe
```

**97 / 100 chars.** ✓

## URLs

| Field | Value |
|---|---|
| Support URL | `https://pastura.app/support/` |
| Marketing URL | `https://pastura.app/` |
| Privacy Policy URL | `https://pastura.app/legal/privacy-policy/` |

## App-level fields (not locale-specific)

| Field | Value | Source |
|---|---|---|
| Primary category | Developer Tools | this task (2026-07-07); matches `web` jsonLd `DeveloperApplication` |
| Secondary category | Entertainment | this task — picks up the "watching" experience without inviting mismatched-audience reviews. Category is not a one-way door (per-version editable) |
| Age rating | 13+ | ADR-005 §3.2 (16+ pre-planned fallback if a reviewer finds output "more than infrequently" suggestive) |
| Price | Free | no IAP, no subscription |

## Screenshot captions (EN)

> Overlay captions for the shots defined in `screenshot-plan.md`. In-app UI labels
> are `INNER VOICE` / `thought`, so copy uses "inner voice" to match what the
> screenshots show.

| # | Screen | Caption |
|---|---|---|
| 1 | Observation transcript (speech + inner-voice bubbles) | Every word, and the thought behind it |
| 2 | Home — scenario list | A pasture of scenarios to run |
| 3 | Visual scenario editor | Write your own world, no code needed |
| 4 | Vote / score results | Votes, scores, and the reveal |
| 5 | Past Results | Every run, saved to revisit |
