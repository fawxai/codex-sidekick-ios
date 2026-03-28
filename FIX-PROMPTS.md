# Fix Prompts — codex-sidekick-ios

Reference: https://github.com/fawxai/codex-sidekick-ios/issues/3

---

## Prompt 1: Code Organization Fixes

```
Read ENGINEERING.md, DOCTRINE.md, and TASTE.md first and follow all rules.

Fix the code quality findings from the security review of codex-sidekick-ios.

### Fix 1: Remove or Gate Dead Theme Code (HIGH)
File: CodexSidekick/SidekickTheme.swift

themeDefinition(for:) is ~298 lines and appears unused — makeTheme calls monochromeDefinition, not themeDefinition.

If it's dead code: delete it entirely.
If it's a future feature: wrap it in a clear #if COLORED_THEMES / #endif or move it to a separate file with a comment explaining it's reserved for future use. Prefer deletion — it can be recovered from git.

### Fix 2: Replace String-Typed Banner State (HIGH)
Files: CodexSidekick/App/AppModel.swift, CodexSidekick/Views/ThreadBrowserView.swift

Currently bannerMessage is a String? and tone is derived via string matching:

    if bannerMessage.hasPrefix("Approval waiting") { return .warning }
    if bannerMessage == "Connection closed" || bannerMessage.hasPrefix("Could not") { return .danger }

Fix:
1. Create a BannerState struct (or enum) with message: String and tone: StatusTone fields
2. Replace @Published var bannerMessage: String? with @Published var banner: BannerState? in AppModel
3. Set the tone at the point where the banner is created, not where it's displayed
4. Update all views that read bannerMessage to read banner?.message and banner?.tone
5. Delete the bannerTone computed property and any string-matching tone logic

### Fix 3: Extract Duplicated tone(for: ThreadStatus) (MEDIUM)
Files: ThreadBrowserView.swift, ThreadDetailView.swift, and any other views with inline tone mapping

The same ThreadStatus → StatusTone mapping exists in 3 places.

Fix: Add an extension on ThreadStatus in a shared file (e.g., DisplayPrimitives.swift or a new ThreadStatus+Tone.swift):

    extension ThreadStatus {
        var tone: StatusTone { ... }
    }

Then replace all inline tone(for:) functions with status.tone.

### Fix 4: Add Deep Link Input Length Validation (MEDIUM)
File: CodexSidekick/Infrastructure/PairingLink.swift

PairingLink.parse() accepts arbitrary-length strings for the discovery query parameter.

Fix: In parse(), before processing, check that the full URL string length is <= 2048 characters. Return nil for oversized URLs.

### Fix 5: Decompose Large View Functions (MEDIUM)
Break these into named subview structs:

- ApprovalInboxView.swift: extract approvalCard(_:) (~100 lines) into a standalone ApprovalCard struct
- PairingView.swift: extract tailscaleDiscoverySection (~67 lines) and directConnectionSection (~57 lines) into standalone structs
- SettingsView.swift: extract appearanceControlsCard (~83 lines) into a standalone AppearanceControlsCard struct
- ThreadDetailView.swift: extract handoffComposer (~69 lines) into a HandoffComposerView struct

Each extracted view should be a private struct in the same file, taking only the bindings/data it needs.

### Fix 6: Decompose AppModel.connect() (LOW)
File: CodexSidekick/App/AppModel.swift

connect() is ~61 lines mixing validation, state mutation, and connection setup.

Fix: Extract the validation/precondition checks into a private validateConnectionState() -> ConnectionEndpoint? method. Keep connect() focused on the actual connection sequence.

### Validation
- Build the project: xcodebuild build -project CodexSidekick.xcodeproj -scheme CodexSidekick -destination 'platform=iOS Simulator,name=iPhone 16'
- Verify zero warnings
- Check that the app launches in simulator (if available)

Commit with message: "refactor: fix review findings — dead code, string dispatch, duplication, decomposition"
Push to a branch: fix/ios-review-findings
Open a PR against main on fawxai/codex-sidekick-ios.
```

---

## Prompt 2: Security Hardening (Lower Priority)

```
Read ENGINEERING.md and DOCTRINE.md first and follow all rules.

Apply these security hardening improvements to codex-sidekick-ios.

### Fix 1: Restructure CodexTransport.request() (MEDIUM)
File: CodexSidekick/Infrastructure/CodexTransport.swift

Currently spawns a Task inside withCheckedThrowingContinuation. If the actor is deallocated between continuation storage and Task execution, the continuation could leak.

Fix: Store the continuation first, then await send() directly within the same context, catching and routing errors to failPendingResponse. Eliminate the inner Task spawn.

### Fix 2: Log Unknown ThreadStatus Types in Debug (LOW)
File: wherever ThreadStatus decoding happens

The decoder falls through to .notLoaded for unknown types. This is resilient but masks protocol evolution.

Fix: In the default decoder case, add:

    #if DEBUG
    print("[ThreadStatus] Unknown status type: \(rawType)")
    #endif

### Fix 3: Document ATS Exception Rationale (LOW)
File: Add a comment in ENGINEERING.md or near Info.plist

The NSAllowsLocalNetworking and *.ts.net exceptions are appropriate but undocumented.

Fix: Add a brief section in ENGINEERING.md under a "Network Security" heading explaining why these ATS exceptions exist and what traffic they cover.

### Validation
- Build the project
- Verify zero warnings

Commit with message: "security: harden transport, log unknown status types, document ATS exceptions"
Push to branch: fix/ios-security-hardening
Open a PR against main on fawxai/codex-sidekick-ios.
```
