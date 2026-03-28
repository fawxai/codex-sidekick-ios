# ENGINEERING.md — Immutable Doctrine (Codex Sidekick iOS)

Effective 2026-03-28. These rules are the implementation doctrine for this
repository.

For evolving UX judgment and visual preference, see `TASTE.md`.

---

## 0. Core Principles

### YAGNI
Do not build future product surfaces until they are required. This app is a
focused sidekick, not a speculative all-in-one mobile Codex clone.

### DRY
Shared transport, display primitives, and thread formatting live in named
modules. Do not duplicate logic across screens.

### Fail Fast and Loudly
Invalid endpoints, missing tokens, protocol mismatches, and unsupported host
states must surface explicit errors. No silent fallback to insecure or broken
behavior.

### Fix Root Causes, Not Symptoms
If the UI wastes space, fix layout ownership. If pairing is wrong, fix endpoint
classification or auth policy. Do not paper over architectural bugs with
padding, toggles, or special cases.

### Every Dependency Is a Liability
Prefer Apple frameworks and small local code over new packages. Every added
dependency must justify itself.

---

## 1. Repository Structure

```text
CodexSidekick/
├── App/             ← state orchestration and lifecycle
├── Infrastructure/  ← JSON-RPC, transport, persistence, endpoint policy
├── Resources/       ← launch screen and bundled assets
├── Views/           ← SwiftUI screens and shared primitives
└── SidekickTheme.swift
```

Rules:

- No `Utils` dumping ground.
- Shared UI belongs under `Views/Shared/` with a concrete name.
- Shared protocol or transport logic belongs in `Infrastructure/`.
- Remove dead views, stale states, and unused theme tokens in the same change
  that obsoletes them.

---

## 2. SwiftUI Architecture

- The host `codex app-server` is the source of truth.
- `AppModel` owns side effects, lifecycle, and request orchestration.
- Views render state and trigger intent; they do not hide business logic inside
  computed view trees or lifecycle side effects.
- Prefer small, named subviews over giant `body` blocks.
- Prefer explicit data flow over MVVM ceremony. Add a separate view model only
  when it materially improves structure.
- Use `@Observable` and value types deliberately; avoid reference sprawl.
- Prefer `async/await` and structured concurrency.
- No UIKit unless SwiftUI cannot reasonably express the behavior.

---

## 3. Code Quality

- Every function should have a clear single purpose.
- Avoid one-off helpers referenced once; name the block well or extract only
  when reuse/readability earns it.
- Avoid boolean soup and opaque optional parameters.
- Use concrete types for protocol and UI state. No stringly-typed app logic when
  an enum or struct exists.
- Errors must be actionable. If the user cannot fix the state from the message,
  the error is incomplete.
- Keep file size under control. Split large screens before they become
  unreviewable.

---

## 4. UI Verification

- Any user-visible change must be built before completion.
- Significant UI changes should be visually checked on simulator.
- Safe-area handling must be device-agnostic.
- Do not ship screen-specific spacing hacks where a shared layout contract
  should exist.

---

## 5. Networking and Persistence

- Speak the existing app-server JSON-RPC contract. Do not invent a parallel
  live-session API.
- Keep pairing bootstrap small, explicit, and separate from live session logic.
- Endpoint classification and auth policy must live in one obvious place.
- Store secrets in secure storage, not plain defaults.
- Never log bearer tokens or emit them into screenshots or debug copy.

---

## 6. Review Standard

Reject changes that:

- add decorative complexity without product value
- drift from the host thread/session model
- duplicate transport or endpoint logic
- weaken remote pairing security
- make the app feel more generic iOS and less like Codex translated to phone
