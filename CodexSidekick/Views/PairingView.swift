import Observation
import SwiftUI

struct PairingView: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @State private var pairingArtifactInput = ""

    private enum PairingMode: String, CaseIterable, Identifiable {
        case local
        case tailscale
        case manual

        var id: Self { self }

        var title: String {
            switch self {
            case .local:
                return "Local"
            case .tailscale:
                return "Tailscale"
            case .manual:
                return "Manual"
            }
        }

        var guidance: String {
            switch self {
            case .local:
                return "Loopback pairing for simulator and same-Mac testing. Bearer token is optional."
            case .tailscale:
                return "Tailnet pairing for your phone. Use a `.ts.net` name or Tailscale IP, and include a bearer token."
            case .manual:
                return "Advanced remote endpoint. Use `wss://` if you need bearer auth outside localhost or Tailscale."
            }
        }

        var securityNote: String {
            switch self {
            case .local:
                return "Token optional on loopback"
            case .tailscale:
                return "Token required on tailnet"
            case .manual:
                return "Prefer `wss://` for remote auth"
            }
        }

        var bestFor: String {
            switch self {
            case .local:
                return "Simulator + same-Mac testing"
            case .tailscale:
                return "Phone pairing across your tailnet"
            case .manual:
                return "Custom secure remote endpoints"
            }
        }
    }

    var body: some View {
        SidekickScrollScreen(
            maxContentWidth: 760,
            topSpacing: 6,
            bottomSpacing: 18
        ) {
            VStack(alignment: .leading, spacing: 14) {
                heroCard
                pairingCard
                protocolCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var selectedPairingMode: PairingMode {
        switch appModel.connectionEndpointKind {
        case .local:
            return .local
        case .tailnet:
            return .tailscale
        case .remote, .invalid:
            return .manual
        }
    }

    private var heroCard: some View {
        SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill(text: "MOBILE SIDEKICK", tone: .neutral)

                        Text("Codex on your phone, not a desktop app squeezed into portrait.")
                            .font(theme.codeFont(24, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("Pair to a live `codex app-server`, pick up a thread, hand the next step back to Codex, and clear approvals from a native iPhone shell.")
                            .font(theme.font(14))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 120), spacing: 10),
                        GridItem(.flexible(minimum: 120), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    capabilityPill("Pairing")
                    capabilityPill("Thread list")
                    capabilityPill("Open live")
                    capabilityPill("Approvals")
                }
            }
        }
    }

    private var pairingCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pair with Codex")
                        .font(theme.codeFont(18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text("Use the websocket endpoint exposed by `codex app-server`. Local loopback and authenticated Tailscale pairing are both first-class paths here.")
                        .font(theme.font(13))
                        .foregroundStyle(theme.textSecondary)
                }

                quickImportSection

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Path")
                        .font(theme.codeFont(10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)

                    HStack(spacing: 8) {
                        ForEach(PairingMode.allCases) { mode in
                            pairingModeButton(mode)
                        }
                    }

                    Text(selectedPairingMode.guidance)
                        .font(theme.font(12))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Websocket URL")
                            .font(theme.codeFont(10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)

                        Spacer(minLength: 8)

                        StatusPill(text: appModel.connectionEndpointKind.title.uppercased(), tone: .neutral)
                    }

                    TextField(urlPlaceholder, text: $appModel.connectionDraft.websocketURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sidekickInputFieldStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bearer Token")
                        .font(theme.codeFont(10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)

                    SecureField(tokenPlaceholder, text: $appModel.connectionDraft.authToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sidekickInputFieldStyle()
                }

                if selectedPairingMode == .tailscale,
                   appModel.connectionDraft.normalizedAuthToken.isEmpty {
                    Text("Tailscale pairing will be rejected until a bearer token is present.")
                        .font(theme.codeFont(12, weight: .medium))
                        .foregroundStyle(theme.warning)
                }

                if let errorMessage = appModel.connectionErrorMessage {
                    Text(errorMessage)
                        .font(theme.codeFont(12, weight: .medium))
                        .foregroundStyle(theme.danger)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appModel.connect()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if appModel.isConnecting {
                                ProgressView()
                                    .tint(theme.backgroundBottom)
                            }

                            Text(appModel.isConnecting ? "Pairing..." : "Pair to Codex")
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .primary, fullWidth: true))
                    .disabled(appModel.isConnecting)
                }

                Divider()
                    .overlay(theme.divider)

                VStack(alignment: .leading, spacing: 8) {
                    DotStatusRow(
                        title: "Transport",
                        value: "JSON-RPC over websocket",
                        tone: .neutral
                    )
                    DotStatusRow(
                        title: "Security",
                        value: selectedPairingMode.securityNote,
                        tone: .neutral
                    )
                    DotStatusRow(
                        title: "Best for",
                        value: selectedPairingMode.bestFor,
                        tone: .neutral
                    )
                }
            }
        }
    }

    private var quickImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Import")
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            Text("Paste a pairing code from the desktop plugin, or scan a QR code that opens this app. The phone will import the endpoint and token together.")
                .font(theme.font(12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("codex-sidekick:v1:...", text: $pairingArtifactInput, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .sidekickInputFieldStyle()

            HStack(spacing: 8) {
                Button {
                    let artifact = pairingArtifactInput
                    Task {
                        await appModel.importPairingArtifact(artifact)
                        pairingArtifactInput = ""
                    }
                } label: {
                    Text("Import & Pair")
                }
                .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))
                .disabled(pairingArtifactInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isConnecting)
            }
        }
    }

    private var protocolCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("First Vertical Slice")
                    .font(theme.codeFont(16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text("The initial mobile flow follows the real app-server model instead of inventing a side protocol.")
                    .font(theme.font(13))
                    .foregroundStyle(theme.textSecondary)

                DotStatusRow(title: "Handshake", value: "initialize -> initialized", tone: .neutral)
                DotStatusRow(title: "Browse", value: "thread/list + thread/read", tone: .neutral)
                DotStatusRow(title: "Open live", value: "thread/resume", tone: .neutral)
                DotStatusRow(title: "Handoff", value: "turn/start", tone: .neutral)
                DotStatusRow(title: "Approvals", value: "server requests", tone: .neutral)
            }
        }
    }

    private func capabilityPill(_ text: String) -> some View {
        Text(text.uppercased())
            .font(theme.codeFont(11, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.chromeElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }

    private var urlPlaceholder: String {
        switch selectedPairingMode {
        case .local:
            return "ws://127.0.0.1:4222"
        case .tailscale:
            return "ws://your-mac.tailnet.ts.net:4222"
        case .manual:
            return "wss://codex.example.com:4222"
        }
    }

    private var tokenPlaceholder: String {
        switch selectedPairingMode {
        case .local:
            return "Optional bearer token"
        case .tailscale:
            return "Required bearer token"
        case .manual:
            return "Optional bearer token"
        }
    }

    private func pairingModeButton(_ mode: PairingMode) -> some View {
        let isSelected = selectedPairingMode == mode

        return Button {
            applyPairingMode(mode)
        } label: {
            Text(mode.title.uppercased())
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? theme.chromeElevated : theme.panelMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? theme.accentSoft.opacity(0.7) : theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyPairingMode(_ mode: PairingMode) {
        let port = URL(string: appModel.connectionDraft.normalizedWebsocketURL)?.port ?? 4222

        switch mode {
        case .local:
            appModel.connectionDraft.websocketURL = "ws://127.0.0.1:\(port)"
        case .tailscale:
            appModel.connectionDraft.websocketURL = "ws://your-mac.tailnet.ts.net:\(port)"
        case .manual:
            appModel.connectionDraft.websocketURL = "wss://codex.example.com:\(port)"
        }
    }
}
