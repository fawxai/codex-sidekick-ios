import Observation
import SwiftUI

struct ThreadDetailView: View {
    @Environment(\.sidekickTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    let threadID: String
    let onBack: (() -> Void)?

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
                    topSpacing: 12,
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
                            .padding(.bottom, 6)
                    }
                    .background(theme.chrome.ignoresSafeArea(edges: .bottom))
                } content: {
                    VStack(alignment: .leading, spacing: 16) {
                        ThreadHeroCard(thread: thread)

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
        SidekickTopBar(title: thread.displayTitle) {
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
        } trailing: {
            HStack(spacing: 8) {
                Button("Open Live") {
                    Task {
                        await appModel.openSelectedThread()
                    }
                }
                .buttonStyle(SidekickActionButtonStyle(tone: .secondary))

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
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mobile Handoff")
                            .font(theme.codeFont(14, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("Send the next instruction into this live thread from iPhone.")
                            .font(theme.font(12))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer()

                    if appModel.pendingApprovals.isEmpty == false {
                        Button("Review \(appModel.pendingApprovals.count)") {
                            selectedSection = .approvals
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .warning))
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $appModel.handoffDraft)
                        .font(theme.codeFont(13))
                        .foregroundStyle(theme.textPrimary)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.chromeElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.border, lineWidth: 1)
                        )

                    if appModel.handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Tell Codex what to pick up next...")
                            .font(theme.codeFont(13))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 8) {
                    if thread?.status.isWaitingOnApproval == true {
                        StatusPill(text: "Approval Pending", tone: .warning)
                    }

                    Spacer()

                    Button("Send Handoff") {
                        Task {
                            await appModel.sendHandoff()
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .primary))
                    .disabled(appModel.handoffDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ThreadHeroCard: View {
    @Environment(\.sidekickTheme) private var theme

    let thread: CodexThread

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.displayTitle)
                            .font(theme.codeFont(22, weight: .bold))
                            .foregroundStyle(theme.textPrimary)

                        if let agentNickname = thread.agentNickname, !agentNickname.isEmpty {
                            Text("Agent: \(agentNickname)")
                                .font(theme.codeFont(11))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(thread.preview.isEmpty ? "No thread preview stored yet." : thread.preview)
                            .font(theme.font(13))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(text: thread.status.label, tone: tone(for: thread.status))
                }

                HStack(spacing: 6) {
                    StatusPill(text: thread.modelProvider.uppercased(), tone: .neutral)
                    StatusPill(text: thread.directoryDisplay, tone: .neutral)
                    if thread.status.isWaitingOnApproval {
                        StatusPill(text: "Approval Pending", tone: .warning)
                    }
                }

                VStack(spacing: 8) {
                    DotStatusRow(
                        title: "Created",
                        value: thread.createdDate.formatted(date: .abbreviated, time: .shortened),
                        tone: .neutral
                    )
                    DotStatusRow(
                        title: "Updated",
                        value: thread.updatedDate.formatted(date: .abbreviated, time: .shortened),
                        tone: .neutral
                    )
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
