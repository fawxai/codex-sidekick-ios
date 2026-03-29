import Foundation

struct ClientInfo: Encodable, Sendable {
    let name: String
    let title: String?
    let version: String
}

struct InitializeCapabilities: Encodable, Sendable {
    let experimentalApi: Bool
    let optOutNotificationMethods: [String]?
}

struct InitializeParams: Encodable, Sendable {
    let clientInfo: ClientInfo
    let capabilities: InitializeCapabilities?
}

struct InitializeResponse: Decodable, Sendable {
    let userAgent: String?
    let codexHome: String?
    let platformFamily: String?
    let platformOs: String?
}

struct ConfigReadParams: Encodable, Sendable {
    let includeLayers: Bool
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case includeLayers = "include_layers"
        case cwd
    }

    init(includeLayers: Bool = false, cwd: String? = nil) {
        self.includeLayers = includeLayers
        self.cwd = cwd
    }
}

struct ConfigReadResponse: Decodable, Sendable {
    let config: HostConfigSnapshot
}

enum ConfigMergeStrategy: String, Encodable, Sendable {
    case replace
    case upsert
}

struct ConfigEdit: Encodable, Sendable {
    let keyPath: String
    let value: JSONValue
    let mergeStrategy: ConfigMergeStrategy
}

struct ConfigBatchWriteParams: Encodable, Sendable {
    let edits: [ConfigEdit]
    let filePath: String?
    let expectedVersion: String?
    let reloadUserConfig: Bool
}

struct ConfigWriteResponse: Decodable, Sendable {
    let version: String
}

struct HostConfigSnapshot: Decodable, Sendable {
    let raw: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: JSONValue].self)
    }
}

extension HostConfigSnapshot {
    var tuiThemeName: String? {
        guard case .object(let tuiSection)? = raw["tui"],
              case .string(let themeName)? = tuiSection["theme"] else {
            return nil
        }
        return themeName
    }

    var modelName: String? {
        raw["model"]?.stringValue
    }

    var modelProviderName: String? {
        raw["model_provider"]?.stringValue
    }

    var reasoningEffortName: String? {
        raw["model_reasoning_effort"]?.stringValue
    }

    var sandboxModeName: String? {
        raw["sandbox_mode"]?.stringValue
    }

    var approvalPolicyValue: JSONValue? {
        raw["approval_policy"]
    }
}

enum ThreadSortKey: String, Encodable, Sendable {
    case createdAt = "created_at"
    case updatedAt = "updated_at"
}

struct ThreadListParams: Encodable, Sendable {
    var cursor: String?
    var limit: Int?
    var sortKey: ThreadSortKey?
    var archived: Bool?
    var cwd: String?

    init(
        cursor: String? = nil,
        limit: Int? = 40,
        sortKey: ThreadSortKey? = .updatedAt,
        archived: Bool? = false,
        cwd: String? = nil
    ) {
        self.cursor = cursor
        self.limit = limit
        self.sortKey = sortKey
        self.archived = archived
        self.cwd = cwd
    }
}

struct ThreadReadParams: Encodable, Sendable {
    let threadId: String
    let includeTurns: Bool
}

struct ThreadResumeParams: Encodable, Sendable {
    let threadId: String
}

struct ThreadStartParams: Encodable, Sendable {
    var model: String?
    var modelProvider: String?
    var cwd: String?
    var ephemeral: Bool?

    init(
        model: String? = nil,
        modelProvider: String? = nil,
        cwd: String? = nil,
        ephemeral: Bool? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.cwd = cwd
        self.ephemeral = ephemeral
    }
}

struct TurnStartParams: Encodable, Sendable {
    let threadId: String
    let input: [UserInputPayload]
}

struct ThreadListResponse: Decodable, Sendable {
    let data: [CodexThread]
    let nextCursor: String?
}

struct ThreadReadResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct ThreadStartResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct ThreadResumeResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct TurnStartResponse: Decodable, Sendable {
    let turn: CodexTurn
}

enum ThreadActiveFlag: String, Decodable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
}

enum ThreadStatus: Sendable {
    case notLoaded
    case idle
    case systemError
    case active(flags: [ThreadActiveFlag])
}

extension ThreadStatus: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)

        switch rawType {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "systemError":
            self = .systemError
        case "active":
            self = .active(flags: try container.decodeIfPresent([ThreadActiveFlag].self, forKey: .activeFlags) ?? [])
        default:
            #if DEBUG
            print("[ThreadStatus] Unknown status type: \(rawType)")
            #endif
            self = .notLoaded
        }
    }
}

extension ThreadStatus {
    var label: String {
        switch self {
        case .notLoaded:
            return "Stored"
        case .idle:
            return "Idle"
        case .systemError:
            return "Error"
        case .active(let flags):
            if flags.contains(.waitingOnApproval) {
                return "Needs approval"
            }
            if flags.contains(.waitingOnUserInput) {
                return "Needs input"
            }
            return "Active"
        }
    }

    var tone: StatusTone {
        switch self {
        case .notLoaded, .idle:
            return .neutral
        case .systemError:
            return .danger
        case .active(let flags):
            return flags.contains(.waitingOnApproval) ? .warning : .success
        }
    }

    var isWaitingOnApproval: Bool {
        if case .active(let flags) = self {
            return flags.contains(.waitingOnApproval)
        }
        return false
    }
}

struct CodexThread: Decodable, Identifiable, Sendable {
    var id: String
    var preview: String
    var ephemeral: Bool
    var modelProvider: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var status: ThreadStatus
    var cwd: String
    var agentNickname: String?
    var agentRole: String?
    var gitInfo: CodexGitInfo?
    var name: String?
    var turns: [CodexTurn]

    private enum CodingKeys: String, CodingKey {
        case id
        case preview
        case ephemeral
        case modelProvider
        case createdAt
        case updatedAt
        case status
        case cwd
        case agentNickname
        case agentRole
        case gitInfo
        case name
        case turns
    }

    init(
        id: String,
        preview: String,
        ephemeral: Bool,
        modelProvider: String,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        status: ThreadStatus,
        cwd: String,
        agentNickname: String?,
        agentRole: String?,
        gitInfo: CodexGitInfo?,
        name: String?,
        turns: [CodexTurn]
    ) {
        self.id = id
        self.preview = preview
        self.ephemeral = ephemeral
        self.modelProvider = modelProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.cwd = cwd
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.gitInfo = gitInfo
        self.name = name
        self.turns = turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider) ?? "openai"
        createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? 0
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? createdAt
        status = try container.decode(ThreadStatus.self, forKey: .status)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        gitInfo = try container.decodeIfPresent(CodexGitInfo.self, forKey: .gitInfo)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        turns = try container.decodeIfPresent([CodexTurn].self, forKey: .turns) ?? []
    }
}

struct CodexGitInfo: Decodable, Sendable {
    let sha: String?
    let branch: String?
    let originURL: String?
}

extension CodexThread {
    var displayTitle: String {
        if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        if let trimmed = agentNickname?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPreview.isEmpty ? "Untitled Thread" : trimmedPreview
    }

    var subtitle: String {
        CodexDisplay.compactDirectoryDisplay(cwd)
    }

    var directoryDisplay: String {
        CodexDisplay.formatDirectoryDisplay(cwd)
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: updatedAt)
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }
}

enum TurnStatus: String, Decodable, Sendable {
    case completed = "completed"
    case interrupted = "interrupted"
    case failed = "failed"
    case inProgress = "inProgress"
}

struct TurnError: Decodable, Sendable {
    let message: String
}

struct CodexTurn: Decodable, Identifiable, Sendable {
    var id: String
    var items: [ThreadItem]
    var status: TurnStatus
    var error: TurnError?

    init(id: String, items: [ThreadItem], status: TurnStatus, error: TurnError?) {
        self.id = id
        self.items = items
        self.status = status
        self.error = error
    }
}

enum UserInputPayload: Sendable {
    case text(String)
    case image(String)
    case localImage(String)
    case skill(name: String, path: String)
    case mention(name: String, path: String)
}

extension UserInputPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements
        case url
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(try container.decode(String.self, forKey: .url))
        case "localImage":
            self = .localImage(try container.decode(String.self, forKey: .path))
        case "skill":
            self = .skill(
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        case "mention":
            self = .mention(
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        default:
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode([String](), forKey: .textElements)
        case .image(let url):
            try container.encode("image", forKey: .type)
            try container.encode(url, forKey: .url)
        case .localImage(let path):
            try container.encode("localImage", forKey: .type)
            try container.encode(path, forKey: .path)
        case .skill(let name, let path):
            try container.encode("skill", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case .mention(let name, let path):
            try container.encode("mention", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        }
    }
}

extension UserInputPayload {
    var renderedText: String {
        switch self {
        case .text(let value):
            return value
        case .image(let url):
            return "Image: \(url)"
        case .localImage(let path):
            return "Local image: \(path)"
        case .skill(let name, _):
            return "Skill: \(name)"
        case .mention(let name, _):
            return "@\(name)"
        }
    }
}

struct AgentMessageItem: Decodable, Sendable {
    let id: String
    var text: String
    let phase: String?
}

struct UserMessageItem: Decodable, Sendable {
    let id: String
    let content: [UserInputPayload]
}

enum CommandExecutionStatus: String, Decodable, Sendable {
    case inProgress = "inProgress"
    case completed = "completed"
    case failed = "failed"
    case declined = "declined"
}

struct CommandExecutionItem: Decodable, Sendable {
    let id: String
    let command: String
    let cwd: String
    let status: CommandExecutionStatus
    let aggregatedOutput: String?
    let exitCode: Int?
}

enum PatchApplyStatus: String, Decodable, Sendable {
    case inProgress = "inProgress"
    case completed = "completed"
    case failed = "failed"
    case declined = "declined"
}

enum PatchChangeKind: Sendable {
    case add
    case delete
    case update(movePath: String?)
}

extension PatchChangeKind: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case movePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "add":
            self = .add
        case "delete":
            self = .delete
        case "update":
            self = .update(movePath: try container.decodeIfPresent(String.self, forKey: .movePath))
        default:
            self = .update(movePath: nil)
        }
    }
}

struct FileUpdateChange: Decodable, Sendable {
    let path: String
    let kind: PatchChangeKind
    let diff: String
}

struct FileChangeItem: Decodable, Sendable {
    let id: String
    let changes: [FileUpdateChange]
    let status: PatchApplyStatus
}

struct ReasoningItem: Decodable, Sendable {
    let id: String
    let summary: [String]
    let content: [String]
}

struct ReviewItem: Decodable, Sendable {
    let id: String
    let review: String
}

struct UnknownThreadItem: Sendable {
    let id: String
    let type: String
    let raw: JSONValue?
}

enum ThreadItem: Sendable {
    case userMessage(UserMessageItem)
    case agentMessage(AgentMessageItem)
    case commandExecution(CommandExecutionItem)
    case fileChange(FileChangeItem)
    case reasoning(ReasoningItem)
    case plan(id: String, text: String)
    case enteredReviewMode(ReviewItem)
    case exitedReviewMode(ReviewItem)
    case contextCompaction(id: String)
    case unknown(UnknownThreadItem)
}

extension ThreadItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case content
        case text
        case phase
        case command
        case cwd
        case status
        case aggregatedOutput
        case exitCode
        case changes
        case summary
        case review
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "userMessage":
            self = .userMessage(
                UserMessageItem(
                    id: try container.decode(String.self, forKey: .id),
                    content: try container.decode([UserInputPayload].self, forKey: .content)
                )
            )
        case "agentMessage":
            self = .agentMessage(
                AgentMessageItem(
                    id: try container.decode(String.self, forKey: .id),
                    text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                    phase: try container.decodeIfPresent(String.self, forKey: .phase)
                )
            )
        case "commandExecution":
            self = .commandExecution(try CommandExecutionItem(from: decoder))
        case "fileChange":
            self = .fileChange(try FileChangeItem(from: decoder))
        case "reasoning":
            self = .reasoning(try ReasoningItem(from: decoder))
        case "plan":
            self = .plan(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            )
        case "enteredReviewMode":
            self = .enteredReviewMode(
                ReviewItem(
                    id: try container.decode(String.self, forKey: .id),
                    review: try container.decode(String.self, forKey: .review)
                )
            )
        case "exitedReviewMode":
            self = .exitedReviewMode(
                ReviewItem(
                    id: try container.decode(String.self, forKey: .id),
                    review: try container.decode(String.self, forKey: .review)
                )
            )
        case "contextCompaction":
            self = .contextCompaction(id: try container.decode(String.self, forKey: .id))
        default:
            let raw = try? JSONValue(from: decoder)
            self = .unknown(
                UnknownThreadItem(
                    id: (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString,
                    type: type,
                    raw: raw
                )
            )
        }
    }
}

extension ThreadItem {
    var id: String {
        switch self {
        case .userMessage(let item):
            return item.id
        case .agentMessage(let item):
            return item.id
        case .commandExecution(let item):
            return item.id
        case .fileChange(let item):
            return item.id
        case .reasoning(let item):
            return item.id
        case .plan(let id, _):
            return id
        case .enteredReviewMode(let item):
            return item.id
        case .exitedReviewMode(let item):
            return item.id
        case .contextCompaction(let id):
            return id
        case .unknown(let item):
            return item.id
        }
    }
}

struct ThreadStartedNotification: Decodable, Sendable {
    let thread: CodexThread
}

struct ThreadStatusChangedNotification: Decodable, Sendable {
    let threadId: String
    let status: ThreadStatus
}

struct TokenUsageBreakdown: Decodable, Sendable {
    let totalTokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
}

struct ThreadTokenUsage: Decodable, Sendable {
    let total: TokenUsageBreakdown
    let last: TokenUsageBreakdown
    let modelContextWindow: Int?

    var contextUsagePercent: Double? {
        guard let modelContextWindow, modelContextWindow > 0 else {
            return nil
        }
        return min(max(Double(total.totalTokens) / Double(modelContextWindow), 0), 1)
    }
}

struct ThreadTokenUsageUpdatedNotification: Decodable, Sendable {
    let threadId: String
    let turnId: String
    let tokenUsage: ThreadTokenUsage
}

struct ThreadNameUpdatedNotification: Decodable, Sendable {
    let threadId: String
    let threadName: String?
}

struct ThreadArchivedNotification: Decodable, Sendable {
    let threadId: String
}

struct ThreadUnarchivedNotification: Decodable, Sendable {
    let threadId: String
}

struct TurnStartedNotification: Decodable, Sendable {
    let threadId: String
    let turn: CodexTurn
}

struct TurnCompletedNotification: Decodable, Sendable {
    let threadId: String
    let turn: CodexTurn
}

struct ItemStartedNotification: Decodable, Sendable {
    let item: ThreadItem
    let threadId: String
    let turnId: String
}

struct ItemCompletedNotification: Decodable, Sendable {
    let item: ThreadItem
    let threadId: String
    let turnId: String
}

struct AgentMessageDeltaNotification: Decodable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let delta: String
}

struct ServerRequestResolvedNotification: Decodable, Sendable {
    let threadId: String
    let requestId: RPCID
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?

    var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct GetAccountRateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

struct AccountRateLimitsUpdatedNotification: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot
}

struct NetworkApprovalContext: Decodable, Sendable {
    let host: String
    let `protocol`: String
}

struct CommandExecutionRequestApprovalParams: Decodable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let approvalId: String?
    let reason: String?
    let networkApprovalContext: NetworkApprovalContext?
    let command: String?
    let cwd: String?
}

enum CommandExecutionApprovalDecision: String, Encodable, Sendable {
    case accept = "accept"
    case acceptForSession = "acceptForSession"
    case decline = "decline"
    case cancel = "cancel"
}

struct CommandExecutionRequestApprovalResponse: Encodable, Sendable {
    let decision: CommandExecutionApprovalDecision
}

struct FileChangeRequestApprovalParams: Decodable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let reason: String?
    let grantRoot: String?
}

enum FileChangeApprovalDecision: String, Encodable, Sendable {
    case accept = "accept"
    case acceptForSession = "acceptForSession"
    case decline = "decline"
    case cancel = "cancel"
}

struct FileChangeRequestApprovalResponse: Encodable, Sendable {
    let decision: FileChangeApprovalDecision
}
