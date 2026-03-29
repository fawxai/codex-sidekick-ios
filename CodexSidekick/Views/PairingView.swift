import Observation
import SwiftUI

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
            return "Tailnet pairing for your phone. Use the discovery flow above or a `.ts.net` / Tailscale IP websocket URL with a bearer token."
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

struct PairingView: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel

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

                        Text("Discovery first, then a short pairing claim.")
                            .font(theme.codeFont(24, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text("The phone discovers a real host surface first. Then it redeems a short-lived code to fetch the actual websocket token from that host without ever stuffing the token into a QR or pairing string.")
                            .font(theme.font(14))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 120), spacing: 10),
                        GridItem(.flexible(minimum: 120), spacing: 10),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    capabilityPill("Discovery")
                    capabilityPill("Short code")
                    capabilityPill("QR claim")
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

                    Text("Choose the trust path first. For Tailscale, paste the discovery target, enter the short code, and pair in one step. Local and manual paths expose the raw websocket connection directly.")
                        .font(theme.font(13))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
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

                if selectedPairingMode == .tailscale {
                    VStack(alignment: .leading, spacing: 14) {
                        TailscaleDiscoverySection(
                            appModel: appModel,
                            pairingMode: selectedPairingMode,
                            discoveryPlaceholder: discoveryPlaceholder,
                            discoverySecurityWarning: discoverySecurityWarning
                        )

                        Divider()
                            .overlay(theme.divider)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Direct Tailnet Connection")
                                .font(theme.codeFont(10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)

                            Text("If you already know the tailnet websocket URL, connect directly here. Tailnet websocket auth requires a bearer token.")
                                .font(theme.font(12))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        DirectConnectionSection(
                            appModel: appModel,
                            pairingMode: selectedPairingMode,
                            endpointTitle: appModel.connectionEndpointKind.title.uppercased(),
                            urlPlaceholder: urlPlaceholder,
                            tokenPlaceholder: tokenPlaceholder
                        )
                    }
                } else {
                    DirectConnectionSection(
                        appModel: appModel,
                        pairingMode: selectedPairingMode,
                        endpointTitle: appModel.connectionEndpointKind.title.uppercased(),
                        urlPlaceholder: urlPlaceholder,
                        tokenPlaceholder: tokenPlaceholder
                    )
                }

                if let pairingErrorMessage = appModel.pairingErrorMessage {
                    Text(pairingErrorMessage)
                        .font(theme.codeFont(12, weight: .medium))
                        .foregroundStyle(theme.danger)
                }

                if let errorMessage = appModel.connectionErrorMessage {
                    Text(errorMessage)
                        .font(theme.codeFont(12, weight: .medium))
                        .foregroundStyle(theme.danger)
                }

                Divider()
                    .overlay(theme.divider)

                pairingStatusRows
            }
        }
    }

    private var pairingStatusRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedPairingMode == .tailscale {
                VStack(alignment: .leading, spacing: 6) {
                    DotStatusRow(
                        title: "Host discovery",
                        value: "Tailnet discovery URL",
                        tone: .neutral
                    )
                    DotStatusRow(
                        title: "Claim",
                        value: "8-character one-time code",
                        tone: .neutral
                    )
                    DotStatusRow(
                        title: "QR",
                        value: "Deep link to host discovery, not the token",
                        tone: .neutral
                    )
                }
            }
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

    private var protocolCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pairing Contract")
                    .font(theme.codeFont(16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text("The phone uses a tiny discovery + claim step for pairing, then speaks the normal app-server protocol for everything live.")
                    .font(theme.font(13))
                    .foregroundStyle(theme.textSecondary)

                DotStatusRow(title: "Discover", value: "tailnet host metadata", tone: .neutral)
                DotStatusRow(title: "Claim", value: "short-lived one-time code", tone: .neutral)
                DotStatusRow(title: "Handshake", value: "initialize -> initialized", tone: .neutral)
                DotStatusRow(title: "Browse", value: "thread/list + thread/read", tone: .neutral)
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

    private var discoveryPlaceholder: String {
        "your-mac.tailnet.ts.net, 100.x.y.z, or a full /v1/discover URL"
    }

    private var discoverySecurityWarning: String? {
        let trimmedInput = appModel.discoveryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        let rawURLString: String
        if trimmedInput.contains("://") {
            rawURLString = trimmedInput
        } else {
            rawURLString = "http://\(trimmedInput)"
        }

        guard let url = URL(string: rawURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "ws" else {
            return nil
        }

        let hostKind = SidekickHostKind(host: url.host)
        guard hostKind == .remote else {
            return nil
        }

        return "Public discovery targets must use https://. Cleartext discovery is only allowed for local or tailnet hosts."
    }

    private var urlPlaceholder: String {
        switch selectedPairingMode {
        case .local:
            return "ws://127.0.0.1:4222"
        case .tailscale:
            return "ws://your-mac.tailnet.ts.net:4222 or ws://100.x.y.z:4222"
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
            if appModel.discoveryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appModel.discoveryInput = "http://your-mac.tailnet.ts.net:4231/v1/discover"
            }
        case .manual:
            appModel.connectionDraft.websocketURL = "wss://codex.example.com:\(port)"
        }
    }
}

private struct TailscaleDiscoverySection: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel

    let pairingMode: PairingMode
    let discoveryPlaceholder: String
    let discoverySecurityWarning: String?

    private var isBusy: Bool {
        appModel.isBusyPairing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Discovery Target")
                    .font(theme.codeFont(10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)

                TextField(discoveryPlaceholder, text: $appModel.discoveryInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .sidekickInputFieldStyle()

                if let discoverySecurityWarning {
                    Text(discoverySecurityWarning)
                        .font(theme.codeFont(11, weight: .medium))
                        .foregroundStyle(theme.warning)
                }
            }

            if let discoveredHost = appModel.discoveredHost {
                DiscoveredHostCard(
                    discoveredHost: discoveredHost,
                    pairingMode: pairingMode
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pairing Code")
                    .font(theme.codeFont(10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)

                TextField("ABCD3F7K", text: $appModel.pairingCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .sidekickInputFieldStyle()

                HStack(spacing: 8) {
                    Button(action: pairWithDiscoveryCode) {
                        HStack(spacing: 10) {
                            if isBusy {
                                ProgressView()
                                    .tint(theme.backgroundBottom)
                            }

                            Text(isBusy ? "Pairing..." : "Pair with Codex")
                        }
                    }
                    .buttonStyle(SidekickActionButtonStyle(tone: .primary, fullWidth: true))
                    .disabled(
                        appModel.discoveryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appModel.pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isBusy
                    )
                }
            }
        }
    }

    private func pairWithDiscoveryCode() {
        Task {
            await appModel.pairWithDiscoveryCode()
        }
    }
}

private struct DirectConnectionSection: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel

    let pairingMode: PairingMode
    let endpointTitle: String
    let urlPlaceholder: String
    let tokenPlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Websocket URL")
                        .font(theme.codeFont(10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)

                    Spacer(minLength: 8)

                    StatusPill(text: endpointTitle, tone: .neutral)
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

            if pairingMode == .tailscale,
               appModel.connectionDraft.normalizedAuthToken.isEmpty {
                Text("Direct Tailscale pairing will be rejected until a bearer token is present.")
                    .font(theme.codeFont(12, weight: .medium))
                    .foregroundStyle(theme.warning)
            }

            HStack(spacing: 8) {
                Button(action: connectDirectly) {
                    HStack(spacing: 10) {
                        if appModel.isConnecting {
                            ProgressView()
                                .tint(theme.backgroundBottom)
                        }

                        Text(appModel.isConnecting ? "Connecting..." : "Connect Directly")
                    }
                }
                .buttonStyle(SidekickActionButtonStyle(tone: .secondary, fullWidth: true))
                .disabled(appModel.isBusyPairing)
            }
        }
    }

    private func connectDirectly() {
        Task {
            await appModel.connect()
        }
    }
}

private struct DiscoveredHostCard: View {
    @Environment(\.sidekickTheme) private var theme

    let discoveredHost: PairingDiscoveryRecord
    let pairingMode: PairingMode

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(discoveredHost.hostLabel)
                            .font(theme.codeFont(15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)

                        Text(discoveredHost.websocketURL)
                            .font(theme.codeFont(11))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    StatusPill(text: pairingMode.title.uppercased(), tone: .success)
                }

                DotStatusRow(
                    title: "Discovery",
                    value: discoveredHost.discoveryURL,
                    tone: .neutral
                )
                DotStatusRow(
                    title: "Claim",
                    value: "\(discoveredHost.pairingCode.length)-character \(discoveredHost.pairingCode.format) code",
                    tone: .neutral
                )
                DotStatusRow(
                    title: "Expires",
                    value: "\(discoveredHost.pairingCode.ttlSeconds / 60) minutes",
                    tone: .neutral
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.panelMuted)
        )
    }
}
