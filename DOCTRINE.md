# DOCTRINE.md — Runtime Invariants (Codex Sidekick iOS)

Effective 2026-03-28. This file defines the product and runtime invariants for
the iPhone sidekick.

`ENGINEERING.md` governs how the code is written. `DOCTRINE.md` governs what
this app is allowed to be.

---

## 0. Identity

- This app is a shell, not the engine.
- The host `codex app-server` is the authority for thread, turn, and approval
  state.
- The app is for a single user operating their own Codex environment.

---

## 1. Protocol Boundary

- The app speaks the real app-server JSON-RPC protocol.
- No bespoke mobile protocol.
- No duplicated server business logic in Swift.
- If the host model changes, the client adapts to the host contract rather than
  inventing local truth.

---

## 2. Security Posture

- Non-loopback pairing must be treated as hostile-by-default.
- Private overlay pairing such as Tailscale is the preferred remote path.
- Unauthenticated non-loopback websocket pairing is not acceptable as a product
  default.
- Tailnet pairing requires a bearer token.
- Generic remote bearer auth requires `wss://`.
- Tokens are secrets. They must not be logged, screenshot into docs, or stored
  in plain preferences.

---

## 3. Product Boundaries

- This repo does not become a desktop app clone squeezed into portrait.
- This repo does not embed or fork the backend.
- This repo does not turn into a public remote administration surface.
- This repo does not optimize for multi-tenant or team-shared operation.

---

## 4. UI Contract

- The interface must use the full phone viewport correctly.
- Status color is semantic, not decorative.
- The mobile client should preserve Codex mental models: threads, turns,
  approvals, handoff.
- If a design decision makes the app feel generic instead of Codex-native, it is
  suspect.

---

## 5. Invariants Summary

These must remain true:

1. Host app-server remains the authority.
2. No side protocol is introduced.
3. Remote pairing stays authenticated.
4. Tailscale/private overlay is preferred over public exposure.
5. Secrets are not logged.
6. Full-screen mobile layout is preserved.
