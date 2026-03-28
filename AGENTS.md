# AGENTS.md — Codex Sidekick iOS

This repository is the native iPhone shell for Codex. It is not the engine, not
the authority, and not a fork of the desktop app. The authority is the host
`codex app-server`; this app is a focused SwiftUI client over that contract.

Read these files in order before making changes:

1. `ENGINEERING.md` for non-negotiable implementation rules
2. `DOCTRINE.md` for runtime and product invariants
3. `TASTE.md` for evolving UX and design preferences

## Scope

- Native SwiftUI iPhone client only
- Pairing, thread browse/detail, handoff, approvals, settings
- No custom side protocol
- No embedded backend/server logic

## Translation from Fawx doctrine

Many Fawx engineering principles apply directly here:

- YAGNI
- DRY
- fail fast
- fix root causes
- dependency minimization
- shell/peripheral thinking

Some Fawx rules do **not** transfer 1:1 because this is not a Rust kernel:

- crate/module policy
- TUI rendering conventions
- kernel immutability implementation details
- orchestrator/subagent runtime design

When a Fawx rule is kernel-specific, translate the intent rather than copying
the mechanism.

## Working rules

- Keep the app aligned to the real `codex app-server` thread/session model.
- Prefer native iOS patterns over Electron/web thinking.
- Do not invent intermediate abstractions just to look “architected.”
- UI-affecting changes must be built and visually checked on simulator.
- Never reintroduce letterboxing or wasted viewport usage.

## Verification

For meaningful changes, run:

```bash
xcodegen generate
xcodebuild \
  -project CodexSidekick.xcodeproj \
  -scheme CodexSidekick \
  -destination 'generic/platform=iOS Simulator' \
  build
```
