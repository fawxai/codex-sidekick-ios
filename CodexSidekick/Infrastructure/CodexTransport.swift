import Foundation

private final class PendingResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<JSONValue, Error>?
    private var continuation: CheckedContinuation<JSONValue, Error>?

    func wait() async throws -> JSONValue {
        if let result = consumeResult() {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            storeOrResume(continuation)
        }
    }

    func succeed(_ value: JSONValue) {
        resolve(.success(value))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    private func consumeResult() -> Result<JSONValue, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { result = nil }
        return result
    }

    private func storeOrResume(_ continuation: CheckedContinuation<JSONValue, Error>) {
        let pendingResult: Result<JSONValue, Error>?

        lock.lock()
        if let result {
            self.result = nil
            pendingResult = result
        } else {
            self.continuation = continuation
            pendingResult = nil
        }
        lock.unlock()

        if let pendingResult {
            continuation.resume(with: pendingResult)
        }
    }

    private func resolve(_ result: Result<JSONValue, Error>) {
        let pendingContinuation: CheckedContinuation<JSONValue, Error>?

        lock.lock()
        if let continuation = self.continuation {
            self.continuation = nil
            pendingContinuation = continuation
        } else {
            self.result = result
            pendingContinuation = nil
        }
        lock.unlock()

        pendingContinuation?.resume(with: result)
    }
}

enum CodexTransportError: LocalizedError {
    case failedToEncodeWebSocketMessage

    var errorDescription: String? {
        switch self {
        case .failedToEncodeWebSocketMessage:
            "The request could not be encoded as a websocket text frame."
        }
    }
}

enum CodexNotificationEvent: Sendable {
    case threadStarted(ThreadStartedNotification)
    case threadStatusChanged(ThreadStatusChangedNotification)
    case threadNameUpdated(ThreadNameUpdatedNotification)
    case threadTokenUsageUpdated(ThreadTokenUsageUpdatedNotification)
    case threadArchived(ThreadArchivedNotification)
    case threadUnarchived(ThreadUnarchivedNotification)
    case turnStarted(TurnStartedNotification)
    case turnCompleted(TurnCompletedNotification)
    case itemStarted(ItemStartedNotification)
    case itemCompleted(ItemCompletedNotification)
    case agentMessageDelta(AgentMessageDeltaNotification)
    case serverRequestResolved(ServerRequestResolvedNotification)
    case accountRateLimitsUpdated(AccountRateLimitsUpdatedNotification)
}

enum CodexServerRequestEvent: Sendable {
    case commandExecutionApproval(requestID: RPCID, params: CommandExecutionRequestApprovalParams)
    case fileChangeApproval(requestID: RPCID, params: FileChangeRequestApprovalParams)
}

enum CodexTransportEvent: Sendable {
    case notification(CodexNotificationEvent)
    case serverRequest(CodexServerRequestEvent)
    case disconnected(String)
}

actor CodexTransport {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var websocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<CodexTransportEvent>.Continuation?
    private var pendingResponses: [RPCID: PendingResponse] = [:]
    private var nextRequestID = 1

    init(session: URLSession = .shared) {
        self.session = session
        encoder.outputFormatting = [.sortedKeys]
    }

    func connect(
        websocketURL: String,
        authToken: String?,
        clientName: String,
        clientTitle: String,
        clientVersion: String,
        experimentalAPI: Bool = true
    ) async throws -> (InitializeResponse, AsyncStream<CodexTransportEvent>) {
        try await disconnect()

        guard let url = URL(string: websocketURL) else {
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: url)
        if let authToken, !authToken.isEmpty {
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: urlRequest)
        websocketTask = task
        task.resume()

        var continuation: AsyncStream<CodexTransportEvent>.Continuation?
        let stream = AsyncStream<CodexTransportEvent> { continuation = $0 }
        eventContinuation = continuation

        receiveTask = Task {
            await receiveLoop()
        }

        let initialize = InitializeParams(
            clientInfo: ClientInfo(
                name: clientName,
                title: clientTitle,
                version: clientVersion
            ),
            capabilities: InitializeCapabilities(
                experimentalApi: experimentalAPI,
                optOutNotificationMethods: nil
            )
        )

        let response: InitializeResponse = try await request(
            method: "initialize",
            params: initialize,
            as: InitializeResponse.self
        )
        try await notify(method: "initialized")
        return (response, stream)
    }

    func disconnect() async throws {
        for (_, continuation) in pendingResponses {
            continuation.fail(CancellationError())
        }
        pendingResponses.removeAll()
        receiveTask?.cancel()
        receiveTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
    }

    func request<Response: Decodable, Params: Encodable & Sendable>(
        method: String,
        params: Params,
        as type: Response.Type
    ) async throws -> Response {
        let requestID = RPCID.integer(nextRequestID)
        nextRequestID += 1

        let rawResult = try await sendRequest(
            id: requestID,
            envelope: JSONRPCRequestEnvelope(
                id: requestID,
                method: method,
                params: params
            )
        )

        return try rawResult.decoded(as: Response.self, using: decoder)
    }

    func request<Response: Decodable>(
        method: String,
        as type: Response.Type
    ) async throws -> Response {
        let requestID = RPCID.integer(nextRequestID)
        nextRequestID += 1

        let rawResult = try await sendRequest(
            id: requestID,
            envelope: JSONRPCRequestEnvelope<JSONValue?>(
                id: requestID,
                method: method,
                params: nil
            )
        )

        return try rawResult.decoded(as: Response.self, using: decoder)
    }

    func notify(method: String) async throws {
        try await send(JSONRPCNotificationEnvelope<JSONValue?>(method: method, params: nil))
    }

    func reply<Result: Encodable & Sendable>(to requestID: RPCID, with result: Result) async throws {
        try await send(JSONRPCResultEnvelope(id: requestID, result: result))
    }

    func reject(requestID: RPCID, code: Int = -32601, message: String) async throws {
        try await send(
            JSONRPCErrorEnvelope(
                id: requestID,
                error: JSONRPCErrorBody(code: code, data: nil, message: message)
            )
        )
    }

    private func sendRequest<Envelope: Encodable>(
        id: RPCID,
        envelope: Envelope
    ) async throws -> JSONValue {
        let pendingResponse = PendingResponse()
        pendingResponses[id] = pendingResponse

        do {
            try await send(envelope)
        } catch {
            failPendingResponse(id: id, error: error)
            throw error
        }

        return try await pendingResponse.wait()
    }

    private func send<Envelope: Encodable>(_ envelope: Envelope) async throws {
        guard let websocketTask else {
            throw URLError(.networkConnectionLost)
        }
        let data = try encoder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexTransportError.failedToEncodeWebSocketMessage
        }
        try await websocketTask.send(.string(text))
    }

    private func receiveLoop() async {
        guard let websocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await websocketTask.receive()
                switch message {
                case .string(let text):
                    try await handleIncomingText(text)
                case .data(let data):
                    guard let text = String(data: data, encoding: .utf8) else {
                        continue
                    }
                    try await handleIncomingText(text)
                @unknown default:
                    continue
                }
            } catch is CancellationError {
                break
            } catch {
                if Task.isCancelled {
                    break
                }
                eventContinuation?.yield(.disconnected(error.localizedDescription))
                break
            }
        }

        eventContinuation?.finish()
        eventContinuation = nil
        websocketTask.cancel(with: .goingAway, reason: nil)
        self.websocketTask = nil
    }

    private func handleIncomingText(_ text: String) async throws {
        let envelope = try decoder.decode(JSONRPCInboundEnvelope.self, from: Data(text.utf8))

        if let requestID = envelope.id, let method = envelope.method {
            try await routeServerRequest(id: requestID, method: method, params: envelope.params)
            return
        }

        if let method = envelope.method {
            try await routeNotification(method: method, params: envelope.params)
            return
        }

        if let requestID = envelope.id, let error = envelope.error {
            failPendingResponse(id: requestID, error: error)
            return
        }

        if let requestID = envelope.id {
            resumePendingResponse(id: requestID, result: envelope.result ?? .null)
        }
    }

    private func routeNotification(method: String, params: JSONValue?) async throws {
        switch method {
        case "thread/started":
            let notification = try decodeParams(ThreadStartedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadStarted(notification)))
        case "thread/status/changed":
            let notification = try decodeParams(ThreadStatusChangedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadStatusChanged(notification)))
        case "thread/name/updated":
            let notification = try decodeParams(ThreadNameUpdatedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadNameUpdated(notification)))
        case "thread/tokenUsage/updated":
            let notification = try decodeParams(ThreadTokenUsageUpdatedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadTokenUsageUpdated(notification)))
        case "thread/archived":
            let notification = try decodeParams(ThreadArchivedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadArchived(notification)))
        case "thread/unarchived":
            let notification = try decodeParams(ThreadUnarchivedNotification.self, from: params)
            eventContinuation?.yield(.notification(.threadUnarchived(notification)))
        case "turn/started":
            let notification = try decodeParams(TurnStartedNotification.self, from: params)
            eventContinuation?.yield(.notification(.turnStarted(notification)))
        case "turn/completed":
            let notification = try decodeParams(TurnCompletedNotification.self, from: params)
            eventContinuation?.yield(.notification(.turnCompleted(notification)))
        case "item/started":
            let notification = try decodeParams(ItemStartedNotification.self, from: params)
            eventContinuation?.yield(.notification(.itemStarted(notification)))
        case "item/completed":
            let notification = try decodeParams(ItemCompletedNotification.self, from: params)
            eventContinuation?.yield(.notification(.itemCompleted(notification)))
        case "item/agentMessage/delta":
            let notification = try decodeParams(AgentMessageDeltaNotification.self, from: params)
            eventContinuation?.yield(.notification(.agentMessageDelta(notification)))
        case "serverRequest/resolved":
            let notification = try decodeParams(ServerRequestResolvedNotification.self, from: params)
            eventContinuation?.yield(.notification(.serverRequestResolved(notification)))
        case "account/rateLimits/updated":
            let notification = try decodeParams(AccountRateLimitsUpdatedNotification.self, from: params)
            eventContinuation?.yield(.notification(.accountRateLimitsUpdated(notification)))
        default:
            break
        }
    }

    private func routeServerRequest(id: RPCID, method: String, params: JSONValue?) async throws {
        switch method {
        case "item/commandExecution/requestApproval":
            let request = try decodeParams(CommandExecutionRequestApprovalParams.self, from: params)
            eventContinuation?.yield(.serverRequest(.commandExecutionApproval(requestID: id, params: request)))
        case "item/fileChange/requestApproval":
            let request = try decodeParams(FileChangeRequestApprovalParams.self, from: params)
            eventContinuation?.yield(.serverRequest(.fileChangeApproval(requestID: id, params: request)))
        default:
            try await reject(
                requestID: id,
                message: "unsupported remote app-server request `\(method)`"
            )
        }
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: JSONValue?) throws -> T {
        if let params {
            return try params.decoded(as: T.self, using: decoder)
        }
        return try decoder.decode(T.self, from: Data("{}".utf8))
    }

    private func resumePendingResponse(id: RPCID, result: JSONValue) {
        guard let pendingResponse = pendingResponses.removeValue(forKey: id) else {
            return
        }
        pendingResponse.succeed(result)
    }

    private func failPendingResponse(id: RPCID, error: Error) {
        guard let pendingResponse = pendingResponses.removeValue(forKey: id) else {
            return
        }
        pendingResponse.fail(error)
    }
}
