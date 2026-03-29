import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    enum PendingApprovalKind: Sendable {
        case command(CommandExecutionRequestApprovalParams)
        case fileChange(FileChangeRequestApprovalParams)
    }

    struct PendingApproval: Identifiable, Sendable {
        let id: String
        let requestID: RPCID
        let threadID: String
        let turnID: String
        let itemID: String
        let kind: PendingApprovalKind

        var title: String {
            switch kind {
            case .command(let params):
                if let command = params.command, !command.isEmpty {
                    return command
                }
                if let networkContext = params.networkApprovalContext {
                    return "Allow \(networkContext.protocol.uppercased()) access to \(networkContext.host)"
                }
                return "Command approval requested"
            case .fileChange:
                return "File changes need approval"
            }
        }

        var subtitle: String {
            switch kind {
            case .command(let params):
                if let reason = params.reason, !reason.isEmpty {
                    return reason
                }
                if let cwd = params.cwd, !cwd.isEmpty {
                    return cwd
                }
                return "Codex is waiting to run a higher-risk command."
            case .fileChange(let params):
                if let reason = params.reason, !reason.isEmpty {
                    return reason
                }
                if let root = params.grantRoot, !root.isEmpty {
                    return "Write access requested for \(root)"
                }
                return "Codex wants to apply file edits."
            }
        }
    }

    private struct ConnectionEndpoint: Sendable {
        let draft: ConnectionDraft
        let websocketURL: String
        let authToken: String
    }

    var connectionDraft = ConnectionDraft() {
        didSet {
            guard connectionDraft.normalizedWebsocketURL != oldValue.normalizedWebsocketURL
                    || connectionDraft.normalizedAuthToken != oldValue.normalizedAuthToken else {
                return
            }
            clearRetryState(resetDiscoveredHost: false, resetPairingCode: false)
        }
    }
    var discoveryInput = "" {
        didSet {
            guard discoveryInput != oldValue else {
                return
            }
            clearRetryState(resetDiscoveredHost: true, resetPairingCode: true)
        }
    }
    var pairingCodeInput = "" {
        didSet {
            guard pairingCodeInput != oldValue else {
                return
            }
            pairingErrorMessage = nil
            if case .failed = connectionState {
                connectionState = .disconnected
            }
        }
    }
    struct ThreadListContext: Sendable {
        var sortKey: ThreadSortKey = .updatedAt
        var cwd: String?
    }

    enum PermissionPreset: Equatable, Sendable {
        case defaultPermissions
        case fullAccess
        case customConfig

        var label: String {
            switch self {
            case .defaultPermissions:
                return "Default permissions"
            case .fullAccess:
                return "Full access"
            case .customConfig:
                return "Custom"
            }
        }
    }

    static let planModePrompt =
        "Plan mode is enabled. Start with a concise step-by-step plan before taking action."
    var discoveredHost: PairingDiscoveryRecord?
    var pairedConnection: StoredPairing?
    var connectionState: ConnectionState = .disconnected
    var initializeResponse: InitializeResponse?
    var threads: [CodexThread] = []
    var selectedThreadID: String?
    var threadDetails: [String: CodexThread] = [:]
    var handoffDraft = ""
    var pendingApprovals: [PendingApproval] = []
    var appearanceSettings = SidekickAppearanceSettings()
    var hostAppearance = HostAppearanceSnapshot(themeName: nil)
    var hostModelName: String?
    var hostModelProviderName: String?
    var hostReasoningEffortName: String?
    var hostSandboxModeName: String?
    var hostApprovalPolicyValue: JSONValue?
    var accountRateLimits: RateLimitSnapshot?
    var threadTokenUsageByThreadID: [String: ThreadTokenUsage] = [:]
    var isBootstrapping = false
    var isDiscoveringHost = false
    var isClaimingPairing = false
    var banner: BannerState?
    var pairingErrorMessage: String?

    private let pairingStore = PairingStore()
    private let pairingBrokerClient = PairingBrokerClient()
    private let appearanceStore = AppearanceStore()
    private var transport: CodexTransport?
    private var eventTask: Task<Void, Never>?
    private var threadListContext = ThreadListContext()

    var hasSavedPairing: Bool {
        pairedConnection != nil
    }

    var isConnecting: Bool {
        connectionState == .connecting
    }

    var isBusyPairing: Bool {
        isConnecting || isDiscoveringHost || isClaimingPairing
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    var connectionErrorMessage: String? {
        if case .failed(let message) = connectionState {
            return message
        }
        return nil
    }

    var connectionEndpointKind: SidekickConnectionEndpointKind {
        connectionDraft.endpointKind
    }

    var selectedThread: CodexThread? {
        guard let selectedThreadID else {
            return nil
        }
        return threadDetails[selectedThreadID] ?? threads.first(where: { $0.id == selectedThreadID })
    }

    var pairedHostLabel: String {
        guard let pairedConnection,
              let host = URL(string: pairedConnection.websocketURL)?.host,
              !host.isEmpty else {
            return pairedConnection?.websocketURL ?? "Unpaired"
        }
        return host
    }

    var hostPermissionPreset: PermissionPreset {
        let normalizedSandboxMode = hostSandboxModeName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let approvalPolicyValue = hostApprovalPolicyValue

        if normalizedSandboxMode == nil, approvalPolicyValue == nil {
            return .defaultPermissions
        }

        if normalizedSandboxMode == "danger-full-access",
           approvalPolicyValue?.stringValue?.lowercased() == "never" {
            return .fullAccess
        }

        return .customConfig
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        if let storedAppearance = appearanceStore.load() {
            appearanceSettings = storedAppearance
        }

        guard let restored = pairingStore.load() else {
            return
        }

        connectionDraft = ConnectionDraft(
            websocketURL: restored.stored.websocketURL,
            authToken: restored.token ?? ""
        )
        discoveryInput = restored.stored.suggestedDiscoveryTarget

        if restored.stored.endpointKind == .local {
            try? pairingStore.clear()
            return
        }

        pairedConnection = restored.stored
        await connect()
    }

    func connect() async {
        guard let endpoint = validateConnectionState() else {
            return
        }

        await disconnectTransport()
        connectionState = .connecting
        banner = nil
        pairingErrorMessage = nil

        do {
            let transport = CodexTransport()
            let (initializeResponse, eventStream) = try await transport.connect(
                websocketURL: endpoint.websocketURL,
                authToken: endpoint.authToken.isEmpty ? nil : endpoint.authToken,
                clientName: "codex_sidekick_ios",
                clientTitle: "Codex Sidekick iOS",
                clientVersion: "0.1.0"
            )

            self.transport = transport
            self.initializeResponse = initializeResponse
            self.pairedConnection = try pairingStore.save(endpoint.draft)
            self.connectionState = .connected
            startListening(to: eventStream)
            await refreshThreads()
            await refreshHostConfigSnapshot()
            await refreshAccountRateLimits()
        } catch {
            self.connectionState = .failed(error.localizedDescription)
        }
    }

    private func validateConnectionState() -> ConnectionEndpoint? {
        let draft = connectionDraft
        let websocketURL = draft.normalizedWebsocketURL
        let authToken = draft.normalizedAuthToken

        guard !websocketURL.isEmpty else {
            connectionState = .failed("Enter a websocket URL for `codex app-server`.")
            return nil
        }

        guard let url = URL(string: websocketURL) else {
            connectionState = .failed("That websocket URL is not valid.")
            return nil
        }

        let endpointKind = SidekickConnectionEndpointKind(url: url)
        if endpointKind == .invalid {
            connectionState = .failed("Use a valid `ws://` or `wss://` websocket URL.")
            return nil
        }

        if endpointKind.requiresBearerToken && authToken.isEmpty {
            connectionState = .failed(
                "Tailscale pairing requires a bearer token from the host."
            )
            return nil
        }

        if !authToken.isEmpty, !endpointKind.supportsBearerToken(scheme: url.scheme) {
            connectionState = .failed(
                "Bearer tokens require `wss://` for manual remote hosts. For Tailscale, use a `.ts.net` hostname or Tailscale IP."
            )
            return nil
        }

        return ConnectionEndpoint(
            draft: draft,
            websocketURL: websocketURL,
            authToken: authToken
        )
    }

    func reconnect() async {
        guard hasSavedPairing else {
            return
        }
        await connect()
    }

    func pairWithDiscoveryCode() async {
        let discoveryTarget = discoveryInput
        guard !discoveryTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pairingErrorMessage = "Enter a `.ts.net` host, a Tailscale IP, or a full discovery URL."
            return
        }

        let code = pairingCodeInput
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pairingErrorMessage = "Enter the short pairing code from the host."
            return
        }

        isDiscoveringHost = true
        isClaimingPairing = true
        clearRetryState(resetDiscoveredHost: false, resetPairingCode: false)
        defer {
            isDiscoveringHost = false
            isClaimingPairing = false
        }

        do {
            let bootstrap = try await pairingBrokerClient.redeemDiscoveryCode(
                from: discoveryTarget,
                code: code
            )
            discoveredHost = bootstrap.discovery
            connectionDraft = bootstrap.draft
            connectionState = .disconnected
            await connect()
            pairingCodeInput = ""
        } catch {
            pairingErrorMessage = error.localizedDescription
        }
    }

    func importPairingLink(_ rawValue: String) async {
        do {
            let payload = try PairingLink.parse(rawValue)
            discoveryInput = payload.discoveryURL
            if let code = payload.code, !code.isEmpty {
                pairingCodeInput = code
                await pairWithDiscoveryCode()
            } else {
                isDiscoveringHost = true
                clearRetryState(resetDiscoveredHost: false, resetPairingCode: false)
                defer { isDiscoveringHost = false }

                let discoveredHost = try await pairingBrokerClient.discover(from: payload.discoveryURL)
                self.discoveredHost = discoveredHost
                connectionDraft.websocketURL = discoveredHost.websocketURL
                if connectionDraft.normalizedAuthToken.isEmpty {
                    connectionDraft.authToken = ""
                }
            }
        } catch {
            pairingErrorMessage = error.localizedDescription
        }
    }

    func forgetPairing() async {
        await disconnectTransport()
        try? pairingStore.clear()
        pairedConnection = nil
        initializeResponse = nil
        threads = []
        threadDetails = [:]
        selectedThreadID = nil
        pendingApprovals = []
        hostAppearance = HostAppearanceSnapshot(themeName: nil)
        hostModelName = nil
        hostModelProviderName = nil
        hostReasoningEffortName = nil
        hostSandboxModeName = nil
        hostApprovalPolicyValue = nil
        accountRateLimits = nil
        threadTokenUsageByThreadID = [:]
        connectionState = .disconnected
        banner = nil
        pairingErrorMessage = nil
        connectionDraft.authToken = ""
    }

    func refreshThreads(using context: ThreadListContext? = nil) async {
        guard let transport else { return }

        if let context {
            threadListContext = context
        }

        do {
            let response: ThreadListResponse = try await transport.request(
                method: "thread/list",
                params: ThreadListParams(
                    sortKey: threadListContext.sortKey,
                    archived: false,
                    cwd: threadListContext.cwd
                ),
                as: ThreadListResponse.self
            )
            let visibleThreadIDs = Set(response.data.map(\.id))
            threads = response.data
            threadDetails = threadDetails.filter { visibleThreadIDs.contains($0.key) }
            if let selectedThreadID,
               threads.contains(where: { $0.id == selectedThreadID }) == false {
                self.selectedThreadID = threads.first?.id
            } else if selectedThreadID == nil {
                selectedThreadID = threads.first?.id
            }
        } catch {
            showBanner(
                "Could not load threads: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func createThread(cwd: String? = nil) async -> String? {
        guard let transport else {
            showBanner("Connect to Codex before starting a thread.", tone: .warning)
            return nil
        }

        do {
            let response: ThreadStartResponse = try await transport.request(
                method: "thread/start",
                params: ThreadStartParams(cwd: cwd),
                as: ThreadStartResponse.self
            )
            storeThread(response.thread)
            selectedThreadID = response.thread.id
            await readThread(response.thread.id, force: true)
            return response.thread.id
        } catch {
            showBanner(
                "Could not start a new thread: \(error.localizedDescription)",
                tone: .danger
            )
            return nil
        }
    }

    func selectThread(_ threadID: String?) async {
        selectedThreadID = threadID
        guard let threadID else {
            return
        }
        await readThread(threadID, force: false)
    }

    func readThread(_ threadID: String, force: Bool) async {
        if !force, threadDetails[threadID] != nil {
            return
        }
        guard let transport else { return }

        do {
            let response: ThreadReadResponse = try await transport.request(
                method: "thread/read",
                params: ThreadReadParams(threadId: threadID, includeTurns: true),
                as: ThreadReadResponse.self
            )
            storeThread(response.thread)
        } catch {
            showBanner(
                "Could not open thread: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func openSelectedThread() async {
        guard let selectedThreadID else { return }
        do {
            try await resumeThread(selectedThreadID)
        } catch {
            showBanner(
                "Could not open live thread: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func sendHandoff() async {
        guard let selectedThreadID else { return }
        let text = handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await sendHandoff(input: [.text(text)])
    }

    func sendHandoff(input: [UserInputPayload]) async {
        guard let selectedThreadID else { return }
        guard !input.isEmpty else { return }
        guard let transport else { return }

        do {
            try await resumeThread(selectedThreadID)
            let response: TurnStartResponse = try await transport.request(
                method: "turn/start",
                params: TurnStartParams(
                    threadId: selectedThreadID,
                    input: input
                ),
                as: TurnStartResponse.self
            )
            replaceTurn(threadID: selectedThreadID, turn: response.turn)
            handoffDraft = ""
        } catch {
            showBanner(
                "Could not send handoff: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func setHostModel(_ model: String) async {
        await writeConfigEdit(
            keyPath: "model",
            value: .string(model)
        )
    }

    func setHostReasoningEffort(_ effort: String) async {
        await writeConfigEdit(
            keyPath: "model_reasoning_effort",
            value: .string(effort)
        )
    }

    func setHostPermissionPreset(_ preset: PermissionPreset) async {
        switch preset {
        case .defaultPermissions:
            await writeConfigEdits([
                ConfigEdit(keyPath: "sandbox_mode", value: .null, mergeStrategy: .replace),
                ConfigEdit(keyPath: "approval_policy", value: .null, mergeStrategy: .replace)
            ])
        case .fullAccess:
            await writeConfigEdits([
                ConfigEdit(
                    keyPath: "sandbox_mode",
                    value: .string("danger-full-access"),
                    mergeStrategy: .replace
                ),
                ConfigEdit(
                    keyPath: "approval_policy",
                    value: .string("never"),
                    mergeStrategy: .replace
                )
            ])
        case .customConfig:
            showBanner(
                "Custom permission mode is managed by the host config.",
                tone: .neutral
            )
        }
    }

    func threadTokenUsage(for threadID: String) -> ThreadTokenUsage? {
        threadTokenUsageByThreadID[threadID]
    }

    func approveCommand(_ approval: PendingApproval, sessionScope: Bool) async {
        guard case .command = approval.kind, let transport else { return }

        let decision: CommandExecutionApprovalDecision = sessionScope ? .acceptForSession : .accept
        do {
            try await transport.reply(
                to: approval.requestID,
                with: CommandExecutionRequestApprovalResponse(decision: decision)
            )
            pendingApprovals.removeAll(where: { $0.id == approval.id })
        } catch {
            showBanner(
                "Could not respond to approval: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func denyCommand(_ approval: PendingApproval, cancelTurn: Bool) async {
        guard case .command = approval.kind, let transport else { return }

        let decision: CommandExecutionApprovalDecision = cancelTurn ? .cancel : .decline
        do {
            try await transport.reply(
                to: approval.requestID,
                with: CommandExecutionRequestApprovalResponse(decision: decision)
            )
            pendingApprovals.removeAll(where: { $0.id == approval.id })
        } catch {
            showBanner(
                "Could not respond to approval: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func approveFileChange(_ approval: PendingApproval, sessionScope: Bool) async {
        guard case .fileChange = approval.kind, let transport else { return }

        let decision: FileChangeApprovalDecision = sessionScope ? .acceptForSession : .accept
        do {
            try await transport.reply(
                to: approval.requestID,
                with: FileChangeRequestApprovalResponse(decision: decision)
            )
            pendingApprovals.removeAll(where: { $0.id == approval.id })
        } catch {
            showBanner(
                "Could not respond to approval: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func denyFileChange(_ approval: PendingApproval, cancelTurn: Bool) async {
        guard case .fileChange = approval.kind, let transport else { return }

        let decision: FileChangeApprovalDecision = cancelTurn ? .cancel : .decline
        do {
            try await transport.reply(
                to: approval.requestID,
                with: FileChangeRequestApprovalResponse(decision: decision)
            )
            pendingApprovals.removeAll(where: { $0.id == approval.id })
        } catch {
            showBanner(
                "Could not respond to approval: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    func title(for threadID: String) -> String {
        threadDetails[threadID]?.displayTitle
            ?? threads.first(where: { $0.id == threadID })?.displayTitle
            ?? "Thread"
    }

    func refreshHostConfigSnapshot() async {
        guard let transport else {
            hostAppearance = HostAppearanceSnapshot(themeName: nil)
            hostModelName = nil
            hostModelProviderName = nil
            hostReasoningEffortName = nil
            hostSandboxModeName = nil
            hostApprovalPolicyValue = nil
            return
        }

        do {
            let response: ConfigReadResponse = try await transport.request(
                method: "config/read",
                params: ConfigReadParams(),
                as: ConfigReadResponse.self
            )
            hostAppearance = HostAppearanceSnapshot(themeName: response.config.tuiThemeName)
            hostModelName = response.config.modelName
            hostModelProviderName = response.config.modelProviderName
            hostReasoningEffortName = response.config.reasoningEffortName
            hostSandboxModeName = response.config.sandboxModeName
            hostApprovalPolicyValue = response.config.approvalPolicyValue
        } catch {
            hostAppearance = HostAppearanceSnapshot(themeName: nil)
            hostModelName = nil
            hostModelProviderName = nil
            hostReasoningEffortName = nil
            hostSandboxModeName = nil
            hostApprovalPolicyValue = nil
        }
    }

    func refreshAccountRateLimits() async {
        guard let transport else {
            accountRateLimits = nil
            return
        }

        do {
            let response: GetAccountRateLimitsResponse = try await transport.request(
                method: "account/rateLimits/read",
                as: GetAccountRateLimitsResponse.self
            )
            accountRateLimits = response.rateLimits
        } catch {
            accountRateLimits = nil
        }
    }

    func setAppearanceMode(_ mode: SidekickThemeMode) {
        appearanceSettings.mode = mode
        persistAppearance()
    }

    func setAppearancePreset(_ preset: SidekickThemePreset) {
        appearanceSettings.preset = preset
        persistAppearance()
    }

    func setSyncWithHostTheme(_ isEnabled: Bool) {
        appearanceSettings.syncsWithHostTheme = isEnabled
        persistAppearance()
        if isEnabled {
            Task {
                await refreshHostConfigSnapshot()
            }
        }
    }

    func setTranslucentSidebar(_ isEnabled: Bool) {
        appearanceSettings.translucentSidebar = isEnabled
        persistAppearance()
    }

    func setUIFontScale(_ scale: Double) {
        appearanceSettings.uiScale = scale
        persistAppearance()
    }

    func setCodeFontScale(_ scale: Double) {
        appearanceSettings.codeScale = scale
        persistAppearance()
    }

    func setContrast(_ contrast: Double) {
        appearanceSettings.contrast = contrast
        persistAppearance()
    }

    private func resumeThread(_ threadID: String) async throws {
        guard let transport else {
            throw URLError(.networkConnectionLost)
        }
        let response: ThreadResumeResponse = try await transport.request(
            method: "thread/resume",
            params: ThreadResumeParams(threadId: threadID),
            as: ThreadResumeResponse.self
        )
        storeThread(response.thread)
        connectionState = .connected
    }

    private func writeConfigEdit(keyPath: String, value: JSONValue) async {
        await writeConfigEdits([
            ConfigEdit(
                keyPath: keyPath,
                value: value,
                mergeStrategy: .replace
            )
        ])
    }

    private func writeConfigEdits(_ edits: [ConfigEdit]) async {
        guard let transport else {
            showBanner("Connect to Codex before updating host settings.", tone: .warning)
            return
        }

        do {
            let _: ConfigWriteResponse = try await transport.request(
                method: "config/batchWrite",
                params: ConfigBatchWriteParams(
                    edits: edits,
                    filePath: nil,
                    expectedVersion: nil,
                    reloadUserConfig: true
                ),
                as: ConfigWriteResponse.self
            )
            await refreshHostConfigSnapshot()
        } catch {
            showBanner(
                "Could not update host config: \(error.localizedDescription)",
                tone: .danger
            )
        }
    }

    private func startListening(to eventStream: AsyncStream<CodexTransportEvent>) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in eventStream {
                await self?.consume(event)
            }
        }
    }

    private func consume(_ event: CodexTransportEvent) async {
        switch event {
        case .notification(let notification):
            handle(notification)
        case .serverRequest(let request):
            handle(request)
        case .disconnected(let message):
            connectionState = .failed(message)
            showBanner("Connection closed", tone: .danger)
        }
    }

    private func handle(_ request: CodexServerRequestEvent) {
        switch request {
        case .commandExecutionApproval(let requestID, let params):
            let approval = PendingApproval(
                id: requestID.displayValue,
                requestID: requestID,
                threadID: params.threadId,
                turnID: params.turnId,
                itemID: params.itemId,
                kind: .command(params)
            )
            upsertApproval(approval)
        case .fileChangeApproval(let requestID, let params):
            let approval = PendingApproval(
                id: requestID.displayValue,
                requestID: requestID,
                threadID: params.threadId,
                turnID: params.turnId,
                itemID: params.itemId,
                kind: .fileChange(params)
            )
            upsertApproval(approval)
        }
    }

    private func handle(_ notification: CodexNotificationEvent) {
        switch notification {
        case .threadStarted(let payload):
            storeThread(payload.thread)
        case .threadStatusChanged(let payload):
            mutateThread(payload.threadId) { thread in
                thread.status = payload.status
            }
        case .threadNameUpdated(let payload):
            mutateThread(payload.threadId) { thread in
                thread.name = payload.threadName
            }
        case .threadTokenUsageUpdated(let payload):
            threadTokenUsageByThreadID[payload.threadId] = payload.tokenUsage
        case .threadArchived(let payload):
            removeThread(payload.threadId)
        case .threadUnarchived:
            Task {
                await refreshThreads()
            }
        case .turnStarted(let payload):
            replaceTurn(threadID: payload.threadId, turn: payload.turn)
        case .turnCompleted(let payload):
            replaceTurn(threadID: payload.threadId, turn: payload.turn)
            Task {
                await refreshThreads()
            }
        case .itemStarted(let payload):
            replaceItem(threadID: payload.threadId, turnID: payload.turnId, item: payload.item)
        case .itemCompleted(let payload):
            replaceItem(threadID: payload.threadId, turnID: payload.turnId, item: payload.item)
        case .agentMessageDelta(let payload):
            appendAgentDelta(
                threadID: payload.threadId,
                turnID: payload.turnId,
                itemID: payload.itemId,
                delta: payload.delta
            )
        case .serverRequestResolved(let payload):
            pendingApprovals.removeAll(where: { $0.requestID == payload.requestId })
        case .accountRateLimitsUpdated(let payload):
            accountRateLimits = payload.rateLimits
        }
    }

    private func storeThread(_ thread: CodexThread) {
        threadDetails[thread.id] = thread
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
        threads.sort(by: { $0.updatedAt > $1.updatedAt })
        if selectedThreadID == nil {
            selectedThreadID = thread.id
        }
    }

    private func removeThread(_ threadID: String) {
        threadDetails.removeValue(forKey: threadID)
        threads.removeAll(where: { $0.id == threadID })
        if selectedThreadID == threadID {
            selectedThreadID = threads.first?.id
        }
    }

    private func mutateThread(_ threadID: String, mutate: (inout CodexThread) -> Void) {
        let thread = threadDetails[threadID]
            ?? threads.first(where: { $0.id == threadID })
        guard var thread else {
            return
        }
        mutate(&thread)
        storeThread(thread)
    }

    private func replaceTurn(threadID: String, turn: CodexTurn) {
        mutateThread(threadID) { thread in
            if let index = thread.turns.firstIndex(where: { $0.id == turn.id }) {
                thread.turns[index] = turn
            } else {
                thread.turns.append(turn)
            }
            thread.updatedAt = Date().timeIntervalSince1970
        }
    }

    private func replaceItem(threadID: String, turnID: String, item: ThreadItem) {
        mutateThread(threadID) { thread in
            let turnIndex = ensureTurn(turnID, in: &thread.turns)
            if let itemIndex = thread.turns[turnIndex].items.firstIndex(where: { $0.id == item.id }) {
                thread.turns[turnIndex].items[itemIndex] = item
            } else {
                thread.turns[turnIndex].items.append(item)
            }
            thread.turns[turnIndex].status = .inProgress
            thread.updatedAt = Date().timeIntervalSince1970
        }
    }

    private func appendAgentDelta(threadID: String, turnID: String, itemID: String, delta: String) {
        mutateThread(threadID) { thread in
            let turnIndex = ensureTurn(turnID, in: &thread.turns)
            if let itemIndex = thread.turns[turnIndex].items.firstIndex(where: { $0.id == itemID }),
               case .agentMessage(var message) = thread.turns[turnIndex].items[itemIndex] {
                message.text += delta
                thread.turns[turnIndex].items[itemIndex] = .agentMessage(message)
            } else {
                thread.turns[turnIndex].items.append(
                    .agentMessage(AgentMessageItem(id: itemID, text: delta, phase: nil))
                )
            }
            thread.turns[turnIndex].status = .inProgress
            thread.updatedAt = Date().timeIntervalSince1970
        }
    }

    private func ensureTurn(_ turnID: String, in turns: inout [CodexTurn]) -> Int {
        if let index = turns.firstIndex(where: { $0.id == turnID }) {
            return index
        }
        turns.append(CodexTurn(id: turnID, items: [], status: .inProgress, error: nil))
        return turns.endIndex - 1
    }

    private func upsertApproval(_ approval: PendingApproval) {
        let wasEmpty = pendingApprovals.isEmpty
        if let index = pendingApprovals.firstIndex(where: { $0.id == approval.id }) {
            pendingApprovals[index] = approval
        } else {
            pendingApprovals.insert(approval, at: 0)
        }
        if wasEmpty {
            showBanner(
                "Approval waiting in \(title(for: approval.threadID))",
                tone: .warning
            )
        }
        if selectedThreadID == nil {
            selectedThreadID = approval.threadID
        }
    }

    private func disconnectTransport() async {
        eventTask?.cancel()
        eventTask = nil
        if let transport {
            try? await transport.disconnect()
        }
        transport = nil
    }

    private func persistAppearance() {
        try? appearanceStore.save(appearanceSettings)
    }

    private func clearRetryState(resetDiscoveredHost: Bool, resetPairingCode: Bool) {
        pairingErrorMessage = nil
        banner = nil
        if case .failed = connectionState {
            connectionState = .disconnected
        }
        if resetDiscoveredHost {
            discoveredHost = nil
        }
        if resetPairingCode {
            pairingCodeInput = ""
        }
    }

    private func showBanner(_ message: String, tone: StatusTone) {
        banner = BannerState(message: message, tone: tone)
    }
}
