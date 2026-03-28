import Observation
import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @Environment(\.sidekickTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    let threadID: String
    let onBack: (() -> Void)?

    @FocusState private var isComposerFocused: Bool
    @State private var composerUtilityNote: String?
    @State private var composerUtilityNoteTask: Task<Void, Never>?
    @State private var isPlanModeEnabled = false

    init(
        appModel: AppModel,
        selectedSection: Binding<SidekickSection>,
        threadID: String,
        onBack: (() -> Void)? = nil
    ) {
        self.appModel = appModel
        self._selectedSection = selectedSection
        self.threadID = threadID
        self.onBack = onBack
    }

    private var thread: CodexThread? {
        appModel.threadDetails[threadID] ?? appModel.threads.first(where: { $0.id == threadID })
    }

    private var detailBottomAnchorID: String {
        "thread-detail-\(threadID)-bottom"
    }

    private var canSendHandoff: Bool {
        appModel.handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var composerModelLabel: String {
        if let modelName = normalizedModelLabel(appModel.hostModelName) {
            return modelName
        }
        return normalizedModelLabel(thread?.modelProvider) ?? "Codex"
    }

    private var composerReasoningLabel: String {
        normalizedReasoningLabel(appModel.hostReasoningEffortName) ?? "Default"
    }

    private var composerModelOptions: [ComposerModelOption] {
        let currentSlug = appModel.hostModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentSlug,
              !currentSlug.isEmpty,
              ComposerModelOption.defaultCatalog.contains(where: { $0.slug == currentSlug }) == false else {
            return ComposerModelOption.defaultCatalog
        }

        return [
            ComposerModelOption(
                id: currentSlug,
                slug: currentSlug,
                title: normalizedModelLabel(currentSlug) ?? currentSlug,
                detail: "Current host model."
            )
        ] + ComposerModelOption.defaultCatalog
    }

    private var selectedReasoningOption: ComposerReasoningOption? {
        ComposerReasoningOption(rawValue: appModel.hostReasoningEffortName?.lowercased() ?? "")
    }

    private var permissionPreset: AppModel.PermissionPreset {
        appModel.hostPermissionPreset
    }

    private var permissionTone: StatusTone {
        switch permissionPreset {
        case .defaultPermissions:
            return .neutral
        case .fullAccess:
            return .warning
        case .customConfig:
            return .neutral
        }
    }

    private var branchLabel: String {
        normalizedBranchLabel(thread?.gitInfo?.branch) ?? "No branch"
    }

    private var threadContextUsage: ThreadTokenUsage? {
        appModel.threadTokenUsage(for: threadID)
    }

    private var contextMeterProgress: Double? {
        threadContextUsage?.contextUsagePercent
    }

    private var contextMeterTone: StatusTone {
        guard let progress = contextMeterProgress else {
            return .neutral
        }

        if progress >= 0.9 {
            return .danger
        }
        if progress >= 0.75 {
            return .warning
        }
        return .neutral
    }

    private var timelineScrollToken: String {
        guard let thread else {
            return "\(threadID)-unloaded"
        }

        let lastTurnID = thread.turns.last?.id ?? "no-turn"
        let lastItemID = thread.turns.last?.items.last?.id ?? "no-item"
        let lastStatus = thread.turns.last?.status.rawValue ?? "idle"
        return "\(threadID)-\(thread.turns.count)-\(lastTurnID)-\(lastItemID)-\(lastStatus)"
    }

    var body: some View {
        Group {
            if let thread {
                SidekickScrollScreen(
                    topSpacing: 8,
                    bottomSpacing: 6,
                    scrollTargetID: detailBottomAnchorID,
                    scrollTargetToken: timelineScrollToken,
                    scrollTargetAnchor: .bottom
                ) {
                    detailTopBar(thread: thread)
                } bottomBar: {
                    VStack(spacing: 0) {
                        handoffComposer
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        composerFooterBar
                            .padding(.horizontal, 18)
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 16) {
                        ThreadSummaryCard(
                            thread: thread,
                            modelName: composerModelLabel,
                            reasoningEffortName: composerReasoningLabel
                        )

                        if let bannerMessage = appModel.bannerMessage {
                            BannerCard(message: bannerMessage, tone: .neutral)
                        }

                        ThreadTimelineView(thread: thread)

                        Color.clear
                            .frame(height: 1)
                            .id(detailBottomAnchorID)
                    }
                }
                .id(threadID)
            } else {
                ThreadEmptyStateCard(
                    title: "Loading thread",
                    message: "The sidekick is fetching the latest detail for this thread."
                )
                .padding(24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: threadID) {
            await appModel.selectThread(threadID)
        }
    }

    @ViewBuilder
    private func detailTopBar(thread: CodexThread) -> some View {
        SidekickTopBar {
            HStack(spacing: 10) {
                if horizontalSizeClass == .regular {
                    Color.clear
                        .frame(width: 36, height: 36)
                } else {
                    SidekickCircularToolbarButton(systemImage: "chevron.left") {
                        if let onBack {
                            onBack()
                        } else {
                            dismiss()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.displayTitle)
                        .font(theme.codeFont(12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Text(thread.subtitle)
                        .font(theme.codeFont(9))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                SidekickCircularToolbarButton(systemImage: "play.fill") {
                    Task {
                        await appModel.openSelectedThread()
                    }
                }

                SidekickCircularToolbarButton(
                    systemImage: appModel.pendingApprovals.isEmpty ? "checklist" : "exclamationmark.shield.fill",
                    tint: appModel.pendingApprovals.isEmpty ? nil : theme.warning
                ) {
                    selectedSection = .approvals
                }
            }
        }
    }

    private var handoffComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "",
                text: $appModel.handoffDraft,
                prompt: Text("Tell Codex what to pick up next...")
                    .foregroundStyle(theme.textTertiary),
                axis: .vertical
            )
            .font(theme.codeFont(13))
            .foregroundStyle(theme.textPrimary)
            .textFieldStyle(.plain)
            .lineLimit(1 ... 3)
            .focused($isComposerFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()
                .overlay(theme.divider)

            if let composerUtilityNote, !composerUtilityNote.isEmpty {
                Text(composerUtilityNote)
                    .font(theme.codeFont(10))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Menu {
                    Button("Paste from Clipboard", action: pasteFromClipboard)

                    Button("Add photos & files") {
                        showComposerUtilityNote("Remote photo and file attachments are not wired through the host protocol yet.")
                    }

                    Toggle("Plan mode", isOn: $isPlanModeEnabled)

                    Menu("Speed") {
                        ComposerReasoningMenuContent(
                            selected: selectedReasoningOption,
                            select: selectReasoningOption
                        )
                    }

                    Menu("Plugins") {
                        Button("Plugin mentions are not wired on iPhone yet.") {
                            showComposerUtilityNote("Plugin mentions from the iPhone composer are not wired yet.")
                        }
                    }

                    if canSendHandoff {
                        Button("Clear Draft", role: .destructive) {
                            appModel.handoffDraft = ""
                        }
                    }
                } label: {
                    composerIconButton(systemImage: "plus")
                }
                .buttonStyle(.plain)

                Menu {
                    ComposerModelMenuContent(
                        options: composerModelOptions,
                        selectedSlug: appModel.hostModelName,
                        select: selectModelOption
                    )
                } label: {
                    ComposerMenuChip(text: composerModelLabel)
                }
                .buttonStyle(.plain)

                Menu {
                    ComposerReasoningMenuContent(
                        selected: selectedReasoningOption,
                        select: selectReasoningOption
                    )
                } label: {
                    ComposerMenuChip(text: composerReasoningLabel)
                }
                .buttonStyle(.plain)

                if isPlanModeEnabled {
                    ComposerStateChip(text: "Plan", icon: "list.bullet", tone: .neutral)
                }

                if thread?.status.isWaitingOnApproval == true {
                    ComposerStateChip(text: "Approval", tone: .warning)
                }

                if appModel.pendingApprovals.isEmpty == false {
                    Button {
                        selectedSection = .approvals
                    } label: {
                        ComposerStateChip(
                            text: "Review \(appModel.pendingApprovals.count)",
                            icon: "checklist"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    isComposerFocused = true
                    showComposerUtilityNote("Use the keyboard's dictation button after focusing the composer.")
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await appModel.sendHandoff(input: handoffInputPayloads())
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSendHandoff ? sendButtonForeground : theme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(canSendHandoff ? sendButtonBackground : theme.chromeElevated)
                        )
                        .overlay(
                            Circle()
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(canSendHandoff == false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.backgroundTop.opacity(theme.colorScheme == .dark ? 0.94 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: theme.shadow.opacity(0.35), radius: 10, y: 2)
    }

    private var composerFooterBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Menu {
                Section("Continue in") {
                    Button {} label: {
                        Label("Local project", systemImage: "checkmark")
                    }
                    .disabled(true)

                    Button {
                        showComposerUtilityNote("Connecting Codex web from iPhone is not wired yet.")
                    } label: {
                        Label("Connect Codex web", systemImage: "arrow.up.right.square")
                    }

                    Button("Send to cloud") {}
                        .disabled(true)
                }

                Menu("Rate limits remaining") {
                    rateLimitMenuContent
                }
            } label: {
                ComposerFooterMenuLabel(
                    text: "Local",
                    icon: "laptopcomputer"
                )
            }
            .buttonStyle(.plain)

            Menu {
                Section {
                    Button {
                        Task {
                            await appModel.setHostPermissionPreset(.defaultPermissions)
                        }
                    } label: {
                        permissionMenuLabel("Default permissions", preset: .defaultPermissions)
                    }

                    Button {
                        Task {
                            await appModel.setHostPermissionPreset(.fullAccess)
                        }
                    } label: {
                        permissionMenuLabel("Full access", preset: .fullAccess)
                    }

                    Button {
                        showComposerUtilityNote("Custom permission profiles still live in the paired host's config.toml.")
                    } label: {
                        permissionMenuLabel("Custom (config.toml)", preset: .customConfig)
                    }
                }
            } label: {
                ComposerFooterMenuLabel(
                    text: permissionPreset.label,
                    icon: "exclamationmark.circle",
                    tone: permissionTone
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Menu {
                Section("Branches") {
                    Button {} label: {
                        Label(branchLabel, systemImage: "checkmark")
                    }
                    .disabled(true)

                    Button("Refresh branch from host") {
                        Task {
                            await appModel.readThread(threadID, force: true)
                        }
                    }

                    Button("Create and checkout new branch") {
                        showComposerUtilityNote("Branch creation and checkout still belong on the paired host.")
                    }
                }

                Section {
                    Button {
                        showComposerUtilityNote("Branch switching from iPhone is not wired yet.")
                    } label: {
                        Text("Switch branches on host")
                    }
                }
            } label: {
                ComposerFooterMenuLabel(
                    text: branchLabel,
                    icon: "point.3.connected.trianglepath.dotted"
                )
            }
            .buttonStyle(.plain)

            Menu {
                contextMeterMenuContent
            } label: {
                ComposerContextMeterLabel(
                    progress: contextMeterProgress,
                    tone: contextMeterTone
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var rateLimitMenuContent: some View {
        if let primary = appModel.accountRateLimits?.primary {
            Section("Primary window") {
                disabledMenuInfoRow("\(primary.remainingPercent)% remaining")
                if let resetDate = dateString(fromUnixSeconds: primary.resetsAt) {
                    disabledMenuInfoRow("Resets \(resetDate)")
                }
                if let windowDurationMins = primary.windowDurationMins {
                    disabledMenuInfoRow("\(windowDurationMins) minute window")
                }
            }
        } else {
            disabledMenuInfoRow("Rate-limit telemetry is not available from the host yet.")
        }

        if let secondary = appModel.accountRateLimits?.secondary {
            Section("Secondary window") {
                disabledMenuInfoRow("\(secondary.remainingPercent)% remaining")
                if let resetDate = dateString(fromUnixSeconds: secondary.resetsAt) {
                    disabledMenuInfoRow("Resets \(resetDate)")
                }
            }
        }
    }

    @ViewBuilder
    private var contextMeterMenuContent: some View {
        if let usage = threadContextUsage {
            Section("Context usage") {
                if let progress = usage.contextUsagePercent {
                    disabledMenuInfoRow("\(Int((progress * 100).rounded()))% of the context window used")
                }
                if let contextWindow = usage.modelContextWindow {
                    disabledMenuInfoRow("\(usage.total.totalTokens.formatted()) / \(contextWindow.formatted()) tokens")
                } else {
                    disabledMenuInfoRow("\(usage.total.totalTokens.formatted()) tokens used")
                }
                disabledMenuInfoRow("Last turn: \(usage.last.totalTokens.formatted()) tokens")
            }
        } else {
            Section("Context usage") {
                disabledMenuInfoRow("Context usage appears once the host streams token telemetry for this thread.")
            }
        }

        if let primary = appModel.accountRateLimits?.primary {
            Section("Account quota") {
                disabledMenuInfoRow("\(primary.remainingPercent)% remaining in the current window")
            }
        }
    }

    private func composerIconButton(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }

    private var sendButtonBackground: Color {
        if theme.colorScheme == .light {
            return theme.chrome
        }
        return theme.textPrimary
    }

    private var sendButtonForeground: Color {
        if theme.colorScheme == .light {
            return theme.textPrimary
        }
        return theme.backgroundBottom
    }

    private func pasteFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            return
        }

        if canSendHandoff {
            appModel.handoffDraft += "\n\(clipboardText)"
        } else {
            appModel.handoffDraft = clipboardText
        }
    }

    private func handoffInputPayloads() -> [UserInputPayload] {
        let text = appModel.handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return []
        }

        if isPlanModeEnabled {
            return [
                .text("Plan mode is enabled. Start with a concise step-by-step plan before taking action."),
                .text(text)
            ]
        }

        return [.text(text)]
    }

    private func selectModelOption(_ option: ComposerModelOption) {
        Task {
            await appModel.setHostModel(option.slug)
        }
    }

    private func selectReasoningOption(_ option: ComposerReasoningOption) {
        Task {
            await appModel.setHostReasoningEffort(option.rawValue)
        }
    }

    private func showComposerUtilityNote(_ message: String) {
        composerUtilityNoteTask?.cancel()
        composerUtilityNote = message
        composerUtilityNoteTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                composerUtilityNote = nil
            }
        }
    }

    private func normalizedModelLabel(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if trimmedValue.hasPrefix("gpt-") {
            return "GPT-\(trimmedValue.dropFirst(4))"
        }
        if trimmedValue.lowercased() == "openai" {
            return "OpenAI"
        }
        return trimmedValue
    }

    private func normalizedReasoningLabel(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if trimmedValue.lowercased() == "xhigh" {
            return "Extra High"
        }

        return trimmedValue
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func normalizedBranchLabel(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    @ViewBuilder
    private func permissionMenuLabel(_ text: String, preset: AppModel.PermissionPreset) -> some View {
        if permissionPreset == preset {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    @ViewBuilder
    private func disabledMenuInfoRow(_ text: String) -> some View {
        Button {} label: {
            Text(text)
        }
        .disabled(true)
    }

    private func dateString(fromUnixSeconds timestamp: Int?) -> String? {
        guard let timestamp else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .omitted, time: .shortened)
    }
}

struct ThreadSummaryCard: View {
    @Environment(\.sidekickTheme) private var theme

    let thread: CodexThread
    let modelName: String?
    let reasoningEffortName: String?

    var body: some View {
        SurfaceCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    StatusPill(text: thread.status.label, tone: tone(for: thread.status))
                    if let modelName {
                        StatusPill(text: modelName, tone: .neutral)
                    }
                    if let reasoningEffortName {
                        StatusPill(text: reasoningEffortName, tone: .neutral)
                    }
                    if thread.status.isWaitingOnApproval {
                        StatusPill(text: "Approval Pending", tone: .warning)
                    }

                    Spacer(minLength: 8)

                    Text(thread.updatedDate.formatted(date: .omitted, time: .shortened))
                        .font(theme.codeFont(10))
                        .foregroundStyle(theme.textTertiary)
                }

                if thread.preview.isEmpty == false && thread.preview != thread.displayTitle {
                    Text(thread.preview)
                        .font(theme.font(12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 10) {
                    Label(thread.directoryDisplay, systemImage: "folder")
                        .font(theme.codeFont(10))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("Created \(thread.createdDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(theme.codeFont(10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func tone(for status: ThreadStatus) -> StatusTone {
        switch status {
        case .notLoaded, .idle:
            return .neutral
        case .systemError:
            return .danger
        case .active(let flags):
            return flags.contains(.waitingOnApproval) ? .warning : .success
        }
    }
}

struct ThreadEmptyStateCard: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String
    let message: String

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(theme.codeFont(18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text(message)
                    .font(theme.font(13))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

struct BannerCard: View {
    @Environment(\.sidekickTheme) private var theme

    let message: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(toneColor)
                .frame(width: 7, height: 7)

            Text(message)
                .font(theme.codeFont(12, weight: .medium))
                .foregroundStyle(theme.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.panelMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(toneColor.opacity(0.26), lineWidth: 1)
        )
    }

    private var toneColor: Color {
        switch tone {
        case .neutral:
            theme.textTertiary
        case .accent:
            theme.accent
        case .success:
            theme.success
        case .warning:
            theme.warning
        case .danger:
            theme.danger
        }
    }
}
