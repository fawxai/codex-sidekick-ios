import Observation
import SwiftUI

struct ThreadBrowserView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    @State private var compactThreadID: String?

    private var usesSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                splitLayout
            } else {
                stackLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            if appModel.threads.isEmpty {
                await appModel.refreshThreads()
            }
        }
    }

    private var stackLayout: some View {
        Group {
            if let compactThreadID {
                ThreadDetailView(
                    appModel: appModel,
                    selectedSection: $selectedSection,
                    threadID: compactThreadID,
                    onBack: { self.compactThreadID = nil }
                )
            } else {
                threadListScreen
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            threadSidebar
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            NavigationStack {
                if let selectedThreadID = appModel.selectedThreadID {
                    ThreadDetailView(
                        appModel: appModel,
                        selectedSection: $selectedSection,
                        threadID: selectedThreadID
                    )
                } else {
                    ThreadEmptyStateCard(
                        title: "Pick a thread",
                        message: "Select a thread to inspect its rollout, resume it live, or hand off the next step from iPhone."
                    )
                    .padding(24)
                    .navigationTitle("Thread")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var threadListScreen: some View {
        threadListSurface { threadID in
            openCompactThread(threadID)
        }
    }

    private var threadSidebar: some View {
        threadListSurface { _ in }
    }

    private func threadListSurface(
        navigationHandler: @escaping (String) -> Void
    ) -> some View {
        SidekickScrollScreen(
            topSpacing: 6,
            bottomSpacing: 88,
            onRefresh: {
                await appModel.refreshThreads()
            }
        ) {
            SidekickTopBar {
                SidekickSectionMenuButton(
                    selectedSection: .threads,
                    pendingApprovalCount: appModel.pendingApprovals.count,
                    selectSection: { selectedSection = $0 }
                )
            } trailing: {
                HStack(spacing: 10) {
                    refreshToolbarButton
                    approvalsToolbarButton
                }
            }
        } content: {
            LazyVStack(alignment: .leading, spacing: 8) {
                connectionCard

                if let bannerMessage = appModel.bannerMessage {
                    BannerCard(message: bannerMessage, tone: bannerTone)
                }

                threadCards(
                    selectionHandler: selectThread,
                    navigationHandler: navigationHandler
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            newThreadButton
                .padding(.trailing, 16)
                .padding(.bottom, 20)
        }
    }

    private var connectionCard: some View {
        SurfaceCard(padding: usesSplitLayout ? 12 : 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paired host")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)

                        Text(appModel.pairedHostLabel)
                            .font(theme.codeFont(17, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text(appModel.pairedConnection?.websocketURL ?? "No paired host")
                            .font(theme.codeFont(10))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    StatusPill(text: statusLabel, tone: statusTone)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        connectionMetadata
                        Spacer(minLength: 0)
                        reconnectButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        connectionMetadata
                        reconnectButton
                    }
                }
            }
        }
    }

    private var connectionMetadata: some View {
        HStack(spacing: 6) {
            StatusPill(text: "\(appModel.threads.count) threads", tone: .neutral)

            if appModel.pendingApprovals.isEmpty == false {
                StatusPill(
                    text: "\(appModel.pendingApprovals.count) approvals",
                    tone: .warning
                )
            }

            if let themeName = appModel.hostAppearance.themeName, !themeName.isEmpty {
                StatusPill(text: themeName, tone: .neutral)
            }
        }
    }

    @ViewBuilder
    private var reconnectButton: some View {
        if appModel.connectionState != .connected {
            Button("Reconnect") {
                Task {
                    await appModel.reconnect()
                }
            }
            .buttonStyle(SidekickActionButtonStyle(tone: .secondary))
        }
    }

    private var refreshToolbarButton: some View {
        SidekickCircularToolbarButton(systemImage: "arrow.clockwise") {
            Task {
                if appModel.isConnected {
                    await appModel.refreshThreads()
                } else {
                    await appModel.reconnect()
                }
            }
        }
    }

    @ViewBuilder
    private func threadCards(
        selectionHandler: @escaping (String) -> Void,
        navigationHandler: @escaping (String) -> Void
    ) -> some View {
        if appModel.threads.isEmpty {
            ThreadEmptyStateCard(
                title: appModel.isConnecting ? "Connecting to Codex" : "No threads yet",
                message: appModel.isConnecting
                    ? "The sidekick is waiting for the host to finish pairing and send down the thread index."
                    : "Tap New Thread or start a thread in Codex desktop to populate this list."
            )
        } else {
            SurfaceCard(padding: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Recent threads")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)

                        Spacer(minLength: 12)

                        Text("\(appModel.threads.count) synced")
                            .font(theme.codeFont(10))
                            .foregroundStyle(theme.textTertiary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(appModel.threads.enumerated()), id: \.element.id) { index, thread in
                            if index > 0 {
                                Divider()
                                    .overlay(theme.divider)
                                    .padding(.leading, 10)
                            }

                            if usesSplitLayout {
                                Button {
                                    selectionHandler(thread.id)
                                } label: {
                                    ThreadRowCard(
                                        thread: thread,
                                        isSelected: appModel.selectedThreadID == thread.id
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    navigationHandler(thread.id)
                                } label: {
                                    ThreadRowCard(
                                        thread: thread,
                                        isSelected: appModel.selectedThreadID == thread.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private var newThreadButton: some View {
        Button {
            Task {
                await createThread()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))

                Text("New Thread")
                    .font(theme.codeFont(12, weight: .semibold))
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .shadow(color: theme.shadow, radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(appModel.isConnected == false)
    }

    private var approvalsToolbarButton: some View {
        Button {
            selectedSection = .approvals
        } label: {
            Image(systemName: appModel.pendingApprovals.isEmpty ? "shield" : "exclamationmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appModel.pendingApprovals.isEmpty ? theme.textPrimary : theme.warning)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.chromeElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if appModel.pendingApprovals.isEmpty == false {
                        Text("\(appModel.pendingApprovals.count)")
                            .font(theme.codeFont(10, weight: .bold))
                            .foregroundStyle(theme.backgroundBottom)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(theme.warning)
                            )
                            .offset(x: 4, y: -3)
                    }
                }
        }
    }

    private var statusLabel: String {
        switch appModel.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Offline"
        case .failed:
            return "Needs Attention"
        }
    }

    private var statusTone: StatusTone {
        switch appModel.connectionState {
        case .connected:
            return .success
        case .connecting:
            return .accent
        case .disconnected:
            return .neutral
        case .failed:
            return .danger
        }
    }

    private var bannerTone: StatusTone {
        guard let bannerMessage = appModel.bannerMessage else {
            return statusTone
        }

        if bannerMessage.hasPrefix("Approval waiting") {
            return .warning
        }

        if bannerMessage == "Connection closed" || bannerMessage.hasPrefix("Could not") {
            return .danger
        }

        return statusTone
    }

    private func selectThread(_ threadID: String) {
        appModel.selectedThreadID = threadID
        Task {
            await appModel.selectThread(threadID)
        }
    }

    private func openCompactThread(_ threadID: String) {
        selectThread(threadID)
        compactThreadID = threadID
    }

    private func createThread() async {
        guard let threadID = await appModel.createThread() else {
            return
        }

        if usesSplitLayout == false {
            compactThreadID = threadID
        }
    }
}

private struct ThreadRowCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sidekickTheme) private var theme

    let thread: CodexThread
    let isSelected: Bool

    private var usesCompactLayout: Bool {
        horizontalSizeClass != .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 5 : 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: usesCompactLayout ? 2 : 3) {
                    Text(thread.displayTitle)
                        .font(theme.codeFont(usesCompactLayout ? 13 : 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)

                    Text(thread.preview.isEmpty ? "No preview yet" : thread.preview)
                        .font(theme.font(11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(usesCompactLayout ? 1 : 2)
                }

                Spacer(minLength: 0)

                Text(thread.updatedDate, style: .relative)
                    .font(theme.codeFont(10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Label(thread.subtitle, systemImage: "folder")
                    .lineLimit(1)

                Spacer(minLength: 10)

                StatusPill(text: thread.status.label, tone: tone(for: thread.status))
            }
            .font(theme.codeFont(10))
            .foregroundStyle(theme.textTertiary)
        }
        .padding(usesCompactLayout ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.selection)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.accent.opacity(0.34), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
