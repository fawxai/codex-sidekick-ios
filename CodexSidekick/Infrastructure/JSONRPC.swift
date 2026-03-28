import Foundation

enum RPCID: Hashable, Codable, Sendable {
    case string(String)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .integer(try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            value
        case .integer(let value):
            String(value)
        }
    }
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func decoded<T: Decodable>(as type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: encodedData())
    }

    func encodedData(using encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

extension JSONValue: CustomStringConvertible {
    var description: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.formatted()
        case .bool(let value):
            return String(value)
        case .null:
            return "null"
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(self),
                  let text = String(data: data, encoding: .utf8) else {
                return "<json>"
            }
            return text
        }
    }
}

struct JSONRPCErrorBody: Codable, Error, Sendable {
    let code: Int
    let data: JSONValue?
    let message: String
}

struct JSONRPCInboundEnvelope: Decodable, Sendable {
    let id: RPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorBody?
}

struct JSONRPCRequestEnvelope<Params: Encodable & Sendable>: Encodable, Sendable {
    let id: RPCID
    let method: String
    let params: Params?
}

struct JSONRPCNotificationEnvelope<Params: Encodable & Sendable>: Encodable, Sendable {
    let method: String
    let params: Params?
}

struct JSONRPCResultEnvelope<Result: Encodable & Sendable>: Encodable, Sendable {
    let id: RPCID
    let result: Result
}

struct JSONRPCErrorEnvelope: Encodable, Sendable {
    let id: RPCID
    let error: JSONRPCErrorBody
}

struct EmptyCodexResponse: Decodable, Sendable {}
