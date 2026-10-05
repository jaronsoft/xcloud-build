import Foundation

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    var id: String
    var localID: String? = nil
    let role: ChatRole
    var content: String
    var statusMessage: String?
    var userRating: Int
    var logDate: String?
    var responseTimeMilliseconds: Int?
    var isExpired = false
}

struct ChatHistoryMessage: Decodable {
    let Id: FlexibleStringID
    let Role: String?
    let Content: String?
    let CreateTime: String?
    let UserRating: Int?
}

struct StreamAskRequest: Encodable {
    let question: String
    let sessionId: Int64?
    let tenantId: Int64
    let source: String
    let userName: String
    let fingerprint: String
    let userId: Int64?
}

struct RatingRequest: Encodable {
    let MessageId: Int64
    let Rating: Int?
    let Comment: String
    let LogDate: String?
    let TenantId: Int64
}

struct ClearHistoryRequest: Encodable {
    let Fingerprint: String
    let TenantId: Int64
}

struct VoiceResponse: Decodable {
    let question: String
}
