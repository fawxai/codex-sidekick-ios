import Foundation
import SwiftUI

enum ThreadOrganizerMode: String {
    case byProject
    case chronological

    var title: String {
        switch self {
        case .byProject:
            return "By project"
        case .chronological:
            return "Chronological list"
        }
    }
}

enum ThreadOrganizerSort: String {
    case created
    case updated

    var title: String {
        switch self {
        case .created:
            return "Created"
        case .updated:
            return "Updated"
        }
    }

    var apiSortKey: ThreadSortKey {
        switch self {
        case .created:
            return .createdAt
        case .updated:
            return .updatedAt
        }
    }

    func timestamp(for thread: CodexThread) -> TimeInterval {
        switch self {
        case .created:
            return thread.createdAt
        case .updated:
            return thread.updatedAt
        }
    }
}

enum ThreadOrganizerShow: String {
    case all
    case relevant

    var title: String {
        switch self {
        case .all:
            return "All threads"
        case .relevant:
            return "Relevant"
        }
    }
}

struct ThreadBrowserPreferences {
    var organization: ThreadOrganizerMode = .byProject
    var sort: ThreadOrganizerSort = .updated
    var show: ThreadOrganizerShow = .relevant
}

struct ThreadFolderGroup: Identifiable {
    let id: String
    let label: String
    let path: String
    let pathDisplay: String
    let showsPath: Bool
    let threads: [CodexThread]
}

struct ThreadCreationTarget: Identifiable, Hashable {
    let id: String
    let cwd: String?
    let title: String
    let subtitle: String?
}

enum ThreadProjectName {
    private static let maxDisplayWords = 3

    static func displayName(for path: String, preferredName: String? = nil) -> String {
        if let preferredName {
            let trimmedName = collapseWords(preferredName)
            if !trimmedName.isEmpty {
                return trimmedName
            }
        }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return "No workspace"
        }

        let pathComponents = trimmedPath
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .map(String.init)
        let fallback = pathComponents.last ?? trimmedPath
        let collapsed = collapseWords(fallback)
        return collapsed.isEmpty ? fallback : collapsed
    }

    private static func collapseWords(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count > maxDisplayWords else {
            return trimmed
        }
        return words.prefix(maxDisplayWords).joined(separator: " ")
    }
}

extension CodexThread {
    var needsAttention: Bool {
        switch status {
        case .systemError:
            return true
        case .active(let flags):
            return flags.contains(.waitingOnApproval) || flags.contains(.waitingOnUserInput)
        case .notLoaded, .idle:
            return false
        }
    }

    func isRelevant(referenceDate: Date = .now) -> Bool {
        if needsAttention {
            return true
        }

        if case .active = status {
            return true
        }

        guard let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) else {
            return true
        }
        return updatedDate >= recentCutoff
    }

    var projectGroupName: String {
        ThreadProjectName.displayName(for: cwd)
    }
}

extension Array where Element == CodexThread {
    func filteredForThreadBrowser(
        show: ThreadOrganizerShow,
        selectedThreadID: String?
    ) -> [CodexThread] {
        switch show {
        case .all:
            return self
        case .relevant:
            return filter { thread in
                thread.isRelevant() || thread.id == selectedThreadID
            }
        }
    }

    func sortedForThreadBrowser(by sort: ThreadOrganizerSort) -> [CodexThread] {
        sorted { lhs, rhs in
            let lhsTimestamp = sort.timestamp(for: lhs)
            let rhsTimestamp = sort.timestamp(for: rhs)
            if lhsTimestamp == rhsTimestamp {
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
            return lhsTimestamp > rhsTimestamp
        }
    }

    func groupedForThreadBrowser(
        by sort: ThreadOrganizerSort,
        show: ThreadOrganizerShow,
        selectedThreadID: String?
    ) -> [ThreadFolderGroup] {
        let filteredThreads = filteredForThreadBrowser(show: show, selectedThreadID: selectedThreadID)
        let groupedThreads = Dictionary(grouping: filteredThreads, by: \.cwd)
        let groupLabels = groupedThreads.keys.map { ThreadProjectName.displayName(for: $0) }
        let labelCounts = Dictionary(grouping: groupLabels, by: { $0 }).mapValues(\.count)

        return groupedThreads.compactMap { cwd, threads in
            let label = ThreadProjectName.displayName(for: cwd)
            let sortedThreads = threads.sortedForThreadBrowser(by: sort)
            guard sortedThreads.isEmpty == false else {
                return nil
            }
            return ThreadFolderGroup(
                id: cwd,
                label: label,
                path: cwd,
                pathDisplay: CodexDisplay.formatDirectoryDisplay(cwd),
                showsPath: (labelCounts[label] ?? 0) > 1,
                threads: sortedThreads
            )
        }
        .sorted { lhs, rhs in
            guard let lhsThread = lhs.threads.first, let rhsThread = rhs.threads.first else {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            let lhsTimestamp = sort.timestamp(for: lhsThread)
            let rhsTimestamp = sort.timestamp(for: rhsThread)
            if lhsTimestamp == rhsTimestamp {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhsTimestamp > rhsTimestamp
        }
    }
}

struct ThreadOrganizerMenu: View {
    @Environment(\.sidekickTheme) private var theme

    let preferences: ThreadBrowserPreferences
    let selectOrganization: (ThreadOrganizerMode) -> Void
    let selectSort: (ThreadOrganizerSort) -> Void
    let selectShow: (ThreadOrganizerShow) -> Void

    var body: some View {
        Menu {
            Section("Organize") {
                organizerButton("By project", isSelected: preferences.organization == .byProject) {
                    selectOrganization(.byProject)
                }
                organizerButton("Chronological list", isSelected: preferences.organization == .chronological) {
                    selectOrganization(.chronological)
                }
            }

            Section("Sort by") {
                organizerButton("Created", isSelected: preferences.sort == .created) {
                    selectSort(.created)
                }
                organizerButton("Updated", isSelected: preferences.sort == .updated) {
                    selectSort(.updated)
                }
            }

            Section("Show") {
                organizerButton("All threads", isSelected: preferences.show == .all) {
                    selectShow(.all)
                }
                organizerButton("Relevant", isSelected: preferences.show == .relevant) {
                    selectShow(.relevant)
                }
            }
        } label: {
            ThreadToolbarMenuLabel(systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(theme.textPrimary)
    }

    private func organizerButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ThreadOrganizerSelectionLabel(title: title, isSelected: isSelected)
        }
    }
}

private struct ThreadToolbarMenuLabel: View {
    @Environment(\.sidekickTheme) private var theme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

private struct ThreadOrganizerSelectionLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)

            Spacer(minLength: 16)

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

struct ThreadProjectSectionView: View {
    @Environment(\.sidekickTheme) private var theme

    let group: ThreadFolderGroup
    let selectedThreadID: String?
    let isCollapsed: Bool
    let usesSplitLayout: Bool
    let selectThread: (String) -> Void
    let navigateToThread: (String) -> Void
    let toggleCollapsed: () -> Void
    let createThreadInGroup: () -> Void

    private var showsSecondaryPath: Bool {
        group.showsPath && isCollapsed == false
    }

    var body: some View {
        SurfaceCard(padding: 6) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if isCollapsed == false {
                    VStack(spacing: 0) {
                        ForEach(Array(group.threads.enumerated()), id: \.element.id) { index, thread in
                            if index > 0 {
                                Divider()
                                    .overlay(theme.divider)
                                    .padding(.leading, 12)
                            }

                            threadRow(thread)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleCollapsed) {
                VStack(alignment: .leading, spacing: showsSecondaryPath ? 4 : 0) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 8, height: 16)

                        Image(systemName: isCollapsed ? "folder" : "folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 14, height: 16)

                        Text(group.label)
                            .font(theme.codeFont(12, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Spacer(minLength: 8)

                        Text("\(group.threads.count)")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }

                    if showsSecondaryPath {
                        Text(group.pathDisplay)
                            .font(theme.codeFont(10))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, 30)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isCollapsed ? 6 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: createThreadInGroup) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(theme.chromeElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func threadRow(_ thread: CodexThread) -> some View {
        ThreadRowButton(
            thread: thread,
            isSelected: selectedThreadID == thread.id,
            showsDirectory: false,
            usesSplitLayout: usesSplitLayout,
            selectThread: selectThread,
            navigateToThread: navigateToThread
        )
    }
}

struct ThreadRowButton: View {
    let thread: CodexThread
    let isSelected: Bool
    let showsDirectory: Bool
    let usesSplitLayout: Bool
    let selectThread: (String) -> Void
    let navigateToThread: (String) -> Void

    var body: some View {
        Button(action: buttonAction) {
            ThreadRowCard(
                thread: thread,
                isSelected: isSelected,
                showsDirectory: showsDirectory
            )
        }
        .buttonStyle(.plain)
    }

    private func buttonAction() {
        if usesSplitLayout {
            selectThread(thread.id)
        } else {
            navigateToThread(thread.id)
        }
    }
}

struct ThreadRowCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sidekickTheme) private var theme

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    let thread: CodexThread
    let isSelected: Bool
    let showsDirectory: Bool

    private var usesCompactLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var previewText: String? {
        let trimmed = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != thread.displayTitle else {
            return nil
        }
        return trimmed
    }

    private var metadataLabel: (systemImage: String, text: String)? {
        if showsDirectory {
            return ("folder", thread.subtitle)
        }

        if let agentRole = thread.agentRole?.trimmingCharacters(in: .whitespacesAndNewlines),
           !agentRole.isEmpty {
            return ("person.2", agentRole)
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 5 : 7) {
            HStack(alignment: .top, spacing: 8) {
                Text(thread.displayTitle)
                    .font(theme.codeFont(usesCompactLayout ? 13 : 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(relativeDateString)
                    .font(theme.codeFont(10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            if let previewText {
                Text(previewText)
                    .font(theme.font(11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(usesCompactLayout ? 1 : 2)
            }

            HStack(spacing: 8) {
                if let metadataLabel {
                    Label(metadataLabel.text, systemImage: metadataLabel.systemImage)
                        .lineLimit(1)
                }

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
                    .stroke(theme.accent.opacity(0.2), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var relativeDateString: String {
        Self.relativeDateFormatter.localizedString(for: thread.updatedDate, relativeTo: .now)
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

struct NewThreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidekickTheme) private var theme

    let creationTargets: [ThreadCreationTarget]
    let createThread: (String?) async -> String?

    @State private var customPath = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundBottom
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start a new thread in an existing project folder, or point Codex at a prepared worktree path on the paired host.")
                                    .font(theme.font(13))
                                    .foregroundStyle(theme.textSecondary)

                                Text("Archived threads stay hidden by default here, so this launcher is the quickest way to branch into a fresh working directory.")
                                    .font(theme.codeFont(11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }

                        SurfaceCard(padding: 0) {
                            VStack(spacing: 0) {
                                NewThreadTargetRow(
                                    title: "Default workspace",
                                    subtitle: "Use the host default when you just need a fresh thread.",
                                    actionTitle: "Start",
                                    isDisabled: isSubmitting,
                                    action: { startThread(in: nil) }
                                )

                                if creationTargets.isEmpty == false {
                                    Divider()
                                        .overlay(theme.divider)
                                        .padding(.leading, 12)
                                }

                                ForEach(Array(creationTargets.enumerated()), id: \.element.id) { index, target in
                                    if index > 0 {
                                        Divider()
                                            .overlay(theme.divider)
                                            .padding(.leading, 12)
                                    }

                                    NewThreadTargetRow(
                                        title: target.title,
                                        subtitle: target.subtitle ?? "Project folder",
                                        actionTitle: "Start",
                                        isDisabled: isSubmitting,
                                        action: { startThread(in: target.cwd) }
                                    )
                                }
                            }
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("New worktree path")
                                    .font(theme.codeFont(11, weight: .semibold))
                                    .foregroundStyle(theme.textTertiary)

                                TextField("/Users/joseph/project-worktree", text: $customPath)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(theme.codeFont(13))
                                    .sidekickInputFieldStyle()

                                Text("The path must exist on the paired host. If you already created a git worktree on the Mac, you can launch the new thread here.")
                                    .font(theme.codeFont(10))
                                    .foregroundStyle(theme.textTertiary)

                                Button("Start in Entered Path") {
                                    startThread(in: customPath)
                                }
                                .buttonStyle(SidekickActionButtonStyle(tone: .primary))
                                .disabled(isSubmitting || customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("New Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(theme.codeFont(12, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startThread(in cwd: String?) {
        guard isSubmitting == false else {
            return
        }

        let normalizedPath = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        Task {
            let threadID = await createThread(normalizedPath?.isEmpty == false ? normalizedPath : nil)
            await MainActor.run {
                isSubmitting = false
                if threadID != nil {
                    dismiss()
                }
            }
        }
    }
}

private struct NewThreadTargetRow: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String
    let subtitle: String
    let actionTitle: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.codeFont(12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text(subtitle)
                    .font(theme.codeFont(10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            Button(actionTitle, action: action)
                .buttonStyle(SidekickActionButtonStyle(tone: .secondary))
                .disabled(isDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}
