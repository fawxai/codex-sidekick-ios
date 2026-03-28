# Codex Sidekick iOS

`CodexSidekick` is a native SwiftUI iPhone companion for Codex. It pairs to the
real `codex app-server` websocket interface for live use, with a small
discovery-and-claim bootstrap flow so the phone never has to ingest a raw
bearer token through a QR payload.

## Current slice

- Pair to a local or Tailscale-hosted `codex app-server`
- Browse recent non-archived threads with Codex-style mobile chrome
- Open thread detail and jump to the newest activity
- Resume a live thread and hand off work with `turn/start`
- Review command and file-change approvals from the phone
- Apply Codex-inspired appearance and monochrome UI treatment

## Pairing model

The preferred phone flow is discovery first:

1. discover a host through its discovery URL
2. redeem an 8-character pairing code or a QR deep link that points at that
   host
3. connect to the returned `codex app-server` websocket endpoint

The app still supports direct connection paths when you already know the raw
websocket endpoint:

- `Local`: loopback `ws://` pairing for simulator and same-Mac testing
- `Tailscale`: authenticated tailnet `ws://` pairing with a bearer token
- `Manual`: generic remote pairing, with bearer auth limited to `wss://`

For discovery pairing, the QR/deep link carries only:

- the discovery URL
- the short-lived claim code

It does not carry the bearer token itself.

## Companion plugin

The recommended desktop-side pairing flow lives in the companion repository
`codex-sidekick-plugin`, which prepares a Tailscale-capable `codex app-server`
listener, serves a host discovery document, and issues short-lived claim codes
for the phone.

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
