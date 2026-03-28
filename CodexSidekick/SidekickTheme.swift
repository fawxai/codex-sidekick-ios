import SwiftUI

enum SidekickThemeMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case dark
    case light

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
}

enum SidekickThemePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex
    case github
    case gruvbox
    case dracula
    case catppuccin
    case nord
    case solarized

    var id: Self { self }

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .github:
            return "GitHub"
        case .gruvbox:
            return "Gruvbox"
        case .dracula:
            return "Dracula"
        case .catppuccin:
            return "Catppuccin"
        case .nord:
            return "Nord"
        case .solarized:
            return "Solarized"
        }
    }

    static func fromHostThemeName(_ hostThemeName: String) -> SidekickThemePreset {
        let normalized = hostThemeName.lowercased()
        if normalized.contains("github") {
            return .github
        }
        if normalized.contains("gruvbox") {
            return .gruvbox
        }
        if normalized.contains("dracula") {
            return .dracula
        }
        if normalized.contains("catppuccin") {
            return .catppuccin
        }
        if normalized.contains("nord") {
            return .nord
        }
        if normalized.contains("solarized") {
            return .solarized
        }
        return .codex
    }
}

struct SidekickAppearanceSettings: Codable, Sendable, Equatable {
    var mode: SidekickThemeMode = .dark
    var preset: SidekickThemePreset = .codex
    var syncsWithHostTheme = true
    var translucentSidebar = false
    var uiScale: Double = 1.0
    var codeScale: Double = 1.0
    var contrast: Double = 0.68
}

struct HostAppearanceSnapshot: Sendable, Equatable {
    var themeName: String?

    var isAvailable: Bool {
        themeName != nil
    }
}

struct SidekickTheme {
    let colorScheme: ColorScheme?
    let accent: Color
    let accentSoft: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let chrome: Color
    let chromeElevated: Color
    let sidebar: Color
    let panel: Color
    let panelMuted: Color
    let border: Color
    let divider: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let selection: Color
    let success: Color
    let warning: Color
    let danger: Color
    let shadow: Color
    let translucentSidebar: Bool
    let uiScale: CGFloat
    let codeScale: CGFloat

    var background: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * uiScale, weight: weight, design: design)
    }

    func codeFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * codeScale, weight: weight, design: .monospaced)
    }

    static func resolve(
        settings: SidekickAppearanceSettings,
        hostAppearance: HostAppearanceSnapshot,
        systemColorScheme: ColorScheme
    ) -> SidekickTheme {
        let resolvedChoice = ResolvedChoice(
            settings: settings,
            hostAppearance: hostAppearance,
            systemColorScheme: systemColorScheme
        )
        return resolvedChoice.preset.makeTheme(mode: resolvedChoice.mode, settings: settings)
    }
}

private struct ResolvedChoice {
    let preset: SidekickThemePreset
    let mode: ResolvedThemeMode

    init(
        settings: SidekickAppearanceSettings,
        hostAppearance: HostAppearanceSnapshot,
        systemColorScheme: ColorScheme
    ) {
        if settings.syncsWithHostTheme, let hostThemeName = hostAppearance.themeName {
            preset = SidekickThemePreset.fromHostThemeName(hostThemeName)
            mode = ResolvedThemeMode.fromHostThemeName(hostThemeName)
            return
        }

        preset = settings.preset
        switch settings.mode {
        case .system:
            mode = systemColorScheme == .light ? .light : .dark
        case .dark:
            mode = .dark
        case .light:
            mode = .light
        }
    }
}

private enum ResolvedThemeMode {
    case dark
    case light

    static func fromHostThemeName(_ hostThemeName: String) -> ResolvedThemeMode {
        let normalized = hostThemeName.lowercased()
        if normalized.contains("light")
            || normalized == "github"
            || normalized == "inspired-github"
            || normalized == "catppuccin-latte"
        {
            return .light
        }
        return .dark
    }
}

private struct ThemeDefinition {
    let accent: Color
    let accentSoft: Color
    let backgroundTop: Color
    let backgroundBottom: Color
    let chrome: Color
    let chromeElevated: Color
    let sidebar: Color
    let panel: Color
    let panelMuted: Color
    let border: Color
    let divider: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let selection: Color
    let success: Color
    let warning: Color
    let danger: Color
}

private extension SidekickThemePreset {
    func makeTheme(mode: ResolvedThemeMode, settings: SidekickAppearanceSettings) -> SidekickTheme {
        let definition = monochromeDefinition(for: mode)
        let contrast = min(max(settings.contrast, 0.45), 0.9)
        let sidebarOpacity = settings.translucentSidebar ? 0.94 : 1.0
        let borderOpacity = 0.48 + (contrast * 0.38)
        let dividerOpacity = 0.3 + (contrast * 0.28)

        return SidekickTheme(
            colorScheme: mode == .light ? .light : .dark,
            accent: definition.accent,
            accentSoft: definition.accentSoft,
            backgroundTop: definition.backgroundTop,
            backgroundBottom: definition.backgroundBottom,
            chrome: definition.chrome,
            chromeElevated: definition.chromeElevated,
            sidebar: definition.sidebar.opacity(sidebarOpacity),
            panel: definition.panel,
            panelMuted: definition.panelMuted,
            border: definition.border.opacity(borderOpacity),
            divider: definition.divider.opacity(dividerOpacity),
            textPrimary: definition.textPrimary,
            textSecondary: definition.textSecondary,
            textTertiary: definition.textTertiary,
            selection: definition.selection,
            success: definition.success,
            warning: definition.warning,
            danger: definition.danger,
            shadow: .black.opacity(mode == .light ? 0.03 : 0.12),
            translucentSidebar: settings.translucentSidebar,
            uiScale: CGFloat(settings.uiScale),
            codeScale: CGFloat(settings.codeScale)
        )
    }

    func monochromeDefinition(for mode: ResolvedThemeMode) -> ThemeDefinition {
        switch mode {
        case .dark:
            return ThemeDefinition(
                accent: Color(hex: 0xC8CDD4),
                accentSoft: Color(hex: 0x8E949D),
                backgroundTop: Color(hex: 0x0B0D10),
                backgroundBottom: Color(hex: 0x050608),
                chrome: Color(hex: 0x111317),
                chromeElevated: Color(hex: 0x191C20),
                sidebar: Color(hex: 0x0F1115),
                panel: Color(hex: 0x15191E),
                panelMuted: Color(hex: 0x11151A),
                border: Color(hex: 0x31363F),
                divider: Color(hex: 0x262B33),
                textPrimary: Color(hex: 0xF2F4F7),
                textSecondary: Color(hex: 0xB2B8C1),
                textTertiary: Color(hex: 0x7A8089),
                selection: Color(hex: 0x20252C),
                success: Color(hex: 0x52B788),
                warning: Color(hex: 0xE59A3A),
                danger: Color(hex: 0xE06C75)
            )
        case .light:
            return ThemeDefinition(
                accent: Color(hex: 0x20242A),
                accentSoft: Color(hex: 0x5A6068),
                backgroundTop: Color(hex: 0xF6F7F9),
                backgroundBottom: Color(hex: 0xECEEF1),
                chrome: Color(hex: 0xF7F8FA),
                chromeElevated: Color(hex: 0xFFFFFF),
                sidebar: Color(hex: 0xEFF1F4),
                panel: Color(hex: 0xFFFFFF),
                panelMuted: Color(hex: 0xF4F5F7),
                border: Color(hex: 0xD5D9E0),
                divider: Color(hex: 0xE1E4E8),
                textPrimary: Color(hex: 0x111418),
                textSecondary: Color(hex: 0x5D646D),
                textTertiary: Color(hex: 0x7C838C),
                selection: Color(hex: 0xE7EAEE),
                success: Color(hex: 0x2F855A),
                warning: Color(hex: 0xB7791F),
                danger: Color(hex: 0xC05621)
            )
        }
    }

    func themeDefinition(for mode: ResolvedThemeMode) -> ThemeDefinition {
        switch (self, mode) {
        case (.codex, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0xF29638),
                accentSoft: Color(hex: 0xF8B56B),
                backgroundTop: Color(hex: 0x0D0F13),
                backgroundBottom: Color(hex: 0x050608),
                chrome: Color(hex: 0x13161A),
                chromeElevated: Color(hex: 0x1A1D22),
                sidebar: Color(hex: 0x101317),
                panel: Color(hex: 0x171B20),
                panelMuted: Color(hex: 0x13171B),
                border: Color(hex: 0x343943),
                divider: Color(hex: 0x2A2F38),
                textPrimary: Color(hex: 0xF2EEE7),
                textSecondary: Color(hex: 0xB5B0A6),
                textTertiary: Color(hex: 0x7D7A72),
                selection: Color(hex: 0x242933),
                success: Color(hex: 0x52B788),
                warning: Color(hex: 0xE59A3A),
                danger: Color(hex: 0xE06C75)
            )
        case (.codex, .light):
            return ThemeDefinition(
                accent: Color(hex: 0xC66A1D),
                accentSoft: Color(hex: 0xE39B62),
                backgroundTop: Color(hex: 0xF7F2E8),
                backgroundBottom: Color(hex: 0xEFE7D9),
                chrome: Color(hex: 0xF4EEE4),
                chromeElevated: Color(hex: 0xFBF6EE),
                sidebar: Color(hex: 0xF0E8DB),
                panel: Color(hex: 0xFFFDF8),
                panelMuted: Color(hex: 0xF6F0E6),
                border: Color(hex: 0xD5CABB),
                divider: Color(hex: 0xDDD3C7),
                textPrimary: Color(hex: 0x1D1915),
                textSecondary: Color(hex: 0x645C53),
                textTertiary: Color(hex: 0x8F877D),
                selection: Color(hex: 0xEDE4D8),
                success: Color(hex: 0x2F855A),
                warning: Color(hex: 0xB7791F),
                danger: Color(hex: 0xC05621)
            )
        case (.github, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0x58A6FF),
                accentSoft: Color(hex: 0x79C0FF),
                backgroundTop: Color(hex: 0x0D1117),
                backgroundBottom: Color(hex: 0x010409),
                chrome: Color(hex: 0x161B22),
                chromeElevated: Color(hex: 0x1F2630),
                sidebar: Color(hex: 0x11161D),
                panel: Color(hex: 0x161B22),
                panelMuted: Color(hex: 0x0F141A),
                border: Color(hex: 0x30363D),
                divider: Color(hex: 0x262C36),
                textPrimary: Color(hex: 0xE6EDF3),
                textSecondary: Color(hex: 0x9DA7B3),
                textTertiary: Color(hex: 0x7D8590),
                selection: Color(hex: 0x1C2733),
                success: Color(hex: 0x3FB950),
                warning: Color(hex: 0xD29922),
                danger: Color(hex: 0xF85149)
            )
        case (.github, .light):
            return ThemeDefinition(
                accent: Color(hex: 0x0969DA),
                accentSoft: Color(hex: 0x218BFF),
                backgroundTop: Color(hex: 0xF6F8FA),
                backgroundBottom: Color(hex: 0xEEF2F6),
                chrome: Color(hex: 0xFFFFFF),
                chromeElevated: Color(hex: 0xF6F8FA),
                sidebar: Color(hex: 0xF6F8FA),
                panel: Color(hex: 0xFFFFFF),
                panelMuted: Color(hex: 0xF6F8FA),
                border: Color(hex: 0xD0D7DE),
                divider: Color(hex: 0xD8DEE4),
                textPrimary: Color(hex: 0x1F2328),
                textSecondary: Color(hex: 0x59636E),
                textTertiary: Color(hex: 0x7A828A),
                selection: Color(hex: 0xEAF2FF),
                success: Color(hex: 0x1A7F37),
                warning: Color(hex: 0x9A6700),
                danger: Color(hex: 0xCF222E)
            )
        case (.gruvbox, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0xD79921),
                accentSoft: Color(hex: 0xFABD2F),
                backgroundTop: Color(hex: 0x282828),
                backgroundBottom: Color(hex: 0x1D2021),
                chrome: Color(hex: 0x32302F),
                chromeElevated: Color(hex: 0x3C3836),
                sidebar: Color(hex: 0x282828),
                panel: Color(hex: 0x32302F),
                panelMuted: Color(hex: 0x282828),
                border: Color(hex: 0x504945),
                divider: Color(hex: 0x665C54),
                textPrimary: Color(hex: 0xEBDBB2),
                textSecondary: Color(hex: 0xBDAE93),
                textTertiary: Color(hex: 0x928374),
                selection: Color(hex: 0x3C3836),
                success: Color(hex: 0x98971A),
                warning: Color(hex: 0xD79921),
                danger: Color(hex: 0xCC241D)
            )
        case (.gruvbox, .light):
            return ThemeDefinition(
                accent: Color(hex: 0xAF3A03),
                accentSoft: Color(hex: 0xD65D0E),
                backgroundTop: Color(hex: 0xFBF1C7),
                backgroundBottom: Color(hex: 0xF2E5BC),
                chrome: Color(hex: 0xF9F5D7),
                chromeElevated: Color(hex: 0xFEFAE0),
                sidebar: Color(hex: 0xF2E5BC),
                panel: Color(hex: 0xF9F5D7),
                panelMuted: Color(hex: 0xF2E5BC),
                border: Color(hex: 0xD5C4A1),
                divider: Color(hex: 0xD8CAA8),
                textPrimary: Color(hex: 0x3C3836),
                textSecondary: Color(hex: 0x665C54),
                textTertiary: Color(hex: 0x928374),
                selection: Color(hex: 0xEBD8A7),
                success: Color(hex: 0x79740E),
                warning: Color(hex: 0xB57614),
                danger: Color(hex: 0x9D0006)
            )
        case (.dracula, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0xFF79C6),
                accentSoft: Color(hex: 0xBD93F9),
                backgroundTop: Color(hex: 0x1E1F29),
                backgroundBottom: Color(hex: 0x11131A),
                chrome: Color(hex: 0x282A36),
                chromeElevated: Color(hex: 0x343746),
                sidebar: Color(hex: 0x21222C),
                panel: Color(hex: 0x282A36),
                panelMuted: Color(hex: 0x21222C),
                border: Color(hex: 0x44475A),
                divider: Color(hex: 0x3D4151),
                textPrimary: Color(hex: 0xF8F8F2),
                textSecondary: Color(hex: 0xC5C6C7),
                textTertiary: Color(hex: 0x8B90A0),
                selection: Color(hex: 0x343746),
                success: Color(hex: 0x50FA7B),
                warning: Color(hex: 0xFFB86C),
                danger: Color(hex: 0xFF5555)
            )
        case (.dracula, .light):
            return ThemeDefinition(
                accent: Color(hex: 0x8B3FDB),
                accentSoft: Color(hex: 0xC86DD7),
                backgroundTop: Color(hex: 0xF8F4FF),
                backgroundBottom: Color(hex: 0xF0E9FF),
                chrome: Color(hex: 0xFBF8FF),
                chromeElevated: Color(hex: 0xFFFFFF),
                sidebar: Color(hex: 0xF1EAFF),
                panel: Color(hex: 0xFFFFFF),
                panelMuted: Color(hex: 0xF7F2FF),
                border: Color(hex: 0xD8CFF0),
                divider: Color(hex: 0xE3DCF4),
                textPrimary: Color(hex: 0x241D38),
                textSecondary: Color(hex: 0x5B5372),
                textTertiary: Color(hex: 0x887EA1),
                selection: Color(hex: 0xECE2FF),
                success: Color(hex: 0x2F855A),
                warning: Color(hex: 0xB7791F),
                danger: Color(hex: 0xC53030)
            )
        case (.catppuccin, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0x89B4FA),
                accentSoft: Color(hex: 0xF5C2E7),
                backgroundTop: Color(hex: 0x1E1E2E),
                backgroundBottom: Color(hex: 0x11111B),
                chrome: Color(hex: 0x313244),
                chromeElevated: Color(hex: 0x45475A),
                sidebar: Color(hex: 0x1E1E2E),
                panel: Color(hex: 0x313244),
                panelMuted: Color(hex: 0x252638),
                border: Color(hex: 0x585B70),
                divider: Color(hex: 0x4B4F63),
                textPrimary: Color(hex: 0xCDD6F4),
                textSecondary: Color(hex: 0xBAC2DE),
                textTertiary: Color(hex: 0x7F849C),
                selection: Color(hex: 0x45475A),
                success: Color(hex: 0xA6E3A1),
                warning: Color(hex: 0xF9E2AF),
                danger: Color(hex: 0xF38BA8)
            )
        case (.catppuccin, .light):
            return ThemeDefinition(
                accent: Color(hex: 0x1E66F5),
                accentSoft: Color(hex: 0xEA76CB),
                backgroundTop: Color(hex: 0xEFF1F5),
                backgroundBottom: Color(hex: 0xE6E9EF),
                chrome: Color(hex: 0xDCE0E8),
                chromeElevated: Color(hex: 0xFFFFFF),
                sidebar: Color(hex: 0xE6E9EF),
                panel: Color(hex: 0xFFFFFF),
                panelMuted: Color(hex: 0xEDEFF4),
                border: Color(hex: 0xBCC0CC),
                divider: Color(hex: 0xCCD0DA),
                textPrimary: Color(hex: 0x4C4F69),
                textSecondary: Color(hex: 0x5C5F77),
                textTertiary: Color(hex: 0x8C8FA1),
                selection: Color(hex: 0xDCE6FF),
                success: Color(hex: 0x40A02B),
                warning: Color(hex: 0xDF8E1D),
                danger: Color(hex: 0xD20F39)
            )
        case (.nord, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0x88C0D0),
                accentSoft: Color(hex: 0x81A1C1),
                backgroundTop: Color(hex: 0x2E3440),
                backgroundBottom: Color(hex: 0x222833),
                chrome: Color(hex: 0x3B4252),
                chromeElevated: Color(hex: 0x434C5E),
                sidebar: Color(hex: 0x2E3440),
                panel: Color(hex: 0x3B4252),
                panelMuted: Color(hex: 0x333A47),
                border: Color(hex: 0x4C566A),
                divider: Color(hex: 0x566175),
                textPrimary: Color(hex: 0xECEFF4),
                textSecondary: Color(hex: 0xD8DEE9),
                textTertiary: Color(hex: 0x95A2B9),
                selection: Color(hex: 0x434C5E),
                success: Color(hex: 0xA3BE8C),
                warning: Color(hex: 0xEBCB8B),
                danger: Color(hex: 0xBF616A)
            )
        case (.nord, .light):
            return ThemeDefinition(
                accent: Color(hex: 0x5E81AC),
                accentSoft: Color(hex: 0x81A1C1),
                backgroundTop: Color(hex: 0xECEFF4),
                backgroundBottom: Color(hex: 0xE5E9F0),
                chrome: Color(hex: 0xE5E9F0),
                chromeElevated: Color(hex: 0xF7F9FC),
                sidebar: Color(hex: 0xE5E9F0),
                panel: Color(hex: 0xF7F9FC),
                panelMuted: Color(hex: 0xECEFF4),
                border: Color(hex: 0xC9D0DB),
                divider: Color(hex: 0xD5DBE5),
                textPrimary: Color(hex: 0x2E3440),
                textSecondary: Color(hex: 0x4C566A),
                textTertiary: Color(hex: 0x7B879A),
                selection: Color(hex: 0xD9E2F2),
                success: Color(hex: 0x5E815B),
                warning: Color(hex: 0xB48E47),
                danger: Color(hex: 0xA34B59)
            )
        case (.solarized, .dark):
            return ThemeDefinition(
                accent: Color(hex: 0x2AA198),
                accentSoft: Color(hex: 0xB58900),
                backgroundTop: Color(hex: 0x002B36),
                backgroundBottom: Color(hex: 0x001F27),
                chrome: Color(hex: 0x073642),
                chromeElevated: Color(hex: 0x0B4B5A),
                sidebar: Color(hex: 0x002B36),
                panel: Color(hex: 0x073642),
                panelMuted: Color(hex: 0x06303A),
                border: Color(hex: 0x31525E),
                divider: Color(hex: 0x335964),
                textPrimary: Color(hex: 0xEEE8D5),
                textSecondary: Color(hex: 0x93A1A1),
                textTertiary: Color(hex: 0x6C7D81),
                selection: Color(hex: 0x0B4B5A),
                success: Color(hex: 0x859900),
                warning: Color(hex: 0xB58900),
                danger: Color(hex: 0xDC322F)
            )
        case (.solarized, .light):
            return ThemeDefinition(
                accent: Color(hex: 0x268BD2),
                accentSoft: Color(hex: 0x2AA198),
                backgroundTop: Color(hex: 0xFDF6E3),
                backgroundBottom: Color(hex: 0xF6EED7),
                chrome: Color(hex: 0xEEE8D5),
                chromeElevated: Color(hex: 0xFFFBF0),
                sidebar: Color(hex: 0xEEE8D5),
                panel: Color(hex: 0xFFFBF0),
                panelMuted: Color(hex: 0xF7F1DF),
                border: Color(hex: 0xD6CFBC),
                divider: Color(hex: 0xDDD6C4),
                textPrimary: Color(hex: 0x586E75),
                textSecondary: Color(hex: 0x657B83),
                textTertiary: Color(hex: 0x93A1A1),
                selection: Color(hex: 0xE6F0F8),
                success: Color(hex: 0x859900),
                warning: Color(hex: 0xB58900),
                danger: Color(hex: 0xCB4B16)
            )
        }
    }
}

private struct SidekickThemeKey: EnvironmentKey {
    static let defaultValue = SidekickTheme.resolve(
        settings: SidekickAppearanceSettings(),
        hostAppearance: HostAppearanceSnapshot(),
        systemColorScheme: .dark
    )
}

extension EnvironmentValues {
    var sidekickTheme: SidekickTheme {
        get { self[SidekickThemeKey.self] }
        set { self[SidekickThemeKey.self] = newValue }
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
