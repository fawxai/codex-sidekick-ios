import Foundation

struct PairingArtifactPayload: Codable, Sendable {
    let version: Int
    let websocketURL: String
    let authToken: String
}

enum PairingArtifact {
    static let codePrefix = "codex-sidekick:v1:"
    static let urlScheme = "codexsidekick"
    private static let pairHost = "pair"

    static func connectionDraft(from rawValue: String) throws -> ConnectionDraft {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingArtifactError.emptyInput
        }

        let code = try pairingCode(from: trimmed)
        let payload = try payload(fromCode: code)

        let websocketURL = payload.websocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !websocketURL.isEmpty else {
            throw PairingArtifactError.missingWebsocketURL
        }

        return ConnectionDraft(
            websocketURL: websocketURL,
            authToken: payload.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func pairingCode(from rawValue: String) throws -> String {
        if rawValue.hasPrefix(codePrefix) {
            return rawValue
        }

        guard let url = URL(string: rawValue),
              url.scheme?.lowercased() == urlScheme,
              url.host?.lowercased() == pairHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw PairingArtifactError.unrecognizedFormat
        }

        return code
    }

    private static func payload(fromCode code: String) throws -> PairingArtifactPayload {
        guard code.hasPrefix(codePrefix) else {
            throw PairingArtifactError.unrecognizedFormat
        }

        let encoded = String(code.dropFirst(codePrefix.count))
        guard let data = dataFromBase64URL(encoded) else {
            throw PairingArtifactError.corruptPayload
        }

        let payload = try JSONDecoder().decode(PairingArtifactPayload.self, from: data)
        guard payload.version == 1 else {
            throw PairingArtifactError.unsupportedVersion(payload.version)
        }

        return payload
    }

    private static func dataFromBase64URL(_ encoded: String) -> Data? {
        let base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - (base64.count % 4)) % 4
        return Data(base64Encoded: base64 + String(repeating: "=", count: padding))
    }
}

enum PairingArtifactError: LocalizedError {
    case emptyInput
    case unrecognizedFormat
    case corruptPayload
    case unsupportedVersion(Int)
    case missingWebsocketURL

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste a pairing code or open a sidekick pairing link."
        case .unrecognizedFormat:
            return "That pairing code is not recognized."
        case .corruptPayload:
            return "That pairing code is unreadable."
        case .unsupportedVersion(let version):
            return "That pairing code uses unsupported version \(version)."
        case .missingWebsocketURL:
            return "That pairing code is missing the websocket URL."
        }
    }
}
