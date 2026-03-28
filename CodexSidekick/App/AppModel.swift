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

    var connectionDraft = ConnectionDraft()
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
    var isBootstrapping = false
    var bannerMessage: String?

    private let pairingStore = PairingStore()
    private let appearanceStore = AppearanceStore()
    private var transport: CodexTransport?
    private var eventTask: Task<Void, Never>?

    var hasSavedPairing: Bool {
        pairedConnection != nil
    }

    var isConnecting: Bool {
        connectionState == .connecting
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

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        if let storedAppearance = appearanceStore.load() {
            appearanceSettings = storedAppearance
        }

        guard let restored = pairingStore.load() else {
            return
        }

        pairedConnection = restored.stored
        connectionDraft = ConnectionDraft(
            websocketURL: restored.stored.websocketURL,
            authToken: restored.token ?? ""
        )
        await connect()
    }

    func connect() async {
        let draft = connectionDraft
        let websocketURL = draft.normalizedWebsocketURL
        let authToken = draft.normalizedAuthToken

        guard !websocketURL.isEmpty else {
            connectionState = .failed("Enter a websocket URL for `codex app-server`.")
            return
        }

        guard let url = URL(string: websocketURL) else {
            connectionState = .failed("That websocket URL is not valid.")
            return
        }

        let endpointKind = SidekickConnectionEndpointKind(url: url)
        if endpointKind == .invalid {
            connectionState = .failed("Use a valid `ws://` or `wss://` websocket URL.")
            return
        }

        if endpointKind.requiresBearerToken && authToken.isEmpty {
            connectionState = .failed(
                "Tailscale pairing requires a bearer token from the host."
            )
            return
        }

        if !authToken.isEmpty, !endpointKind.supportsBearerToken(scheme: url.scheme) {
            connectionState = .failed(
                "Bearer tokens require `wss://` for manual remote hosts. For Tailscale, use a `.ts.net` hostname or Tailscale IP."
            )
            return
        }

        await disconnectTransport()
        connectionState = .connecting
        bannerMessage = nil

        do {
            let transport = CodexTransport()
            let (initializeResponse, eventStream) = try await transport.connect(
                websocketURL: websocketURL,
                authToken: authToken.isEmpty ? nil : authToken,
                clientName: "codex_sidekick_ios",
                clientTitle: "Codex Sidekick iOS",
                clientVersion: "0.1.0"
            )

            self.transport = transport
            self.initializeResponse = initializeResponse
            self.pairedConnection = try pairingStore.save(draft)
            self.connectionState = .connected
            startListening(to: eventStream)
            await refreshThreads()
            await refreshHostAppearance()
        } catch {
            self.connectionState = .failed(error.localizedDescription)
        }
    }

    func reconnect() async {
        guard hasSavedPairing else {
            return
        }
        await connect()
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
        connectionState = .disconnected
        bannerMessage = nil
        connectionDraft.authToken = ""
    }

    func refreshThreads() async {
        guard let transport else { return }

        do {
            let response: ThreadListResponse = try await transport.request(
                method: "thread/list",
                params: ThreadListParams(archived: false),
                as: ThreadListResponse.self
            )
            let visibleThreadIDs = Set(response.data.map(\.id))
            threads = response.data.sorted(by: { $0.updatedAt > $1.updatedAt })
            threadDetails = threadDetails.filter { visibleThreadIDs.contains($0.key) }
            if let selectedThreadID,
               threads.contains(where: { $0.id == selectedThreadID }) == false {
                self.selectedThreadID = threads.first?.id
            } else if selectedThreadID == nil {
                selectedThreadID = threads.first?.id
            }
        } catch {
            bannerMessage = "Could not load threads: \(error.localizedDescription)"
        }
    }

    func createThread() async -> String? {
        guard let transport else {
            bannerMessage = "Connect to Codex before starting a thread."
            return nil
        }

        do {
            let response: ThreadStartResponse = try await transport.request(
                method: "thread/start",
                params: ThreadStartParams(),
                as: ThreadStartResponse.self
            )
            storeThread(response.thread)
            selectedThreadID = response.thread.id
            await readThread(response.thread.id, force: true)
            return response.thread.id
        } catch {
            bannerMessage = "Could not start a new thread: \(error.localizedDescription)"
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
            bannerMessage = "Could not open thread: \(error.localizedDescription)"
        }
    }

    func openSelectedThread() async {
        guard let selectedThreadID else { return }
        do {
            try await resumeThread(selectedThreadID)
        } catch {
            bannerMessage = "Could not open live thread: \(error.localizedDescription)"
        }
    }

    func sendHandoff() async {
        guard let selectedThreadID else { return }
        let text = handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let transport else { return }

        do {
            try await resumeThread(selectedThreadID)
            let response: TurnStartResponse = try await transport.request(
                method: "turn/start",
                params: TurnStartParams(
                    threadId: selectedThreadID,
                    input: [.text(text)]
                ),
                as: TurnStartResponse.self
            )
            replaceTurn(threadID: selectedThreadID, turn: response.turn)
            handoffDraft = ""
        } catch {
            bannerMessage = "Could not send handoff: \(error.localizedDescription)"
        }
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
            bannerMessage = "Could not respond to approval: \(error.localizedDescription)"
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
            bannerMessage = "Could not respond to approval: \(error.localizedDescription)"
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
            bannerMessage = "Could not respond to approval: \(error.localizedDescription)"
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
            bannerMessage = "Could not respond to approval: \(error.localizedDescription)"
        }
    }

    func title(for threadID: String) -> String {
        threadDetails[threadID]?.displayTitle
            ?? threads.first(where: { $0.id == threadID })?.displayTitle
            ?? "Thread"
    }

    func refreshHostAppearance() async {
        guard let transport else {
            hostAppearance = HostAppearanceSnapshot(themeName: nil)
            return
        }

        do {
            let response: ConfigReadResponse = try await transport.request(
                method: "config/read",
                params: ConfigReadParams(),
                as: ConfigReadResponse.self
            )
            hostAppearance = HostAppearanceSnapshot(themeName: response.config.tuiThemeName)
        } catch {
            hostAppearance = HostAppearanceSnapshot(themeName: nil)
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
                await refreshHostAppearance()
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
            bannerMessage = "Connection closed"
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
            bannerMessage = "Approval waiting in \(title(for: approval.threadID))"
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
}
