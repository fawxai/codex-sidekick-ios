import SwiftUI

enum StatusTone {
    case neutral
    case accent
    case success
    case warning
    case danger
}

enum SidekickSection: String, CaseIterable, Identifiable {
    case threads
    case approvals
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .threads:
            return "Threads"
        case .approvals:
            return "Approvals"
        case .settings:
            return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .threads:
            return "text.bubble"
        case .approvals:
            return "exclamationmark.shield"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}

enum SidekickButtonTone {
    case primary
    case secondary
    case warning
    case danger
}

struct SurfaceCard<Content: View>: View {
    @Environment(\.sidekickTheme) private var theme

    let padding: CGFloat
    let content: Content

    init(
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .shadow(color: theme.shadow, radius: 6, y: 1)
    }
}

struct SidekickSectionMenuButton: View {
    @Environment(\.sidekickTheme) private var theme

    let selectedSection: SidekickSection
    let pendingApprovalCount: Int
    let selectSection: (SidekickSection) -> Void

    var body: some View {
        Menu {
            ForEach(SidekickSection.allCases) { section in
                Button {
                    selectSection(section)
                } label: {
                    Label(menuTitle(for: section), systemImage: section.iconName)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selectedSection.iconName)
                    .font(.system(size: 12, weight: .medium))

                Text(selectedSection.title)
                    .font(theme.codeFont(12, weight: .semibold))

                if pendingApprovalCount > 0, selectedSection != .approvals {
                    Text("\(pendingApprovalCount)")
                        .font(theme.codeFont(10, weight: .bold))
                        .foregroundStyle(theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(theme.warning.opacity(0.14))
                        )
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
    }

    private func menuTitle(for section: SidekickSection) -> String {
        if section == .approvals, pendingApprovalCount > 0 {
            return "\(section.title) (\(pendingApprovalCount))"
        }
        return section.title
    }
}

struct SidekickCircularToolbarButton: View {
    @Environment(\.sidekickTheme) private var theme

    let systemImage: String
    let tint: Color?
    let action: () -> Void

    init(
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint ?? theme.textPrimary)
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
        .buttonStyle(.plain)
    }
}

struct SidekickTopBar<Leading: View, Trailing: View>: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String?
    let leading: Leading
    let trailing: Trailing

    init(
        title: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(theme.codeFont(13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 72)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

struct StatusPill: View {
    @Environment(\.sidekickTheme) private var theme

    let text: String
    let tone: StatusTone

    var body: some View {
        Text(text)
            .font(theme.codeFont(10, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
        case .neutral:
            theme.chromeElevated
        case .accent:
            theme.chromeElevated
        case .success:
            theme.success.opacity(0.16)
        case .warning:
            theme.warning.opacity(0.16)
        case .danger:
            theme.danger.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            theme.textPrimary
        case .accent:
            theme.textPrimary
        case .success:
            theme.success
        case .warning:
            theme.warning
        case .danger:
            theme.danger
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            theme.border.opacity(0.8)
        case .accent:
            theme.border.opacity(0.8)
        case .success:
            theme.success.opacity(0.34)
        case .warning:
            theme.warning.opacity(0.34)
        case .danger:
            theme.danger.opacity(0.34)
        }
    }
}

struct DotStatusRow: View {
    @Environment(\.sidekickTheme) private var theme

    let title: String
    let value: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(dotColor)
                .frame(width: 7, height: 7)

            Text(title)
                .font(theme.codeFont(10, weight: .medium))
                .foregroundStyle(theme.textTertiary)

            Spacer()

            Text(value)
                .font(theme.codeFont(12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .neutral:
            theme.textTertiary
        case .accent:
            theme.textSecondary
        case .success:
            theme.success
        case .warning:
            theme.warning
        case .danger:
            theme.danger
        }
    }
}

struct SidekickActionButtonStyle: ButtonStyle {
    @Environment(\.sidekickTheme) private var theme

    let tone: SidekickButtonTone
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.codeFont(12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        switch tone {
        case .primary:
            theme.textPrimary
        case .secondary:
            theme.chromeElevated
        case .warning:
            theme.chromeElevated
        case .danger:
            theme.chromeElevated
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary:
            theme.backgroundBottom
        case .secondary:
            theme.textPrimary
        case .warning:
            theme.textPrimary
        case .danger:
            theme.textPrimary
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            theme.textPrimary.opacity(0.22)
        case .secondary:
            theme.border
        case .warning:
            theme.border
        case .danger:
            theme.border
        }
    }
}

private struct SidekickInputFieldModifier: ViewModifier {
    @Environment(\.sidekickTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.codeFont(13))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func sidekickInputFieldStyle() -> some View {
        modifier(SidekickInputFieldModifier())
    }
}

enum CodexDisplay {
    static func formatDirectoryDisplay(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No workspace"
        }

        let url = URL(fileURLWithPath: trimmed)
        let standardizedPath = url.standardizedFileURL.path
        let homePath = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path

        if standardizedPath == homePath {
            return "~"
        }

        let homePrefix = homePath.hasSuffix("/") ? homePath : "\(homePath)/"
        if standardizedPath.hasPrefix(homePrefix) {
            let relative = String(standardizedPath.dropFirst(homePrefix.count))
            return relative.isEmpty ? "~" : "~/\(relative)"
        }

        return standardizedPath
    }

    static func compactDirectoryDisplay(_ path: String) -> String {
        let formatted = formatDirectoryDisplay(path)
        let expandedPath = formatted.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let lastPathComponent = URL(fileURLWithPath: expandedPath).lastPathComponent
        return lastPathComponent.isEmpty ? formatted : lastPathComponent
    }
}
