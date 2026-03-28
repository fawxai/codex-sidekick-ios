import SwiftUI

struct ThreadTimelineView: View {
    @Environment(\.sidekickTheme) private var theme

    let thread: CodexThread

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rollout")
                    .font(theme.codeFont(16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Text("\(thread.turns.count) turn\(thread.turns.count == 1 ? "" : "s")")
                    .font(theme.codeFont(10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }

            if thread.turns.isEmpty {
                Text("This thread has no loaded turns yet. Resume it live or refresh the thread detail to pull in the latest rollout.")
                    .font(theme.font(13))
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(Array(thread.turns.enumerated()), id: \.element.id) { index, turn in
                    TurnSection(turn: turn)

                    if index != thread.turns.endIndex - 1 {
                        Divider()
                            .overlay(theme.divider)
                    }
                }
            }
        }
    }
}

private struct TurnSection: View {
    @Environment(\.sidekickTheme) private var theme

    let turn: CodexTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(turn.id)
                    .font(theme.codeFont(10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)

                Spacer()

                Text(turn.status.rawValue)
                    .font(theme.codeFont(10, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            if let error = turn.error {
                Text(error.message)
                    .font(theme.codeFont(12, weight: .medium))
                    .foregroundStyle(theme.danger)
            }

            ForEach(Array(turn.timelineEntries.enumerated()), id: \.element.id) { index, entry in
                ThreadTimelineEntryView(entry: entry)

                if index != turn.timelineEntries.endIndex - 1 {
                    Divider()
                        .overlay(theme.divider.opacity(0.55))
                }
            }
        }
    }

    private var statusColor: Color {
        switch turn.status {
        case .completed:
            return theme.success
        case .interrupted:
            return theme.warning
        case .failed:
            return theme.danger
        case .inProgress:
            return theme.textTertiary
        }
    }
}
