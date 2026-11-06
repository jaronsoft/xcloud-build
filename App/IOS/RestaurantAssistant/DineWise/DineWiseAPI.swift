import Foundation

struct DineWiseStore: Decodable, Identifiable {
    let Id: String
    let Name: String
    let Mode: String
    let Roles: [String]
    let BusinessType: String?
    let Address: String?
    let Introduction: String?
    let PaymentMethods: [String]?
    let HasPhoto: Bool?

    var id: String { Id }
}

struct DineWiseOperatorStore: Decodable, Identifiable {
    let Id: String
    let Name: String
    let BusinessType: String
    let OwnerEmail: String
    let Address: String
    let Introduction: String?
    let HasPhoto: Bool
    let PaymentMethods: [String]

    var id: String { Id }
}

struct DineWiseSession: Decodable {
    let UserId: String
    let AccessToken: String
    let Email: String
}

struct DineWiseOperatorSession: Decodable {
    let Username: String
    let AccessToken: String
}

struct DineWiseMember: Decodable, Identifiable {
    let Id: String
    let UserId: String
    let Email: String?
    let Role: String
    let Enabled: Bool

    var id: String { Id }
}

struct DineWiseSubmission: Decodable, Identifiable {
    let Id: String
    let SubmittedByUserId: String
    let SubmittedRole: String
    let Kind: String
    let BusinessDate: String
    let OriginalText: String
    let Status: String
    let Version: Int

    var id: String { Id }
}

struct DineWiseSubmissionField: Decodable, Identifiable {
    let FieldKey: String
    let OriginalValue: String?
    let OriginalUnit: String?
    let CurrentValue: String
    let CurrentUnit: String?
    let NormalizedValue: String?
    let NormalizedUnit: String?

    var id: String { FieldKey }
}

struct DineWiseSubmissionDetail: Decodable {
    let Submission: DineWiseSubmission
    let Fields: [DineWiseSubmissionField]
    let Files: [DineWiseSubmissionFile]
}

struct DineWiseRecommendation: Decodable, Identifiable {
    let Id: String
    let SourceSubmissionId: String
    let Title: String
    let Rationale: String
    let Steps: String
    let TargetRole: String
    let Status: String
    let Version: Int
    let DecisionReason: String?
    let RemindOn: String?
    let TaskId: String?

    var id: String { Id }
}

struct DineWiseTask: Decodable, Identifiable {
    let Id: String
    let Title: String
    let Steps: String
    let TargetRole: String
    let AssignedUserId: String?
    let Status: String
    let Version: Int
    let Receipt: String?
    let ReviewNote: String?

    var id: String { Id }
}

struct DineWiseDailyReport: Decodable {
    let StoreId: String
    let Mode: String
    let BusinessDate: String
    let RevenueYuan: Decimal?
    let Orders: Int?
    let Tables: Int?
    let RevenuePerTableYuan: Decimal?
    let SourceSubmissionId: String?
    let SourceVersion: Int?
    let MissingReasons: [String]
}

struct DineWiseSubmissionFile: Decodable, Identifiable {
    let Id: String
    let FileName: String
    let SizeBytes: Int

    var id: String { Id }
}

private struct DineWiseSubmissionPage: Decodable {
    let Total: Int
    let Items: [DineWiseSubmission]
}

private struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let response: Value?
    let msg: String?
}

private struct EmptyResult: Decodable {}

enum DineWiseAPIError: LocalizedError {
    case invalidURL
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "API 地址无效，请检查应用配置。"
        case let .failed(message): message
        }
    }
}

struct DineWiseAPI {
    private let baseURL = Bundle.main.object(forInfoDictionaryKey: "DINEWISE_API_BASE_URL") as? String ?? ""

    private func request<Value: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil,
        idempotencyKey: String? = nil,
        role: String? = nil
    ) async throws -> Value {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant\(path)", relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else {
            throw DineWiseAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let role { request.setValue(role, forHTTPHeaderField: "X-DineWise-Role") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              envelope.success,
              let result = envelope.response else {
            throw DineWiseAPIError.failed(envelope.msg ?? "请求失败")
        }
        return result
    }

    func sendCode(email: String) async throws {
        let _: EmptyResult = try await request(
            "/auth/email/send-code", method: "POST", body: ["Email": email]
        )
    }

    func login(email: String, code: String) async throws -> DineWiseSession {
        try await request("/auth/email", method: "POST", body: ["Email": email, "Code": code])
    }

    func operatorLogin(username: String, password: String) async throws -> DineWiseOperatorSession {
        try await request("/operator/auth/login", method: "POST",
                          body: ["Username": username, "Password": password])
    }

    func operatorStores(token: String) async throws -> [DineWiseOperatorStore] {
        try await request("/operator/stores", token: token)
    }

    func operatorCreateStore(token: String, name: String, businessType: String,
                             ownerEmail: String, address: String, introduction: String,
                             paymentMethods: [String], latitude: Double?, longitude: Double?,
                             idempotencyKey: String) async throws -> DineWiseOperatorStore {
        var body: [String: Any] = [
            "Name": name, "BusinessType": businessType, "OwnerEmail": ownerEmail,
            "Address": address, "Introduction": introduction,
            "PaymentMethods": paymentMethods, "TimeZone": "Asia/Shanghai",
            "BusinessDayCutoffMinutes": 0
        ]
        if let latitude, let longitude {
            body["Latitude"] = latitude
            body["Longitude"] = longitude
        }
        return try await request("/operator/stores", method: "POST", body: body,
                                 token: token, idempotencyKey: idempotencyKey)
    }

    func operatorUploadPhoto(token: String, storeID: String, data: Data) async throws -> DineWiseOperatorStore {
        guard data.count <= 5 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("门店照片不能超过 5 MB。")
        }
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/operator/stores/\(storeID)/photo",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"store.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var upload = URLRequest(url: url)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (responseData, response) = try await URLSession.shared.upload(for: upload, from: body)
        let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseOperatorStore>.self,
                                                from: responseData)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              envelope.success, let store = envelope.response else {
            throw DineWiseAPIError.failed(envelope.msg ?? "门店照片上传失败")
        }
        return store
    }

    func stores(token: String) async throws -> [DineWiseStore] {
        try await request("/stores", token: token)
    }

    func createDemoStore(name: String, token: String, idempotencyKey: String) async throws {
        let _: DineWiseStore = try await request(
            "/stores", method: "POST",
            body: ["Name": name, "TimeZone": "Asia/Shanghai", "BusinessDayCutoffMinutes": 0],
            token: token, idempotencyKey: idempotencyKey
        )
    }

    func members(storeID: String, token: String) async throws -> [DineWiseMember] {
        try await request("/stores/\(storeID)/members", token: token, role: "owner")
    }

    func grantMember(storeID: String, email: String, role: String, token: String) async throws {
        let _: DineWiseMember = try await request(
            "/stores/\(storeID)/members", method: "POST",
            body: ["Email": email, "Role": role], token: token, role: "owner"
        )
    }

    func revokeMember(storeID: String, memberID: String, token: String) async throws {
        let _: EmptyResult = try await request(
            "/stores/\(storeID)/members/\(memberID)", method: "DELETE",
            token: token, role: "owner"
        )
    }

    func submissions(storeID: String, token: String, role: String) async throws -> [DineWiseSubmission] {
        let page: DineWiseSubmissionPage = try await request(
            "/stores/\(storeID)/submissions", token: token, role: role
        )
        return page.Items
    }

    func submissionDetail(storeID: String, submissionID: String,
                          token: String, role: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)", token: token, role: role)
    }

    func reviewField(storeID: String, submissionID: String, token: String, role: String,
                     version: Int, fieldKey: String, value: String, unit: String,
                     idempotencyKey: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/fields",
                          method: "PATCH", body: ["Version": version, "FieldKey": fieldKey,
                                                  "Value": value, "Unit": unit],
                          token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func finishReview(storeID: String, submissionID: String, token: String, role: String,
                      version: Int, action: String,
                      idempotencyKey: String) async throws -> DineWiseSubmissionDetail {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/\(action)",
                          method: "POST", body: ["Version": version], token: token,
                          idempotencyKey: idempotencyKey, role: role)
    }

    func recommendations(storeID: String, token: String, role: String) async throws -> [DineWiseRecommendation] {
        try await request("/stores/\(storeID)/recommendations", token: token, role: role)
    }

    func dailyReport(storeID: String, businessDate: String,
                     token: String) async throws -> DineWiseDailyReport {
        try await request("/stores/\(storeID)/reports/daily?date=\(businessDate)",
                          token: token, role: "owner")
    }

    func proposeRecommendation(storeID: String, token: String, role: String,
                               sourceSubmissionID: String, title: String, rationale: String,
                               steps: String, targetRole: String,
                               idempotencyKey: String) async throws -> DineWiseRecommendation {
        try await request("/stores/\(storeID)/recommendations", method: "POST", body: [
            "SourceSubmissionId": sourceSubmissionID, "Title": title,
            "Rationale": rationale, "Steps": steps, "TargetRole": targetRole
        ], token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func decideRecommendation(storeID: String, recommendationID: String,
                              token: String, role: String, version: Int, action: String,
                              reason: String, remindOn: String?, assignedUserID: String?,
                              idempotencyKey: String) async throws -> DineWiseRecommendation {
        var body: [String: Any] = ["Version": version, "Action": action, "Reason": reason]
        if let remindOn { body["RemindOn"] = remindOn }
        if let assignedUserID { body["AssignedUserId"] = assignedUserID }
        return try await request("/stores/\(storeID)/recommendations/\(recommendationID)/decision",
                                 method: "POST", body: body, token: token,
                                 idempotencyKey: idempotencyKey, role: role)
    }

    func tasks(storeID: String, token: String, role: String) async throws -> [DineWiseTask] {
        try await request("/stores/\(storeID)/tasks", token: token, role: role)
    }

    func taskAction(storeID: String, taskID: String, token: String, role: String,
                    version: Int, action: String, note: String, assignedUserID: String?,
                    idempotencyKey: String) async throws -> DineWiseTask {
        var body: [String: Any] = ["Version": version, "Action": action, "Note": note]
        if let assignedUserID { body["AssignedUserId"] = assignedUserID }
        return try await request("/stores/\(storeID)/tasks/\(taskID)/actions", method: "POST",
                                 body: body, token: token, idempotencyKey: idempotencyKey, role: role)
    }

    func submitText(storeID: String, token: String, role: String, kind: String,
                    businessDate: String, originalText: String, idempotencyKey: String) async throws {
        let _: DineWiseSubmission = try await request(
            "/stores/\(storeID)/submissions", method: "POST",
            body: ["Kind": kind, "BusinessDate": businessDate, "OriginalText": originalText],
            token: token, idempotencyKey: idempotencyKey, role: role
        )
    }

    func files(storeID: String, submissionID: String, token: String,
               role: String) async throws -> [DineWiseSubmissionFile] {
        try await request("/stores/\(storeID)/submissions/\(submissionID)/files",
                          token: token, role: role)
    }

    func uploadFile(storeID: String, submissionID: String, token: String, role: String,
                    fileName: String, data: Data, idempotencyKey: String) async throws {
        guard data.count <= 10 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("单个附件不能超过 10 MB。")
        }
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(storeID)/submissions/\(submissionID)/files",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        let boundary = "DineWise-\(UUID().uuidString)"
        let safeName = fileName.replacingOccurrences(of: "\"", with: "_")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(role, forHTTPHeaderField: "X-DineWise-Role")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
        let envelope = try JSONDecoder().decode(APIEnvelope<DineWiseSubmissionFile>.self,
                                                from: responseData)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              envelope.success, envelope.response != nil else {
            throw DineWiseAPIError.failed(envelope.msg ?? "附件上传失败")
        }
    }

    func downloadFile(storeID: String, submissionID: String, fileID: String,
                      token: String, role: String) async throws -> Data {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/restaurant-assistant/stores/\(storeID)/submissions/\(submissionID)/files/\(fileID)",
                            relativeTo: base)?.absoluteURL,
              isAllowedEndpoint(url) else { throw DineWiseAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(role, forHTTPHeaderField: "X-DineWise-Role")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 10 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("附件下载失败。")
        }
        return data
    }

    private func isAllowedEndpoint(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && (url.host == "localhost" || url.host == "127.0.0.1"
            || url.host?.hasPrefix("192.168.") == true || url.host?.hasPrefix("10.") == true)
        #else
        return false
        #endif
    }
}
