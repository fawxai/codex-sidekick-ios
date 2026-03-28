import Foundation
import Network

struct PairingBrokerHTTPTransport {
    private final class ConnectionStateBox: @unchecked Sendable {
        var hasResumed = false
    }

    private final class ReceiveStateBox: @unchecked Sendable {
        var hasResumed = false
        var buffer = Data()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              url.scheme?.lowercased() == "http",
              let host = url.host,
              let port = nwPort(for: url.port ?? 80) else {
            throw URLError(.badURL)
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "codex.sidekick.pairing.http")

        do {
            try await waitUntilReady(connection, on: queue)
            let payload = try requestPayload(for: request, host: host)
            try await send(payload, over: connection)
            let responseData = try await receiveAll(from: connection)
            connection.cancel()
            return try parseResponse(responseData, for: url)
        } catch {
            connection.cancel()
            throw error
        }
    }

    private func nwPort(for rawValue: Int) -> NWEndpoint.Port? {
        guard let value = UInt16(exactly: rawValue) else {
            return nil
        }
        return NWEndpoint.Port(rawValue: value)
    }

    private func waitUntilReady(_ connection: NWConnection, on queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let stateBox = ConnectionStateBox()

            connection.stateUpdateHandler = { state in
                guard !stateBox.hasResumed else {
                    return
                }

                switch state {
                case .ready:
                    stateBox.hasResumed = true
                    continuation.resume()
                case .failed(let error):
                    stateBox.hasResumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    stateBox.hasResumed = true
                    continuation.resume(throwing: URLError(.networkConnectionLost))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private func send(_ payload: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveAll(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let state = ReceiveStateBox()
            receiveNext(from: connection, state: state, continuation: continuation)
        }
    }

    private func receiveNext(
        from connection: NWConnection,
        state: ReceiveStateBox,
        continuation: CheckedContinuation<Data, Error>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            guard !state.hasResumed else {
                return
            }

            if let error {
                state.hasResumed = true
                continuation.resume(throwing: error)
                return
            }

            if let content, !content.isEmpty {
                state.buffer.append(content)
            }

            if isComplete {
                state.hasResumed = true
                continuation.resume(returning: state.buffer)
            } else {
                receiveNext(from: connection, state: state, continuation: continuation)
            }
        }
    }

    private func requestPayload(for request: URLRequest, host: String) throws -> Data {
        let method = request.httpMethod ?? "GET"
        let path = requestPath(for: request.url)
        let body = request.httpBody ?? Data()
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(hostHeaderValue(host: host, url: request.url))",
            "Accept: application/json",
            "Connection: close",
        ]

        if let contentType = request.value(forHTTPHeaderField: "Content-Type") {
            lines.append("Content-Type: \(contentType)")
        }

        if body.isEmpty == false {
            lines.append("Content-Length: \(body.count)")
        }

        let headers = lines.joined(separator: "\r\n") + "\r\n\r\n"
        guard var data = headers.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        data.append(body)
        return data
    }

    private func hostHeaderValue(host: String, url: URL?) -> String {
        let bracketedHost = host.contains(":") ? "[\(host)]" : host
        guard let url,
              let port = url.port else {
            return bracketedHost
        }

        let scheme = url.scheme?.lowercased()
        let usesDefaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        return usesDefaultPort ? bracketedHost : "\(bracketedHost):\(port)"
    }

    private func requestPath(for url: URL?) -> String {
        guard let url else {
            return "/"
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let percentEncodedPath = components?.percentEncodedPath ?? ""
        let path = percentEncodedPath.isEmpty ? "/" : percentEncodedPath
        if let query = components?.percentEncodedQuery, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    private func parseResponse(_ rawResponse: Data, for url: URL) throws -> (Data, HTTPURLResponse) {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = rawResponse.range(of: separator) else {
            throw URLError(.badServerResponse)
        }

        let headerData = rawResponse.subdata(in: 0..<range.lowerBound)
        let bodyData = rawResponse.subdata(in: range.upperBound..<rawResponse.endIndex)

        guard let headerString = String(data: headerData, encoding: .utf8) ??
            String(data: headerData, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }

        let headerLines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = headerLines.first else {
            throw URLError(.badServerResponse)
        }

        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2,
              let statusCode = Int(statusParts[1]) else {
            throw URLError(.badServerResponse)
        }

        var headerFields: [String: String] = [:]
        for line in headerLines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            headerFields[key] = value
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        ) else {
            throw URLError(.badServerResponse)
        }

        return (bodyData, response)
    }
}
