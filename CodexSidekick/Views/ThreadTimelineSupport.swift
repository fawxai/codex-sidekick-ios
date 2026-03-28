import Foundation
import SwiftUI

enum ThreadTimelineEntry: Identifiable {
    case commentaryGroup(id: String, messages: [AgentMessageItem])
    case item(ThreadItem)

    var id: String {
        switch self {
        case .commentaryGroup(let id, _):
            return id
        case .item(let item):
            return item.id
        }
    }
}

enum ThreadMessagePhaseKind: String {
    case commentary = "commentary"
    case finalAnswer = "final_answer"

    init?(rawPhase: String?) {
        guard let rawPhase else {
            return nil
        }

        let normalized = rawPhase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "commentary":
            self = .commentary
        case "final_answer", "finalanswer":
            self = .finalAnswer
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .commentary:
            return "Commentary"
        case .finalAnswer:
            return "Answer"
        }
    }
}

extension AgentMessageItem {
    var phaseKind: ThreadMessagePhaseKind? {
        ThreadMessagePhaseKind(rawPhase: phase)
    }

    var phaseTitle: String {
        phaseKind?.title ?? "Codex"
    }
}

extension CodexTurn {
    var timelineEntries: [ThreadTimelineEntry] {
        var entries: [ThreadTimelineEntry] = []
        var commentaryBuffer: [AgentMessageItem] = []

        func flushCommentaryBuffer() {
            guard !commentaryBuffer.isEmpty else {
                return
            }

            if commentaryBuffer.count == 1, let message = commentaryBuffer.first {
                entries.append(.item(.agentMessage(message)))
            } else {
                let groupID = commentaryBuffer.map(\.id).joined(separator: "::")
                entries.append(.commentaryGroup(id: groupID, messages: commentaryBuffer))
            }
            commentaryBuffer = []
        }

        for item in items {
            if case .agentMessage(let message) = item,
               message.phaseKind == .commentary {
                commentaryBuffer.append(message)
            } else {
                flushCommentaryBuffer()
                entries.append(.item(item))
            }
        }

        flushCommentaryBuffer()
        return entries
    }
}

struct ThreadTimelineEntryView: View {
    @Environment(\.sidekickTheme) private var theme

    let entry: ThreadTimelineEntry

    var body: some View {
        switch entry {
        case .commentaryGroup(_, let messages):
            CommentaryGroupView(messages: messages)
        case .item(let item):
            ThreadTimelineItemView(item: item)
        }
    }
}

private struct CommentaryGroupView: View {
    @Environment(\.sidekickTheme) private var theme

    let messages: [AgentMessageItem]

    @State private var isExpanded = false

    private var collapsedPreview: String {
        messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 8) {
                        Text("Commentary")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("\(messages.count)")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            CommentaryMessageBlock(
                                message: message,
                                index: index + 1,
                                totalCount: messages.count
                            )
                        }
                    }
                } else {
                    ThreadTimelineTextBlock(
                        text: collapsedPreview,
                        style: .markdown,
                        alignment: .leading,
                        fallback: "Commentary"
                    )
                    .lineLimit(3)
                }
            }

            Spacer(minLength: 36)
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeOut(duration: 0.16)) {
            isExpanded.toggle()
        }
    }
}

private struct CommentaryMessageBlock: View {
    @Environment(\.sidekickTheme) private var theme

    let message: AgentMessageItem
    let index: Int
    let totalCount: Int

    private var label: String {
        "\(index) of \(totalCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(theme.codeFont(9, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            ThreadTimelineTextBlock(
                text: message.text,
                style: .markdown,
                alignment: .leading
            )
        }
    }
}

private struct ThreadTimelineItemView: View {
    @Environment(\.sidekickTheme) private var theme

    let item: ThreadItem

    var body: some View {
        switch item {
        case .userMessage(let message):
            HStack {
                Spacer(minLength: 36)
                ThreadMessageCard(
                    title: "You",
                    contentText: message.content.map(\.renderedText).joined(separator: "\n\n"),
                    alignment: .trailing,
                    contentStyle: .markdown
                )
            }
        case .agentMessage(let message):
            HStack {
                ThreadMessageCard(
                    title: message.phaseTitle,
                    contentText: message.text,
                    alignment: .leading,
                    contentStyle: .markdown
                )
                Spacer(minLength: 36)
            }
        case .commandExecution(let command):
            ThreadTimelineToolCard(
                title: "Command",
                contentText: command.command,
                bodyStyle: .code,
                footer: command.aggregatedOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
                footerStyle: .code,
                tone: theme.textSecondary
            )
        case .fileChange(let change):
            ThreadTimelineToolCard(
                title: "File Change",
                contentText: change.changes.map(\.path).joined(separator: "\n"),
                bodyStyle: .code,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textSecondary
            )
        case .reasoning(let reasoning):
            ThreadTimelineToolCard(
                title: "Reasoning",
                contentText: (reasoning.summary + reasoning.content).joined(separator: "\n\n"),
                bodyStyle: .markdown,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textSecondary
            )
        case .plan(_, let text):
            ThreadTimelineToolCard(
                title: "Plan",
                contentText: text,
                bodyStyle: .markdown,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textSecondary
            )
        case .enteredReviewMode(let review), .exitedReviewMode(let review):
            ThreadTimelineToolCard(
                title: "Review",
                contentText: review.review,
                bodyStyle: .markdown,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textSecondary
            )
        case .contextCompaction:
            ThreadTimelineToolCard(
                title: "Compaction",
                contentText: "Codex compacted the thread context.",
                bodyStyle: .plain,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textTertiary
            )
        case .unknown(let unknown):
            ThreadTimelineToolCard(
                title: unknown.type,
                contentText: unknown.raw?.description ?? "Unsupported item",
                bodyStyle: .code,
                footer: nil,
                footerStyle: .plain,
                tone: theme.textTertiary
            )
        }
    }
}

private enum ThreadTimelineTextStyle {
    case markdown
    case plain
    case code
}

private struct ThreadMessageCard: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String
    let contentText: String
    let alignment: HorizontalAlignment
    let contentStyle: ThreadTimelineTextStyle

    var bodyViewAlignment: Alignment {
        alignment == .leading ? .leading : .trailing
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 7) {
            Text(title)
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: bodyViewAlignment)

            ThreadTimelineTextBlock(
                text: contentText,
                style: contentStyle,
                alignment: bodyViewAlignment
            )
        }
    }
}

private struct ThreadTimelineToolCard: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String
    let contentText: String
    let bodyStyle: ThreadTimelineTextStyle
    let footer: String?
    let footerStyle: ThreadTimelineTextStyle
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(tone)

            ThreadTimelineTextBlock(
                text: contentText,
                style: bodyStyle,
                alignment: .leading,
                fallback: "No content"
            )

            if let footer, !footer.isEmpty {
                ThreadTimelineTextBlock(
                    text: footer,
                    style: footerStyle,
                    alignment: .leading,
                    foreground: theme.textSecondary
                )
            }
        }
    }
}

private struct ThreadTimelineTextBlock: View {
    @Environment(\.sidekickTheme) private var theme

    let text: String
    let style: ThreadTimelineTextStyle
    let alignment: Alignment
    let fallback: String
    let foreground: Color?

    init(
        text: String,
        style: ThreadTimelineTextStyle,
        alignment: Alignment,
        fallback: String = "...",
        foreground: Color? = nil
    ) {
        self.text = text
        self.style = style
        self.alignment = alignment
        self.fallback = fallback
        self.foreground = foreground
    }

    var body: some View {
        Group {
            switch style {
            case .markdown:
                markdownBody
            case .plain:
                plainBody(text: displayText)
            case .code:
                codeBody(text: displayText)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var markdownBody: some View {
        Group {
            if let attributedMarkdown {
                Text(attributedMarkdown)
                    .font(theme.font(13))
                    .foregroundStyle(foreground ?? theme.textPrimary)
                    .lineSpacing(3)
                    .tint(theme.textPrimary)
            } else {
                plainBody(text: displayText)
            }
        }
    }

    private func plainBody(text: String) -> some View {
        Text(text)
            .font(theme.font(13))
            .foregroundStyle(foreground ?? theme.textPrimary)
            .lineSpacing(3)
    }

    private func codeBody(text: String) -> some View {
        Text(text)
            .font(theme.codeFont(12))
            .foregroundStyle(foreground ?? theme.textPrimary)
            .lineSpacing(2)
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var attributedMarkdown: AttributedString? {
        guard style == .markdown else {
            return nil
        }

        do {
            return try AttributedString(
                markdown: displayText,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
        }
    }
}
