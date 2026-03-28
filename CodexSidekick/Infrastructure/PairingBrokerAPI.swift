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

struct PairingSessionBootstrap: Sendable {
    let discovery: PairingDiscoveryRecord
    let draft: ConnectionDraft
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

private enum PairingBrokerRequestPhase {
    case discovery
    case claim

    var fallbackMessage: String {
        switch self {
        case .discovery:
            return "Could not discover that Codex host."
        case .claim:
            return "That pairing code could not be redeemed."
        }
    }
}

private enum PairingBrokerTransportKind {
    case urlSession
    case socketHTTP
}

private struct PairingBrokerTarget {
    let url: URL
    let transportKind: PairingBrokerTransportKind
}

enum PairingBrokerError: LocalizedError {
    case emptyInput
    case invalidDiscoveryURL
    case invalidCode
    case insecureDiscoveryTarget(host: String)
    case discoveryFailed(String)
    case claimFailed(String)
    case claimAfterDiscoveryFailed(hostLabel: String, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a Tailscale host, Tailscale IP, or discovery URL first."
        case .invalidDiscoveryURL:
            return "That discovery target is not valid. Use a `.ts.net` host, a Tailscale IP, or a full `/v1/discover` URL."
        case .invalidCode:
            return "Enter the 8-character pairing code from the host."
        case .insecureDiscoveryTarget(let host):
            return "Cleartext discovery is only allowed for local or tailnet hosts. `\(host)` must use `https://`."
        case .discoveryFailed(let message), .claimFailed(let message):
            return message
        case .claimAfterDiscoveryFailed(let hostLabel, let message):
            return "Discovered \(hostLabel), but could not redeem the pairing code: \(message)"
        }
    }
}

actor PairingBrokerClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let httpTransport = PairingBrokerHTTPTransport()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(from rawValue: String) async throws -> PairingDiscoveryRecord {
        let target = try discoveryTarget(from: rawValue)
        let (data, response) = try await data(
            for: target,
            phase: .discovery
        )
        try validateHTTP(response, data: data, phase: .discovery)
        return try decoder.decode(PairingDiscoveryRecord.self, from: data)
    }

    func redeemDiscoveryCode(from rawValue: String, code: String) async throws -> PairingSessionBootstrap {
        let discovery = try await discover(from: rawValue)

        do {
            let draft = try await claim(discovery: discovery, code: code)
            return PairingSessionBootstrap(discovery: discovery, draft: draft)
        } catch {
            throw PairingBrokerError.claimAfterDiscoveryFailed(
                hostLabel: discovery.hostLabel,
                message: error.localizedDescription
            )
        }
    }

    // SECURITY: ATS stays scoped in Info.plist. Cleartext discovery/claim is allowed only for
    // local or Tailscale hosts, and Tailscale IP endpoints use a tiny raw HTTP transport so we
    // do not need a global ATS bypass for `100.64.0.0/10`.
    private func data(
        for target: PairingBrokerTarget,
        phase: PairingBrokerRequestPhase,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: target.url)
        request.httpMethod = body == nil ? "GET" : "POST"
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        do {
            switch target.transportKind {
            case .urlSession:
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    switch phase {
                    case .discovery:
                        throw PairingBrokerError.discoveryFailed(phase.fallbackMessage)
                    case .claim:
                        throw PairingBrokerError.claimFailed(phase.fallbackMessage)
                    }
                }
                return (data, httpResponse)
            case .socketHTTP:
                return try await httpTransport.data(for: request)
            }
        } catch let error as PairingBrokerError {
            throw error
        } catch {
            switch phase {
            case .discovery:
                throw PairingBrokerError.discoveryFailed(error.localizedDescription)
            case .claim:
                throw PairingBrokerError.claimFailed(error.localizedDescription)
            }
        }
    }

    private func claim(discovery: PairingDiscoveryRecord, code: String) async throws -> ConnectionDraft {
        let normalizedCode = normalizedCode(from: code)
        guard !normalizedCode.isEmpty else {
            throw PairingBrokerError.invalidCode
        }

        let target = try requestTarget(from: discovery.claimURL)
        let body = try encoder.encode(PairingClaimParams(code: normalizedCode))
        let (data, response) = try await data(
            for: target,
            phase: .claim,
            body: body
        )
        try validateHTTP(response, data: data, phase: .claim)

        let payload = try decoder.decode(PairingClaimResponse.self, from: data)
        return ConnectionDraft(
            websocketURL: payload.websocketURL,
            authToken: payload.authToken
        )
    }

    private func validateHTTP(
        _ response: HTTPURLResponse,
        data: Data,
        phase: PairingBrokerRequestPhase
    ) throws {
        guard (200..<300).contains(response.statusCode) else {
            if let brokerError = try? decoder.decode(PairingBrokerErrorResponse.self, from: data),
               !brokerError.error.isEmpty {
                switch phase {
                case .discovery:
                    throw PairingBrokerError.discoveryFailed(brokerError.error)
                case .claim:
                    throw PairingBrokerError.claimFailed(brokerError.error)
                }
            }

            switch phase {
            case .discovery:
                throw PairingBrokerError.discoveryFailed(phase.fallbackMessage)
            case .claim:
                throw PairingBrokerError.claimFailed(phase.fallbackMessage)
            }
        }
    }

    private func discoveryTarget(from rawValue: String) throws -> PairingBrokerTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingBrokerError.emptyInput
        }

        if let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return try normalizedDiscoveryTarget(from: parsed, defaultScheme: scheme)
            case "ws":
                return try normalizedDiscoveryTarget(from: parsed, defaultScheme: "http")
            case "wss":
                return try normalizedDiscoveryTarget(from: parsed, defaultScheme: "https")
            default:
                throw PairingBrokerError.invalidDiscoveryURL
            }
        }

        guard let parsed = URL(string: "http://\(trimmed)") else {
            throw PairingBrokerError.invalidDiscoveryURL
        }
        return try normalizedDiscoveryTarget(from: parsed, defaultScheme: "http")
    }

    private func requestTarget(from rawValue: String) throws -> PairingBrokerTarget {
        guard let parsed = URL(string: rawValue),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host else {
            throw PairingBrokerError.invalidDiscoveryURL
        }

        let hostKind = SidekickHostKind(host: host)
        if scheme == "http", !hostKind.allowsCleartextDiscovery {
            throw PairingBrokerError.insecureDiscoveryTarget(host: host)
        }

        let transportKind: PairingBrokerTransportKind =
            hostKind.requiresSocketBootstrapTransport && scheme == "http" ? .socketHTTP : .urlSession
        return PairingBrokerTarget(url: parsed, transportKind: transportKind)
    }

    private func normalizedDiscoveryTarget(from url: URL, defaultScheme: String) throws -> PairingBrokerTarget {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              !host.isEmpty else {
            throw PairingBrokerError.invalidDiscoveryURL
        }

        components.scheme = defaultScheme
        if components.port == nil || components.port == 4222 {
            components.port = 4231
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1/discover"
        }

        let hostKind = SidekickHostKind(host: host)
        if defaultScheme == "http", !hostKind.allowsCleartextDiscovery {
            throw PairingBrokerError.insecureDiscoveryTarget(host: host)
        }

        guard let normalizedURL = components.url else {
            throw PairingBrokerError.invalidDiscoveryURL
        }

        let transportKind: PairingBrokerTransportKind =
            hostKind.requiresSocketBootstrapTransport && defaultScheme == "http" ? .socketHTTP : .urlSession
        return PairingBrokerTarget(url: normalizedURL, transportKind: transportKind)
    }

    private func normalizedCode(from rawValue: String) -> String {
        let allowed = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return rawValue
            .uppercased()
            .filter { allowed.contains($0) }
    }
}
