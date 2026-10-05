import Foundation

enum SSEEvent: Equatable, Sendable {
    case status(String)
    case content(String)
    case metadata(messageID: String?, sessionID: String?, logDate: String?)
    case failure(String)
    case done
}

struct SSEParser: Sendable {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        var events: [SSEEvent] = []
        let delimiter = Data([0x0A, 0x0A])
        while let range = buffer.range(of: delimiter) {
            let packet = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            events.append(contentsOf: parsePacket(packet))
        }
        return events
    }

    mutating func finish() -> [SSEEvent] {
        guard !buffer.isEmpty else { return [] }
        let packet = buffer
        buffer.removeAll()
        return parsePacket(packet)
    }

    private func parsePacket(_ packet: Data) -> [SSEEvent] {
        guard let text = String(data: packet, encoding: .utf8) else {
            return []
        }
        let payload = text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                var value = String(line)
                if value.hasSuffix("\r") { value.removeLast() }
                guard value.hasPrefix("data:") else { return nil }
                value.removeFirst(5)
                if value.hasPrefix(" ") { value.removeFirst() }
                return value
            }
            .joined(separator: "\n")
        guard !payload.isEmpty else { return [] }
        if payload == "[DONE]" {
            return [.done]
        } else if payload.hasPrefix("__STATUS__") {
            let json = String(payload.dropFirst("__STATUS__".count))
            return [.status(jsonValue("msg", from: json) ?? json)]
        } else if payload.hasPrefix("__ERROR__") {
            let json = String(payload.dropFirst("__ERROR__".count))
            return [
                .failure(
                    jsonValue("message", from: json)
                        ?? (json.isEmpty
                            ? String(localized: "chat.service_unavailable")
                            : json)
                )
            ]
        } else if payload.hasPrefix("[API_ERROR]") {
            return [.failure(String(localized: "chat.service_unavailable"))]
        } else if payload.hasPrefix("__METADATA__") {
            let json = String(payload.dropFirst("__METADATA__".count))
            return [
                .metadata(
                    messageID: jsonScalar("id", from: json),
                    sessionID: jsonScalar("sessionId", from: json),
                    logDate: jsonValue("logDate", from: json)
                )
            ]
        }
        return [.content(jsonValue("content", from: payload) ?? payload)]
    }

    private func jsonValue(_ key: String, from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String else {
            return nil
        }
        return value
    }

    private func jsonScalar(_ key: String, from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
