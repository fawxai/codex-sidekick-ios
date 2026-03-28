# Codex Sidekick iOS

`CodexSidekick` is a native SwiftUI iPhone companion for Codex. It pairs to the
real `codex app-server` websocket interface instead of inventing a side
protocol, so the app stays aligned with the thread/session model used by rich
Codex clients.

## Current slice

- Pair to a local or Tailscale-hosted `codex app-server`
- Browse recent non-archived threads with Codex-style mobile chrome
- Open thread detail and jump to the newest activity
- Resume a live thread and hand off work with `turn/start`
- Review command and file-change approvals from the phone
- Apply Codex-inspired appearance and monochrome UI treatment

## Pairing model

The app currently supports three connection paths:

- `Local`: loopback `ws://` pairing for simulator and same-Mac testing
- `Tailscale`: authenticated tailnet `ws://` pairing with a bearer token
- `Manual`: generic remote pairing, with bearer auth limited to `wss://`

Tailscale pairing uses the host's `.ts.net` name or Tailscale IP and requires a
bearer token from the host.

## Companion plugin

The recommended desktop-side pairing flow lives in the companion repository
`codex-sidekick-plugin`, which prepares a Tailscale-capable `codex app-server`
listener and emits a ready-to-enter pairing payload for the phone.

## Build

Generate the Xcode project:

```bash
xcodegen generate
```

Build for the simulator:

```bash
xcodebuild \
  -project CodexSidekick.xcodeproj \
  -scheme CodexSidekick \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Attribution

This project is an Apache-2.0 derivative that builds on OpenAI Codex protocol
and UX concepts while implementing a separate native iOS client.
