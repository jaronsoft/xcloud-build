import Foundation

struct MemoryService: Sendable {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func list(
        token: String,
        page: Int,
        size: Int = 30,
        keyword: String = "",
        category: String = "",
        status: String = "",
        projectId: String? = nil
    ) async throws -> PageResponse<AISMemoryItem> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        if !keyword.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if !category.isEmpty {
            query.append(URLQueryItem(name: "category", value: category))
        }
        if !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if let projectId {
            query.append(URLQueryItem(name: "projectId", value: projectId))
        }
        return try await api.get(
            "/api/ais/memories/my",
            query: query,
            accessToken: token
        )
    }

    func detail(token: String, id: String) async throws -> AISMemoryDetail {
        try await api.get("/api/ais/memories/my/\(id)", accessToken: token)
    }

    func create(token: String, draft: AISMemoryDraft) async throws -> String {
        try await api.post(
            "/api/ais/memories/my",
            body: request(from: draft),
            accessToken: token
        )
    }

    func update(
        token: String,
        id: String,
        draft: AISMemoryDraft
    ) async throws -> String {
        try await api.put(
            "/api/ais/memories/my/\(id)",
            body: request(from: draft),
            accessToken: token
        )
    }

    func changeStatus(
        token: String,
        id: String,
        action: String
    ) async throws {
        let _: String = try await api.put(
            "/api/ais/memories/my/\(id)/\(action)",
            body: AISMemoryEmptyRequest(),
            accessToken: token
        )
    }

    func delete(token: String, id: String) async throws {
        let _: String = try await api.delete(
            "/api/ais/memories/my/\(id)",
            accessToken: token
        )
    }

    func bulk(
        token: String,
        ids: [String],
        action: String
    ) async throws {
        let _: JSONValue = try await api.post(
            "/api/ais/memories/my/\(action)",
            body: AISMemoryBulkRequest(ids: ids, reason: nil),
            accessToken: token
        )
    }

    func startExtraction(token: String) async throws -> String {
        try await api.post(
            "/api/ais/memories/history-extractions",
            body: AISMemoryExtractionRequest(days: 180, maxTasks: 500),
            accessToken: token
        )
    }

    func extractionBatches(
        token: String
    ) async throws -> PageResponse<AISMemoryExtractionBatch> {
        try await api.get(
            "/api/ais/memories/history-extractions",
            query: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "size", value: "20")
            ],
            accessToken: token
        )
    }

    func extractionDetail(
        token: String,
        id: String
    ) async throws -> AISMemoryExtractionDetail {
        try await api.get(
            "/api/ais/memories/history-extractions/\(id)",
            accessToken: token
        )
    }

    private func request(from draft: AISMemoryDraft) -> AISMemoryWriteRequest {
        let memoryType = switch draft.scope {
        case "project": "project_rule"
        case "brand": "brand_rule"
        case "product": "product_fact"
        default: draft.category == "correction"
            ? "correction"
            : "personal_preference"
        }
        return AISMemoryWriteRequest(
            content: draft.content,
            editMode: "simple",
            scope: draft.scope,
            projectId: draft.scope == "project" ? draft.projectId : nil,
            brandKey: draft.brandKey.nilIfEmpty,
            productKey: draft.productKey.nilIfEmpty,
            category: draft.category,
            memoryType: memoryType,
            preferenceKey: draft.preferenceKey.nilIfEmpty,
            preferenceValueJson: draft.preferenceValueJson.nilIfEmpty,
            weight: draft.weight,
            rowVersion: draft.rowVersion
        )
    }
}
