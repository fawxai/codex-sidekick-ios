import Observation
import SwiftUI

struct ThreadBrowserView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    @State private var compactThreadID: String?
    @State private var browserPreferences = ThreadBrowserPreferences()
    @State private var collapsedProjectIDs: Set<String> = []
    @State private var isPresentingNewThreadSheet = false

    private typealias ThreadCreationCandidate = (target: ThreadCreationTarget, updatedAt: TimeInterval)

    private var usesSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var visibleThreads: [CodexThread] {
        appModel.threads
            .filteredForThreadBrowser(show: browserPreferences.show, selectedThreadID: appModel.selectedThreadID)
            .sortedForThreadBrowser(by: browserPreferences.sort)
    }

    private var projectGroups: [ThreadFolderGroup] {
        appModel.threads.groupedForThreadBrowser(
            by: browserPreferences.sort,
            show: browserPreferences.show,
            selectedThreadID: appModel.selectedThreadID
        )
    }

    private var threadCreationTargets: [ThreadCreationTarget] {
        let groupedThreads = Dictionary(grouping: appModel.threads, by: \.cwd)
        let candidates: [ThreadCreationCandidate] = groupedThreads.compactMap { entry in
                let cwd = entry.key
                let threads = entry.value
                let trimmedPath = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPath.isEmpty else {
                    return nil
                }

                let latestThread = threads.max(by: { $0.updatedAt < $1.updatedAt })
                return (
                    target: ThreadCreationTarget(
                        id: cwd,
                        cwd: cwd,
                        title: ThreadProjectName.displayName(for: cwd),
                        subtitle: CodexDisplay.formatDirectoryDisplay(cwd)
                    ),
                    updatedAt: latestThread?.updatedAt ?? 0
                )
            }
        return candidates
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.target.title.localizedCaseInsensitiveCompare(rhs.target.title) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .map(\.target)
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
                await refreshThreadList()
            }
        }
        .onChange(of: appModel.selectedThreadID) { _, threadID in
            guard let threadID,
                  let groupID = appModel.threads.first(where: { $0.id == threadID })?.cwd else {
                return
            }
            collapsedProjectIDs.remove(groupID)
        }
        .sheet(isPresented: $isPresentingNewThreadSheet) {
            NewThreadSheet(
                creationTargets: threadCreationTargets,
                createThread: { cwd in
                    await createThread(cwd: cwd)
                }
            )
            .presentationCornerRadius(18)
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
                await refreshThreadList()
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
                    ThreadOrganizerMenu(
                        preferences: browserPreferences,
                        selectOrganization: { browserPreferences.organization = $0 },
                        selectSort: { sort in
                            browserPreferences.sort = sort
                            Task {
                                await refreshThreadList()
                            }
                        },
                        selectShow: { browserPreferences.show = $0 }
                    )
                    refreshToolbarButton
                    approvalsToolbarButton
                }
            }
        } content: {
            LazyVStack(alignment: .leading, spacing: 8) {
                connectionCard

                if let banner = appModel.banner {
                    BannerCard(message: banner.message, tone: banner.tone.statusTone)
                }

                threadOrganizerContent(
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
                    await refreshThreadList()
                }
            }
            .buttonStyle(SidekickActionButtonStyle(tone: .secondary))
        }
    }

    @ViewBuilder
    private func threadOrganizerContent(
        selectionHandler: @escaping (String) -> Void,
        navigationHandler: @escaping (String) -> Void
    ) -> some View {
        if visibleThreads.isEmpty {
            ThreadEmptyStateCard(
                title: emptyStateTitle,
                message: emptyStateMessage
            )
        } else if browserPreferences.organization == .byProject {
            ForEach(projectGroups) { group in
                ThreadProjectSectionView(
                    group: group,
                    selectedThreadID: appModel.selectedThreadID,
                    isCollapsed: collapsedProjectIDs.contains(group.id),
                    usesSplitLayout: usesSplitLayout,
                    selectThread: selectionHandler,
                    navigateToThread: navigationHandler,
                    toggleCollapsed: { toggleCollapsedGroup(group.id) },
                    createThreadInGroup: {
                        Task {
                            await createThread(cwd: group.path)
                        }
                    }
                )
            }
        } else {
            chronologicalThreadList(
                selectionHandler: selectionHandler,
                navigationHandler: navigationHandler
            )
        }
    }

    private func chronologicalThreadList(
        selectionHandler: @escaping (String) -> Void,
        navigationHandler: @escaping (String) -> Void
    ) -> some View {
        SurfaceCard(padding: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(browserPreferences.show == .all ? "Threads" : "Relevant threads")
                        .font(theme.codeFont(10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)

                    Spacer(minLength: 12)

                    Text("\(visibleThreads.count)")
                        .font(theme.codeFont(10))
                        .foregroundStyle(theme.textTertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                        if index > 0 {
                            Divider()
                                .overlay(theme.divider)
                                .padding(.leading, 10)
                        }

                        ThreadRowButton(
                            thread: thread,
                            isSelected: appModel.selectedThreadID == thread.id,
                            showsDirectory: true,
                            usesSplitLayout: usesSplitLayout,
                            selectThread: selectionHandler,
                            navigateToThread: navigationHandler
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private var refreshToolbarButton: some View {
        SidekickCircularToolbarButton(systemImage: "arrow.clockwise") {
            Task {
                if appModel.isConnected {
                    await refreshThreadList()
                } else {
                    await appModel.reconnect()
                    await refreshThreadList()
                }
            }
        }
    }

    private var newThreadButton: some View {
        Button {
            isPresentingNewThreadSheet = true
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
        .buttonStyle(.plain)
    }

    private var emptyStateTitle: String {
        if appModel.isConnecting {
            return "Connecting to Codex"
        }
        if browserPreferences.show == .relevant {
            return "No relevant threads"
        }
        return "No threads yet"
    }

    private var emptyStateMessage: String {
        if appModel.isConnecting {
            return "The sidekick is waiting for the host to finish pairing and send down the thread index."
        }
        if browserPreferences.show == .relevant {
            return "Switch Show back to All threads, or start working in a project to pull it back into the recent set."
        }
        return "Tap New Thread or start a thread in Codex desktop to populate this list."
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

    private func selectThread(_ threadID: String) {
        appModel.selectedThreadID = threadID
        collapsedProjectIDs.remove(appModel.threads.first(where: { $0.id == threadID })?.cwd ?? "")
        Task {
            await appModel.selectThread(threadID)
        }
    }

    private func openCompactThread(_ threadID: String) {
        selectThread(threadID)
        compactThreadID = threadID
    }

    private func refreshThreadList() async {
        await appModel.refreshThreads(
            using: AppModel.ThreadListContext(
                sortKey: browserPreferences.sort.apiSortKey,
                cwd: nil
            )
        )
    }

    private func toggleCollapsedGroup(_ groupID: String) {
        if collapsedProjectIDs.contains(groupID) {
            collapsedProjectIDs.remove(groupID)
        } else {
            collapsedProjectIDs.insert(groupID)
        }
    }

    private func createThread(cwd: String? = nil) async -> String? {
        let threadID = await appModel.createThread(cwd: cwd)
        guard let threadID else {
            return nil
        }

        if let cwd {
            collapsedProjectIDs.remove(cwd)
        }

        if usesSplitLayout == false {
            compactThreadID = threadID
        }
        return threadID
    }
}
