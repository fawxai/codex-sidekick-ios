import Foundation

struct PairingLinkPayload: Sendable {
    let discoveryURL: String
    let code: String?
}

enum PairingLink {
    static let urlScheme = "codexsidekick"
    private static let pairHost = "pair"
    private static let maxURLLength = 2048

    static func parse(_ rawValue: String) throws -> PairingLinkPayload {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingLinkError.emptyInput
        }

        guard trimmed.count <= maxURLLength else {
            throw PairingLinkError.oversizedInput
        }

        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == urlScheme,
              url.host?.lowercased() == pairHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let discoveryURL = components.queryItems?.first(where: { $0.name == "discovery" })?.value,
              !discoveryURL.isEmpty else {
            throw PairingLinkError.unrecognizedFormat
        }

        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        return PairingLinkPayload(discoveryURL: discoveryURL, code: code)
    }
}

enum PairingLinkError: LocalizedError {
    case emptyInput
    case oversizedInput
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Open a pairing QR or deep link from the host."
        case .oversizedInput:
            return "That pairing link is too large. Re-open the pairing QR or link from the host."
        case .unrecognizedFormat:
            return "That sidekick pairing link is not recognized."
        }
    }
}
