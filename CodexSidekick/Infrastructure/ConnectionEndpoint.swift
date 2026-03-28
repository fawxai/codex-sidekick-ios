import Darwin
import Foundation

enum SidekickConnectionEndpointKind: Equatable {
    case local
    case tailnet
    case remote
    case invalid

    init(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            self = .invalid
            return
        }

        if Self.isLocalHost(host) {
            self = .local
            return
        }

        if Self.isTailnetHost(host) {
            self = .tailnet
            return
        }

        self = .remote
    }

    var title: String {
        switch self {
        case .local:
            return "Local"
        case .tailnet:
            return "Tailscale"
        case .remote:
            return "Manual"
        case .invalid:
            return "Invalid"
        }
    }

    var guidance: String {
        switch self {
        case .local:
            return "Best for simulator and same-Mac pairing. Loopback `ws://` endpoints can omit the bearer token."
        case .tailnet:
            return "Use your node's `.ts.net` name or Tailscale IP. Tailnet pairing should always include a bearer token."
        case .remote:
            return "For advanced remote hosts outside your tailnet, prefer `wss://`. Non-local `ws://` bearer auth is intentionally blocked."
        case .invalid:
            return "Enter a valid `ws://` or `wss://` websocket URL."
        }
    }

    var requiresBearerToken: Bool {
        self == .tailnet
    }

    func supportsBearerToken(scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else {
            return false
        }

        return switch self {
        case .local, .tailnet:
            scheme == "ws" || scheme == "wss"
        case .remote:
            scheme == "wss"
        case .invalid:
            false
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }

        if let address = parseIPv4(host) {
            return (address & 0xFF00_0000) == 0x7F00_0000
        }

        if let bytes = parseIPv6(host) {
            return bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1
        }

        return false
    }

    private static func isTailnetHost(_ host: String) -> Bool {
        if host.hasSuffix(".ts.net") {
            return true
        }

        if let address = parseIPv4(host) {
            return (address & 0xFFC0_0000) == 0x6440_0000
        }

        if let bytes = parseIPv6(host) {
            return Array(bytes.prefix(6)) == [0xFD, 0x7A, 0x11, 0x5C, 0xA1, 0xE0]
        }

        return false
    }

    private static func parseIPv4(_ host: String) -> UInt32? {
        var address = in_addr()
        let parsed = host.withCString { inet_pton(AF_INET, $0, &address) }
        guard parsed == 1 else {
            return nil
        }
        return UInt32(bigEndian: address.s_addr)
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let parsed = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}
