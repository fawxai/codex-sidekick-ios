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
            return "Loopback pairing for Simulator and same-Mac testing. Connect straight to the websocket endpoint."
        case .tailscale:
            return "Preferred phone pairing flow. Paste the host discovery URL and the 8-character pairing code from Codex. You do not need to know the websocket URL or bearer token."
        case .manual:
            return "Advanced remote connection. Use `wss://` when you need bearer auth outside localhost or Tailscale."
        }
    }
}

struct PairingView: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel
    @State private var selectedPairingMode: PairingMode = .tailscale

    var body: some View {
        SidekickScrollScreen(
            maxContentWidth: 760,
            topSpacing: 6,
            bottomSpacing: 18
        ) {
            VStack(alignment: .leading, spacing: 18) {
                heroHeader
                pairingCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex Sidekick")
                .font(theme.codeFont(30, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var pairingCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pairingSectionTitle)
                        .font(theme.codeFont(18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(selectedPairingMode.guidance)
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
                }

                if selectedPairingMode == .tailscale {
                    TailscaleDiscoverySection(
                        appModel: appModel,
                        pairingMode: selectedPairingMode,
                        discoveryPlaceholder: discoveryPlaceholder,
                        discoverySecurityWarning: discoverySecurityWarning,
                        isPairingCodeValid: isPairingCodeValid
                    )
                } else {
                    DirectConnectionSection(
                        appModel: appModel,
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
            }
        }
    }

    private var discoveryPlaceholder: String {
        "http://your-mac.tailnet.ts.net:4231/v1/discover"
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

    private var pairingSectionTitle: String {
        switch selectedPairingMode {
        case .local:
            return "Connect Locally"
        case .tailscale:
            return "Pair over Tailscale"
        case .manual:
            return "Connect Manually"
        }
    }

    private var pairingCodeDescriptor: PairingCodeDescriptor {
        appModel.discoveredHost?.pairingCode
            ?? PairingCodeDescriptor(
                format: "base32",
                length: 8,
                alphabet: "23456789ABCDEFGHJKLMNPQRSTUVWXYZ",
                ttlSeconds: 0
            )
    }

    private var normalizedPairingCode: String {
        pairingCodeDescriptor.normalizedCode(from: appModel.pairingCodeInput)
    }

    private var isPairingCodeValid: Bool {
        normalizedPairingCode.count == pairingCodeDescriptor.length
    }

    private func pairingModeButton(_ mode: PairingMode) -> some View {
        let isSelected = selectedPairingMode == mode

        return Button {
            selectPairingMode(mode)
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

    private func selectPairingMode(_ mode: PairingMode) {
        guard selectedPairingMode != mode else {
            return
        }

        selectedPairingMode = mode
        applyPairingMode(mode)
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
    let isPairingCodeValid: Bool

    private var isBusy: Bool {
        appModel.isBusyPairing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TailscaleSetupCard()

            VStack(alignment: .leading, spacing: 6) {
                Text("Discovery URL")
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
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .sidekickInputFieldStyle()

                Text("The short code redeems the bearer token and websocket URL from the host over Tailscale. Use Manual only when you already have direct host credentials.")
                    .font(theme.codeFont(11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                            || !isPairingCodeValid
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

private struct TailscaleSetupCard: View {
    @Environment(\.sidekickTheme) private var theme

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended Tailscale Setup")
                    .font(theme.codeFont(12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    SetupStepRow(
                        index: "1",
                        text: "Ask Codex on your Mac to prepare Sidekick pairing over Tailscale and give you a discovery URL plus pairing code."
                    )
                    SetupStepRow(
                        index: "2",
                        text: "Paste the discovery URL here. It will usually look like `http://your-mac.tailnet.ts.net:4231/v1/discover` or `http://100.x.y.z:4231/v1/discover`."
                    )
                    SetupStepRow(
                        index: "3",
                        text: "Enter the short pairing code and tap Pair with Codex. The app will learn the websocket URL and bearer token from the host for you."
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.panelMuted)
        )
    }
}

private struct SetupStepRow: View {
    @Environment(\.sidekickTheme) private var theme

    let index: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(theme.codeFont(10, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.chromeElevated)
                )

            Text(text)
                .font(theme.font(12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DirectConnectionSection: View {
    @Environment(\.sidekickTheme) private var theme

    @Bindable var appModel: AppModel

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

            if appModel.connectionEndpointKind == .tailnet,
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

                    StatusPill(
                        text: pairingMode.title.uppercased(),
                        tone: pairingMode == .tailscale ? .success : .neutral
                    )
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
