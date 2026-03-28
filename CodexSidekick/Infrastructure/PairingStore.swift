import Foundation
import Security

struct StoredPairing: Codable, Sendable {
    let websocketURL: String

    var endpointKind: SidekickConnectionEndpointKind {
        guard let url = URL(string: websocketURL) else {
            return .invalid
        }
        return SidekickConnectionEndpointKind(url: url)
    }

    var suggestedDiscoveryTarget: String {
        guard let url = URL(string: websocketURL),
              var components = URLComponents(string: websocketURL),
              let host = components.host else {
            return ""
        }

        if endpointKind == .tailnet || endpointKind == .local || host == "localhost" || host == "127.0.0.1" {
            components.scheme = "http"
            components.port = 4231
            components.path = "/v1/discover"
            components.query = nil
            components.fragment = nil
            return components.string ?? "http://\(host):4231/v1/discover"
        }

        return ""
    }
}

struct ConnectionDraft: Sendable {
    var websocketURL: String = "ws://127.0.0.1:4222"
    var authToken: String = ""

    var normalizedWebsocketURL: String {
        websocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAuthToken: String {
        authToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var endpointKind: SidekickConnectionEndpointKind {
        guard let url = URL(string: normalizedWebsocketURL) else {
            return .invalid
        }
        return SidekickConnectionEndpointKind(url: url)
    }
}

struct PairingStore {
    private let defaultsKey = "codex.sidekick.pairing"
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(
        service: "com.fawxai.codex-sidekick",
        account: "remote-auth-token"
    )

    func load() -> (stored: StoredPairing, token: String?)? {
        guard let data = defaults.data(forKey: defaultsKey),
              let pairing = try? JSONDecoder().decode(StoredPairing.self, from: data) else {
            return nil
        }
        return (pairing, try? keychain.load())
    }

    func save(_ draft: ConnectionDraft) throws -> StoredPairing {
        let pairing = StoredPairing(websocketURL: draft.normalizedWebsocketURL)
        let data = try JSONEncoder().encode(pairing)
        defaults.set(data, forKey: defaultsKey)
        if draft.normalizedAuthToken.isEmpty {
            try keychain.delete()
        } else {
            try keychain.save(draft.normalizedAuthToken)
        }
        return pairing
    }

    func clear() throws {
        defaults.removeObject(forKey: defaultsKey)
        try keychain.delete()
    }
}

private struct KeychainStore {
    let service: String
    let account: String

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        try delete()
        let status = SecItemAdd(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ] as CFDictionary,
            nil
        )
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func load() throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &item
        )

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

private enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}
