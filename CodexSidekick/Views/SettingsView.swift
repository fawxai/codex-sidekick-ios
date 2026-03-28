import Observation
import SwiftUI

struct SettingsView: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    private let modeOrder: [SidekickThemeMode] = [.light, .dark, .system]
    private let buttonColumns = [
        GridItem(.adaptive(minimum: 132, maximum: 196), spacing: 8)
    ]

    var body: some View {
        SidekickScrollScreen(topSpacing: 12) {
            SidekickTopBar {
                SidekickSectionMenuButton(
                    selectedSection: .settings,
                    pendingApprovalCount: appModel.pendingApprovals.count,
                    selectSection: { selectedSection = $0 }
                )
            } trailing: {
                SidekickCircularToolbarButton(systemImage: "text.bubble") {
                    selectedSection = .threads
                }
            }
        } content: {
            LazyVStack(alignment: .leading, spacing: 14) {
                appearanceHeroCard
                appearanceControlsCard
                typographyCard
                connectionCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var appearanceHeroCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Appearance")
                            .font(theme.codeFont(20, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("Borrow the Codex desktop design language, but tune it for a native mobile shell.")
                            .font(theme.font(13))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    if appModel.appearanceSettings.syncsWithHostTheme,
                       let themeName = appModel.hostAppearance.themeName,
                       themeName.isEmpty == false {
                        StatusPill(text: "SYNCED: \(themeName)", tone: .neutral)
                    } else {
                        StatusPill(text: appModel.appearanceSettings.preset.title, tone: .neutral)
                    }
                }

                AppearancePreviewPanel()
            }
        }
    }

    private var appearanceControlsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionHeader(
                    title: "Theme",
                    detail: "Use the paired host theme when available, or fall back to a local preset."
                )

                settingRow(
                    title: "Sync with host theme",
                    detail: hostThemeDetail
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { appModel.appearanceSettings.syncsWithHostTheme },
                            set: { appModel.setSyncWithHostTheme($0) }
                        )
                    )
                    .labelsHidden()
                    .tint(theme.textPrimary)
                }

                settingRow(
                    title: "Theme mode",
                    detail: "Match the desktop appearance controls: Light, Dark, or System."
                ) {
                    ThemeModeSelector(
                        modes: modeOrder,
                        selectedMode: Binding(
                            get: { appModel.appearanceSettings.mode },
                            set: { appModel.setAppearanceMode($0) }
                        )
                    )
                }

                settingRow(
                    title: "Theme preset",
                    detail: "Used for local fallback and for explicit iOS-only overrides."
                ) {
                    Picker(
                        "Theme preset",
                        selection: Binding(
                            get: { appModel.appearanceSettings.preset },
                            set: { appModel.setAppearancePreset($0) }
                        )
                    ) {
                        ForEach(SidekickThemePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.textPrimary)
                }

                settingRow(
                    title: "Translucent sidebar",
                    detail: "Optional subtle translucency for wide-layout navigation surfaces. Keep this off for the flatter Codex look."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { appModel.appearanceSettings.translucentSidebar },
                            set: { appModel.setTranslucentSidebar($0) }
                        )
                    )
                    .labelsHidden()
                    .tint(theme.textPrimary)
                }

                sliderSetting(
                    title: "Contrast",
                    detail: "Adjust the separation between surfaces, borders, and content cards.",
                    valueText: String(format: "%.0f%%", appModel.appearanceSettings.contrast * 100),
                    range: 0.45...0.9,
                    value: Binding(
                        get: { appModel.appearanceSettings.contrast },
                        set: { appModel.setContrast($0) }
                    )
                )
            }
        }
    }

    private var typographyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionHeader(
                    title: "Typography",
                    detail: "These map to the desktop app's UI font size and code font size controls."
                )

                sliderSetting(
                    title: "UI font size",
                    detail: "Adjust the base size used for the Codex UI.",
                    valueText: String(format: "%.0f%%", appModel.appearanceSettings.uiScale * 100),
                    range: 0.85...1.25,
                    value: Binding(
                        get: { appModel.appearanceSettings.uiScale },
                        set: { appModel.setUIFontScale($0) }
                    )
                )

                sliderSetting(
                    title: "Code font size",
                    detail: "Adjust the base size used for code across rollouts and approvals.",
                    valueText: String(format: "%.0f%%", appModel.appearanceSettings.codeScale * 100),
                    range: 0.85...1.25,
                    value: Binding(
                        get: { appModel.appearanceSettings.codeScale },
                        set: { appModel.setCodeFontScale($0) }
                    )
                )
            }
        }
    }

    private var connectionCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionHeader(
                    title: "Connection",
                    detail: "The appearance sync and live thread state both come from this paired host."
                )

                settingRow(
                    title: "Host",
                    detail: appModel.pairedConnection?.websocketURL ?? "No paired host"
                ) {
                    StatusPill(text: appModel.pairedHostLabel, tone: .neutral)
                }

                settingRow(
                    title: "App-server theme",
                    detail: "Read from `config/read` when the host exposes a theme."
                ) {
                    Text(appModel.hostAppearance.themeName ?? "Unavailable")
                        .font(theme.codeFont(12, weight: .medium))
                        .foregroundStyle(appModel.hostAppearance.themeName == nil ? theme.textTertiary : theme.textPrimary)
                }

                LazyVGrid(columns: buttonColumns, spacing: 10) {
                    Button("Refresh Host Theme") {
                        Task {
                            await appModel.refreshHostAppearance()
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))

                    Button("Reconnect") {
                        Task {
                            await appModel.reconnect()
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))

                    Button("Forget Pairing") {
                        Task {
                            await appModel.forgetPairing()
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .danger, fullWidth: true))
                }
            }
        }
    }

    private var hostThemeDetail: String {
        if let themeName = appModel.hostAppearance.themeName, themeName.isEmpty == false {
            return "Current host theme: \(themeName)"
        }
        return "If the paired host exposes its theme, the sidekick mirrors it automatically."
    }

    private func settingsSectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.codeFont(16, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Text(detail)
                .font(theme.font(12))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func settingRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.codeFont(12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(detail)
                        .font(theme.font(11))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                control()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.panelMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func sliderSetting(
        title: String,
        detail: String,
        valueText: String,
        range: ClosedRange<Double>,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.codeFont(12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(detail)
                        .font(theme.font(11))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 12)

                Text(valueText)
                    .font(theme.codeFont(11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }

            Slider(value: value, in: range)
                .tint(theme.textPrimary)
        }
        .padding(12)
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

private struct AppearancePreviewPanel: View {
    @Environment(\.sidekickTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sidebar")
                    .font(theme.codeFont(10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)

                previewPill("Threads", tone: .neutral)
                previewPill("Approvals", tone: .neutral)
                previewPill("Settings", tone: .neutral)
            }
            .frame(maxWidth: 108, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.sidebar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Codex")
                        .font(theme.codeFont(14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    StatusPill(text: "LIVE", tone: .success)
                }

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.chromeElevated)
                    .frame(height: 52)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("turn/start")
                                .font(theme.codeFont(10, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("Open live thread and hand off")
                                .font(theme.font(11))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    diffBlock(color: theme.panelMuted, lineColor: theme.textSecondary)
                    diffBlock(color: theme.chromeElevated, lineColor: theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
    }

    private func previewPill(_ title: String, tone: StatusTone) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(for: tone))
                .frame(width: 7, height: 7)

            Text(title)
                .font(theme.codeFont(10, weight: .medium))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.chrome)
        )
    }

    private func diffBlock(color: Color, lineColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color)
            .frame(height: 64)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(lineColor.opacity(0.86))
                            .frame(width: 78, height: 4)
                    }
                }
                .padding(12)
            }
    }

    private func color(for tone: StatusTone) -> Color {
        switch tone {
        case .neutral:
            return theme.textTertiary
        case .accent:
            return theme.textSecondary
        case .success:
            return theme.success
        case .warning:
            return theme.warning
        case .danger:
            return theme.danger
        }
    }
}

private struct ThemeModeSelector: View {
    @Environment(\.sidekickTheme) private var theme

    let modes: [SidekickThemeMode]
    @Binding var selectedMode: SidekickThemeMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modes) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Text(mode.title.uppercased())
                        .font(theme.codeFont(10, weight: .semibold))
                        .foregroundStyle(
                            selectedMode == mode ? theme.backgroundBottom : theme.textPrimary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedMode == mode ? theme.textPrimary : theme.chromeElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    selectedMode == mode ? theme.textPrimary.opacity(0.22) : theme.border,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 260)
    }
}
