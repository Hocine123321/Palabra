import Foundation

/// A Codable, Sendable JSON value. The only data type that crosses the capability boundary,
/// so `Features/Artifacts` never needs to know app model types.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// Only for integral numbers: 3 -> 3, 3.5 -> nil.
    var intValue: Int? {
        guard case .number(let value) = self, value == value.rounded(), abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Plain Foundation objects (`NSNull`, `Bool`, `Double`, `String`, `[Any]`, `[String: Any]`),
    /// for `WKWebView` replies and for passing a JSON schema to the AI client.
    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.foundationObject)
        case .object(let value): return value.mapValues(\.foundationObject)
        }
    }

    /// The reverse of `foundationObject`, for `WKScriptMessage.body`. `nil` if anything is not JSON.
    static func from(foundation: Any) -> JSONValue? {
        switch foundation {
        case is NSNull:
            return .null
        case let number as NSNumber:
            // JavaScript booleans arrive as CFBoolean-backed NSNumbers.
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let text as String:
            return .string(text)
        case let items as [Any]:
            let converted = items.compactMap { from(foundation: $0) }
            return converted.count == items.count ? .array(converted) : nil
        case let object as [String: Any]:
            var converted: [String: JSONValue] = [:]
            for (key, value) in object {
                guard let item = from(foundation: value) else { return nil }
                converted[key] = item
            }
            return .object(converted)
        default:
            return nil
        }
    }

    /// Stable (sorted-key) compact JSON.
    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}
