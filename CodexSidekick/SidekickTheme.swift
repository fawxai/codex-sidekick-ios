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
