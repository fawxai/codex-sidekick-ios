import Observation
import SwiftUI

struct ApprovalInboxView: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    var body: some View {
        SidekickScrollScreen(topSpacing: 12) {
            SidekickTopBar {
                SidekickSectionMenuButton(
                    selectedSection: .approvals,
                    pendingApprovalCount: appModel.pendingApprovals.count,
                    selectSection: { selectedSection = $0 }
                )
            } trailing: {
                SidekickCircularToolbarButton(systemImage: "text.bubble") {
                    selectedSection = .threads
                }
            }
        } content: {
            LazyVStack(alignment: .leading, spacing: 12) {
                inboxHeader

                if appModel.pendingApprovals.isEmpty {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Approval inbox is clear")
                                .font(theme.codeFont(18, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)

                            Text("New command and file-change approvals from Codex will land here automatically.")
                                .font(theme.font(13))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                } else {
                    ForEach(appModel.pendingApprovals) { approval in
                        ApprovalCard(
                            approval: approval,
                            threadTitle: appModel.title(for: approval.threadID),
                            showThread: {
                                selectedSection = .threads
                                Task {
                                    await appModel.selectThread(approval.threadID)
                                }
                            },
                            approveCommand: { sessionScope in
                                await appModel.approveCommand(approval, sessionScope: sessionScope)
                            },
                            denyCommand: { cancelTurn in
                                await appModel.denyCommand(approval, cancelTurn: cancelTurn)
                            },
                            approveFileChange: { sessionScope in
                                await appModel.approveFileChange(approval, sessionScope: sessionScope)
                            },
                            denyFileChange: { cancelTurn in
                                await appModel.denyFileChange(approval, cancelTurn: cancelTurn)
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var inboxHeader: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remote approvals")
                            .font(theme.codeFont(18, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("Approve command execution and file changes without reaching back for the Mac.")
                            .font(theme.font(13))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    StatusPill(
                        text: appModel.pendingApprovals.isEmpty ? "CLEAR" : "\(appModel.pendingApprovals.count) PENDING",
                        tone: appModel.pendingApprovals.isEmpty ? .success : .warning
                    )
                }

                if appModel.pendingApprovals.isEmpty == false {
                    Button("Back to Threads") {
                        selectedSection = .threads
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .secondary))
                }
            }
        }
    }

}

private struct ApprovalCard: View {
    @Environment(\.sidekickTheme) private var theme

    let approval: AppModel.PendingApproval
    let threadTitle: String
    let showThread: () -> Void
    let approveCommand: (Bool) async -> Void
    let denyCommand: (Bool) async -> Void
    let approveFileChange: (Bool) async -> Void
    let denyFileChange: (Bool) async -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 10)
    ]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(approval.title)
                            .font(theme.codeFont(15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(threadTitle)
                            .font(theme.font(12))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    StatusPill(text: approval.kindLabel, tone: approval.kindTone)
                }

                Text(approval.subtitle)
                    .font(theme.font(13))
                    .foregroundStyle(theme.textSecondary)

                approvalMetadata

                Button("Show Thread", action: showThread)
                    .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))

                LazyVGrid(columns: gridColumns, spacing: 10) {
                    switch approval.kind {
                    case .command:
                        Button("Accept") {
                            Task {
                                await approveCommand(false)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .primary, fullWidth: true))

                        Button("Accept for Session") {
                            Task {
                                await approveCommand(true)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))

                        Button("Decline") {
                            Task {
                                await denyCommand(false)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .danger, fullWidth: true))

                        Button("Cancel Turn") {
                            Task {
                                await denyCommand(true)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .warning, fullWidth: true))
                    case .fileChange:
                        Button("Apply Changes") {
                            Task {
                                await approveFileChange(false)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .primary, fullWidth: true))

                        Button("Apply for Session") {
                            Task {
                                await approveFileChange(true)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))

                        Button("Decline") {
                            Task {
                                await denyFileChange(false)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .danger, fullWidth: true))

                        Button("Cancel Turn") {
                            Task {
                                await denyFileChange(true)
                            }
                        }
                        .buttonStyle(SidekickActionButtonStyle(tone: .warning, fullWidth: true))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var approvalMetadata: some View {
        switch approval.kind {
        case .command(let params):
            VStack(alignment: .leading, spacing: 8) {
                if let cwd = params.cwd, cwd.isEmpty == false {
                    metadataRow(label: "Working directory", value: CodexDisplay.formatDirectoryDisplay(cwd))
                }

                if let networkContext = params.networkApprovalContext {
                    metadataRow(
                        label: "Network",
                        value: "\(networkContext.protocol.uppercased()) \(networkContext.host)"
                    )
                }
            }
        case .fileChange(let params):
            VStack(alignment: .leading, spacing: 8) {
                if let root = params.grantRoot, root.isEmpty == false {
                    metadataRow(label: "Grant root", value: CodexDisplay.formatDirectoryDisplay(root))
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            Spacer(minLength: 10)

            Text(value)
                .font(theme.codeFont(11))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.panelMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

private extension AppModel.PendingApproval {
    var kindLabel: String {
        switch kind {
        case .command:
            return "COMMAND"
        case .fileChange:
            return "FILE CHANGE"
        }
    }

    var kindTone: StatusTone {
        switch kind {
        case .command:
            return .warning
        case .fileChange:
            return .success
        }
    }
}
