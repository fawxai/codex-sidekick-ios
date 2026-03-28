import Foundation

struct PairingCodeDescriptor: Decodable, Sendable {
    let format: String
    let length: Int
    let alphabet: String
    let ttlSeconds: Int
}

struct PairingDiscoveryRecord: Decodable, Identifiable, Sendable {
    let version: Int
    let hostLabel: String
    let discoveryURL: String
    let claimURL: String
    let websocketURL: String
    let connectionKind: String
    let pairingCode: PairingCodeDescriptor

    var id: String {
        discoveryURL
    }
}

private struct PairingClaimParams: Encodable, Sendable {
    let code: String
}

private struct PairingClaimResponse: Decodable, Sendable {
    let version: Int
    let hostLabel: String?
    let websocketURL: String
    let authToken: String
}

private struct PairingBrokerErrorResponse: Decodable, Sendable {
    let error: String
}

enum PairingBrokerError: LocalizedError {
    case emptyInput
    case invalidDiscoveryURL
    case invalidCode
    case discoveryFailed(String)
    case claimFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a Tailscale host, Tailscale IP, or discovery URL first."
        case .invalidDiscoveryURL:
            return "That discovery target is not valid. Use a `.ts.net` host, a Tailscale IP, or a full `/v1/discover` URL."
        case .invalidCode:
            return "Enter the 8-character pairing code from the host."
        case .discoveryFailed(let message), .claimFailed(let message):
            return message
        }
    }
}

actor PairingBrokerClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(from rawValue: String) async throws -> PairingDiscoveryRecord {
        let url = try discoveryURL(from: rawValue)
        let (data, response) = try await session.data(from: url)
        try validateHTTP(response, data: data, fallback: "Could not discover that Codex host.")
        return try decoder.decode(PairingDiscoveryRecord.self, from: data)
    }

    func claim(discovery: PairingDiscoveryRecord, code: String) async throws -> ConnectionDraft {
        let normalizedCode = normalizedCode(from: code)
        guard !normalizedCode.isEmpty else {
            throw PairingBrokerError.invalidCode
        }

        guard let claimURL = URL(string: discovery.claimURL) else {
            throw PairingBrokerError.invalidDiscoveryURL
        }

        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(PairingClaimParams(code: normalizedCode))

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data, fallback: "That pairing code could not be redeemed.")

        let payload = try decoder.decode(PairingClaimResponse.self, from: data)
        return ConnectionDraft(
            websocketURL: payload.websocketURL,
            authToken: payload.authToken
        )
    }

    private func validateHTTP(_ response: URLResponse, data: Data, fallback: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PairingBrokerError.discoveryFailed(fallback)
        }

        guard (200..<300).contains(http.statusCode) else {
            if let brokerError = try? decoder.decode(PairingBrokerErrorResponse.self, from: data),
               !brokerError.error.isEmpty {
                throw PairingBrokerError.claimFailed(brokerError.error)
            }
            throw PairingBrokerError.discoveryFailed(fallback)
        }
    }

    private func discoveryURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingBrokerError.emptyInput
        }

        if let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return try normalizedDiscoveryURL(from: parsed, defaultScheme: scheme)
            case "ws":
                return try normalizedDiscoveryURL(from: parsed, defaultScheme: "http")
            case "wss":
                return try normalizedDiscoveryURL(from: parsed, defaultScheme: "https")
            default:
                throw PairingBrokerError.invalidDiscoveryURL
            }
        }

        guard let parsed = URL(string: "http://\(trimmed)") else {
            throw PairingBrokerError.invalidDiscoveryURL
        }
        return try normalizedDiscoveryURL(from: parsed, defaultScheme: "http")
    }

    private func normalizedDiscoveryURL(from url: URL, defaultScheme: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false else {
            throw PairingBrokerError.invalidDiscoveryURL
        }

        components.scheme = defaultScheme
        if components.port == nil || components.port == 4222 {
            components.port = 4231
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1/discover"
        }

        guard let normalizedURL = components.url else {
            throw PairingBrokerError.invalidDiscoveryURL
        }
        return normalizedURL
    }

    private func normalizedCode(from rawValue: String) -> String {
        let allowed = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return rawValue
            .uppercased()
            .filter { allowed.contains($0) }
    }
}
