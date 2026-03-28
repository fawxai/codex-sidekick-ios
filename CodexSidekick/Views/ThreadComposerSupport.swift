import SwiftUI

struct ComposerModelOption: Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let detail: String
}

enum ComposerReasoningOption: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case extraHigh = "xhigh"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .extraHigh:
            return "Extra High"
        }
    }
}

enum ComposerMenuKind {
    case neutral
    case warning
}

extension ComposerModelOption {
    static let defaultCatalog: [ComposerModelOption] = [
        ComposerModelOption(
            id: "gpt-5.4",
            slug: "gpt-5.4",
            title: "GPT-5.4",
            detail: "Latest frontier agentic coding model."
        ),
        ComposerModelOption(
            id: "gpt-5.4-mini",
            slug: "gpt-5.4-mini",
            title: "GPT-5.4-Mini",
            detail: "Smaller frontier agentic coding model."
        ),
        ComposerModelOption(
            id: "gpt-5.3-codex",
            slug: "gpt-5.3-codex",
            title: "GPT-5.3-Codex",
            detail: "Frontier Codex-optimized agentic coding model."
        ),
        ComposerModelOption(
            id: "gpt-5.3-codex-spark",
            slug: "gpt-5.3-codex-spark",
            title: "GPT-5.3-Codex-Spark",
            detail: "Ultra-fast coding model."
        ),
        ComposerModelOption(
            id: "gpt-5.2-codex",
            slug: "gpt-5.2-codex",
            title: "GPT-5.2-Codex",
            detail: "Frontier agentic coding model."
        ),
        ComposerModelOption(
            id: "gpt-5.2",
            slug: "gpt-5.2",
            title: "GPT-5.2",
            detail: "Optimized for professional work and long-running agents."
        ),
        ComposerModelOption(
            id: "gpt-5.1-codex-max",
            slug: "gpt-5.1-codex-max",
            title: "GPT-5.1-Codex-Max",
            detail: "Codex-optimized model for deep and fast reasoning."
        ),
        ComposerModelOption(
            id: "gpt-5.1-codex-mini",
            slug: "gpt-5.1-codex-mini",
            title: "GPT-5.1-Codex-Mini",
            detail: "Faster Codex model with lower cost."
        )
    ]
}

struct ComposerMenuChip: View {
    @Environment(\.sidekickTheme) private var theme

    let text: String
    let icon: String?
    let kind: ComposerMenuKind

    init(text: String, icon: String? = nil, kind: ComposerMenuKind = .neutral) {
        self.text = text
        self.icon = icon
        self.kind = kind
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(text)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(theme.codeFont(10, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch kind {
        case .neutral:
            theme.chromeElevated
        case .warning:
            theme.warning.opacity(0.14)
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .neutral:
            theme.textPrimary
        case .warning:
            theme.warning
        }
    }

    private var borderColor: Color {
        switch kind {
        case .neutral:
            theme.border
        case .warning:
            theme.warning.opacity(0.28)
        }
    }
}

struct ComposerStateChip: View {
    @Environment(\.sidekickTheme) private var theme

    let text: String
    let icon: String?
    let tone: StatusTone

    init(text: String, icon: String? = nil, tone: StatusTone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(text)
                .lineLimit(1)
        }
        .font(theme.codeFont(10, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch tone {
        case .warning:
            theme.warning.opacity(0.14)
        case .danger:
            theme.danger.opacity(0.14)
        case .success:
            theme.success.opacity(0.14)
        case .neutral, .accent:
            theme.chromeElevated
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .warning:
            theme.warning
        case .danger:
            theme.danger
        case .success:
            theme.success
        case .neutral, .accent:
            theme.textPrimary
        }
    }

    private var borderColor: Color {
        switch tone {
        case .warning:
            theme.warning.opacity(0.28)
        case .danger:
            theme.danger.opacity(0.28)
        case .success:
            theme.success.opacity(0.28)
        case .neutral, .accent:
            theme.border
        }
    }
}

struct ComposerModelMenuContent: View {
    let options: [ComposerModelOption]
    let selectedSlug: String?
    let select: (ComposerModelOption) -> Void

    var body: some View {
        Section("Select model") {
            ForEach(options) { option in
                Button {
                    select(option)
                } label: {
                    if selectedSlug == option.slug {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        }
    }
}

struct ComposerReasoningMenuContent: View {
    let selected: ComposerReasoningOption?
    let select: (ComposerReasoningOption) -> Void

    var body: some View {
        Section("Select reasoning") {
            ForEach(ComposerReasoningOption.allCases) { option in
                Button {
                    select(option)
                } label: {
                    if selected == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        }
    }
}

struct ComposerFooterMenuLabel: View {
    @Environment(\.sidekickTheme) private var theme

    let text: String
    let icon: String
    let tone: StatusTone

    init(text: String, icon: String, tone: StatusTone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))

            Text(text)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(theme.codeFont(10, weight: .medium))
        .foregroundStyle(foregroundColor)
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral, .accent:
            theme.textSecondary
        case .warning:
            theme.warning
        case .danger:
            theme.danger
        case .success:
            theme.success
        }
    }
}

struct ComposerContextMeterLabel: View {
    @Environment(\.sidekickTheme) private var theme

    let progress: Double?
    let tone: StatusTone

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.border.opacity(0.85), lineWidth: 1.4)

            Circle()
                .trim(from: 0, to: max(min(progress ?? 0, 0.999), 0))
                .stroke(
                    meterColor,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }

    private var meterColor: Color {
        guard progress != nil else {
            return theme.textTertiary
        }

        switch tone {
        case .neutral, .accent:
            return theme.textSecondary
        case .warning:
            return theme.warning
        case .danger:
            return theme.danger
        case .success:
            return theme.success
        }
    }
}
