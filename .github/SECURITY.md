# Security Policy

Thank you for helping keep Pastura and its users safe. This document
explains how to report a vulnerability and what to expect once you do.

## Reporting a Vulnerability

Please report security issues **privately** via GitHub's Private
Vulnerability Reporting:

[**Report a vulnerability**](https://github.com/tyabu12/pastura/security/advisories/new)

Do not open a public issue, pull request, or discussion thread for
suspected vulnerabilities. Public reports give attackers time to exploit
the issue before a fix is available.

If GitHub PVR is unavailable to you, contact the maintainer at
`tyabu1212@gmail.com` with a subject line beginning `[Pastura security]`.

### What to include

A good report contains, at a minimum:

1. A short description of the issue and its security impact.
2. The Pastura commit SHA (or release tag) on which the issue reproduces.
3. Steps to reproduce, including any required scenario YAML, model
   selection, or device configuration.
4. Your proposed severity (informational / low / medium / high / critical)
   and a one-line rationale.
5. Any proof-of-concept output you are willing to share. Do NOT include
   third-party user data.

## What to Expect

Pastura is maintained by a single developer outside of business hours. The
following targets are realistic upper bounds, not service-level
guarantees.

| Phase | Target |
|-------|--------|
| Acknowledgment of the report | 7 days |
| Initial triage and severity assessment | 14 days |
| Fix proposal (or out-of-scope decision) | 30 days |
| Public disclosure after fix lands | 90 days from triage, or sooner if you prefer |

We follow coordinated disclosure. If you intend to publish your findings,
let us know your planned date so we can align the fix release.

## Supported Versions

Pastura is pre-release. Only the latest commit on the `main` branch is
maintained. Earlier commits, branches, forks, and any sideloaded build
older than the current `main` are out of support. Pastura is not yet
distributed via TestFlight or the App Store.

| Version | Supported |
|---------|-----------|
| `main` (latest) | Yes |
| Older commits / branches / forks / sideloaded builds | No |

Once Pastura ships its first tagged release, this table will track at
least the current minor release.

## Scope

### In scope

* Pastura iOS source code (`Pastura/Pastura/**`).
* CI and build infrastructure (`.github/workflows/**`, `scripts/**`).
* Public web pages (`pages/**`) served from `pastura.app`.
* Scenario engine logic and the LLM inference layer's invocation of
  third-party libraries (Yams, GRDB, llama.cpp via mattt/llama.swift).

### Out of scope

* Vulnerabilities in third-party dependencies themselves. Please report
  those to the upstream project (Yams, GRDB.swift, llama.cpp,
  mattt/llama.swift). Pastura will update its pinned versions once an
  upstream fix is released.
* Issues that require physical device access or a jailbroken device.
* Bugs in the iOS operating system or Apple frameworks.
* Denial-of-service via maliciously crafted scenario YAML supplied by the
  device user to their own device. Scenario YAML executes only with the
  user's explicit action, on-device, with no network exfiltration path.
* Social-engineering, phishing, or reports that require the attacker to
  already have the device unlocked.

## Pastura's Security Posture (for context)

Knowing how Pastura is built may help you assess impact:

* Pastura runs entirely on the user's device. Scenarios, prompts, agent
  outputs, and inference all stay local.
* Pastura ships no analytics, no telemetry, no crash reporters, no
  advertising or attribution SDKs. The only network activity is the
  one-time model download from publicly listed URLs (see
  `App/ModelRegistry.swift`).
* Pastura has no user accounts and no authentication. There is no server
  component to compromise.
* See `docs/decisions/ADR-005.md` for content-safety architecture and
  `pages/legal/privacy-policy/` for the public privacy policy.

## Acknowledgments

Reporters who follow this policy and request credit will be acknowledged
in the security advisory that lands the fix.
