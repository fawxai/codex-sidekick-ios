import SwiftUI

struct ThreadTimelineView: View {
    @Environment(\.sidekickTheme) private var theme

    let thread: CodexThread

    var body: some View {
        SurfaceCard(padding: 14) {
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
}

private struct TurnSection: View {
    @Environment(\.sidekickTheme) private var theme

    let turn: CodexTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(turn.id)
                    .font(theme.codeFont(10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)

                Spacer()

                StatusPill(text: turn.status.rawValue, tone: tone(for: turn.status))
            }

            if let error = turn.error {
                Text(error.message)
                    .font(theme.codeFont(12, weight: .medium))
                    .foregroundStyle(theme.danger)
            }

            ForEach(Array(turn.items.enumerated()), id: \.element.id) { _, item in
                ThreadItemRow(item: item)
            }
        }
    }

    private func tone(for status: TurnStatus) -> StatusTone {
        switch status {
        case .completed:
            return .success
        case .interrupted:
            return .warning
        case .failed:
            return .danger
        case .inProgress:
            return .neutral
        }
    }
}

private struct ThreadItemRow: View {
    @Environment(\.sidekickTheme) private var theme

    let item: ThreadItem

    var body: some View {
        switch item {
        case .userMessage(let message):
            HStack {
                Spacer(minLength: 44)
                messageBubble(
                    title: "You",
                    body: message.content.map(\.renderedText).joined(separator: "\n\n"),
                    background: theme.panelMuted,
                    border: theme.border,
                    alignment: .trailing
                )
            }
        case .agentMessage(let message):
            HStack {
                messageBubble(
                    title: message.phase ?? "Codex",
                    body: message.text,
                    background: theme.chromeElevated,
                    border: theme.border,
                    alignment: .leading
                )
                Spacer(minLength: 44)
            }
        case .commandExecution(let command):
            toolCard(
                title: "Command",
                body: command.command,
                footer: command.aggregatedOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
                tone: theme.textSecondary
            )
        case .fileChange(let change):
            toolCard(
                title: "File Change",
                body: change.changes.map(\.path).joined(separator: "\n"),
                footer: nil,
                tone: theme.textSecondary
            )
        case .reasoning(let reasoning):
            toolCard(
                title: "Reasoning",
                body: (reasoning.summary + reasoning.content).joined(separator: "\n"),
                footer: nil,
                tone: theme.textSecondary
            )
        case .plan(_, let text):
            toolCard(
                title: "Plan",
                body: text,
                footer: nil,
                tone: theme.textSecondary
            )
        case .enteredReviewMode(let review), .exitedReviewMode(let review):
            toolCard(
                title: "Review",
                body: review.review,
                footer: nil,
                tone: theme.textSecondary
            )
        case .contextCompaction:
            toolCard(
                title: "Compaction",
                body: "Codex compacted the thread context.",
                footer: nil,
                tone: theme.textTertiary
            )
        case .unknown(let unknown):
            toolCard(
                title: unknown.type,
                body: unknown.raw?.description ?? "Unsupported item",
                footer: nil,
                tone: theme.textTertiary
            )
        }
    }

    private func messageBubble(
        title: String,
        body: String,
        background: Color,
        border: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(title.uppercased())
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            Text(body.isEmpty ? "..." : body)
                .font(theme.font(13))
                .foregroundStyle(theme.textPrimary)
                .frame(
                    maxWidth: .infinity,
                    alignment: alignment == .leading ? .leading : .trailing
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
    }

    private func toolCard(
        title: String,
        body: String,
        footer: String?,
        tone: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(tone)

            Text(body.isEmpty ? "No content" : body)
                .font(theme.codeFont(12))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(theme.codeFont(11))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.panelMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tone.opacity(0.26), lineWidth: 1)
        )
    }
}
