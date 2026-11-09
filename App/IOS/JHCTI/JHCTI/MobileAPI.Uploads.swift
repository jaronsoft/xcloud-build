import Foundation

extension MobileAPI {
    func uploadMyOnboardingDocument(_ data: Data, applicationId: String, category: String,
                                   documentName: String, fileName: String) async throws -> String {
        try await uploadMyOnboardingDocument(data, applicationId: applicationId, category: category,
                                             documentName: documentName, fileName: fileName, canRefresh: true)
    }

    private func uploadMyOnboardingDocument(_ data: Data, applicationId: String, category: String,
                                            documentName: String, fileName: String, canRefresh: Bool) async throws -> String {
        let name = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedCategories = ["Entity", "Store", "Settlement", "Compliance", "Other"]
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard data.count >= 8, data.count <= 20 * 1024 * 1024,
              Int64(applicationId).map({ $0 > 0 }) == true,
              allowedCategories.contains(category), !name.isEmpty, name.count <= 120,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              ["pdf", "jpg", "jpeg", "png"].contains(ext), let old = store.session else {
            throw MobileAPIError.unavailable("请提供有效的 PDF、JPG 或 PNG 文件、资料名称和申请编号")
        }
        let safeName = "document.\(ext == "jpeg" ? "jpg" : ext)"
        let contentType = ext == "pdf" ? "application/pdf" : (ext == "png" ? "image/png" : "image/jpeg")
        let boundary = "JHCTI-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (key, value) in [("ApplicationId", applicationId), ("Category", category), ("DocumentName", name)] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        defer {
            if !body.isEmpty { body.resetBytes(in: body.startIndex..<body.endIndex) }
        }
        guard let url = URL(string: "/api/JHCTIMerchant/UploadMyOnboardingDocument", relativeTo: baseURL) else {
            throw MobileAPIError.unavailable("上传地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(old.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await performNetworkRequest {
            try await URLSession.shared.upload(for: request, from: body)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        let apiStatus = envelope["status"] as? Int ?? envelope["Status"] as? Int
        let originalPrincipal = nativeTourismPrincipal(old.accessToken)
        if status == 401 || apiStatus == 401 {
            guard canRefresh else { throw MobileAPIError.unavailable("登录已失效，请重新登录后重试上传") }
            if let current = store.session, nativeTourismPrincipal(current.accessToken) != originalPrincipal {
                throw MobileAPIError.unavailable("登录账号已变化，请重新操作")
            }
            _ = try await refreshSession(old)
            try Task.checkCancellation()
            if !body.isEmpty { body.resetBytes(in: body.startIndex..<body.endIndex) }
            return try await uploadMyOnboardingDocument(data, applicationId: applicationId, category: category,
                                                        documentName: name, fileName: safeName, canRefresh: false)
        }
        if !(200..<300).contains(status) || envelope["Success"] as? Bool == false || envelope["success"] as? Bool == false {
            let message = (envelope["Msg"] ?? envelope["msg"] ?? envelope["Message"] ?? envelope["message"]) as? String
            throw MobileAPIError.unavailable(message ?? "资料上传失败，请重试")
        }
        let resultValue = envelope["Response"] ?? envelope["response"] ?? envelope["Data"] ?? envelope["data"]
        let result = (resultValue as? String) ?? (resultValue as? NSNumber)?.stringValue
        guard store.session.map({ nativeTourismPrincipal($0.accessToken) }) == originalPrincipal,
              let result,
              Int64(result).map({ $0 > 0 }) == true else {
            throw MobileAPIError.unavailable("上传结果无效或登录账号已变化，请刷新核对")
        }
        return result
    }

    func uploadSupportTicketAttachment(_ data: Data, objectNo: String) async throws -> String {
        try await uploadSupportTicketAttachment(data, objectNo: objectNo, canRefresh: true)
    }

    func uploadMyProductReviewImage(_ data: Data, expectedPrincipal: String? = nil) async throws -> String {
        try await uploadMyProductReviewImage(data, expectedPrincipal: expectedPrincipal, canRefresh: true)
    }

    func uploadMyAfterSaleEvidence(_ data: Data, expectedPrincipal: String? = nil) async throws -> String {
        try await uploadMyAfterSaleEvidence(data, expectedPrincipal: expectedPrincipal, canRefresh: true)
    }

    private func uploadMyAfterSaleEvidence(_ data: Data, expectedPrincipal: String?, canRefresh: Bool) async throws -> String {
        guard data.count >= 8, data.count <= 5 * 1024 * 1024, let old = store.session else {
            throw MobileAPIError.unavailable("售后凭证无效或超过 5 MB，请重新选择")
        }
        let principal = nativeTourismPrincipal(old.accessToken)
        guard expectedPrincipal == nil || expectedPrincipal == principal else {
            throw MobileAPIError.unavailable("售后凭证无效或超过 5 MB，请重新选择")
        }
        let boundary = "JHCTI-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"after-sale.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        guard let url = URL(string: "/api/JHCTITradeAfterSale/UploadMyEvidence", relativeTo: baseURL) else {
            throw MobileAPIError.unavailable("售后凭证上传地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(old.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await performNetworkRequest {
            try await URLSession.shared.upload(for: request, from: body)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        let apiStatus = envelope["status"] as? Int ?? envelope["Status"] as? Int
        if status == 401 || apiStatus == 401 {
            guard canRefresh, let current = store.session,
                  nativeTourismPrincipal(current.accessToken) == principal else {
                throw MobileAPIError.unavailable("登录已失效或账号已变化，请重新登录后上传")
            }
            _ = try await refreshSession(old)
            try Task.checkCancellation()
            return try await uploadMyAfterSaleEvidence(data, expectedPrincipal: principal, canRefresh: false)
        }
        if !(200..<300).contains(status) || envelope["Success"] as? Bool == false || envelope["success"] as? Bool == false {
            let message = (envelope["Msg"] ?? envelope["msg"] ?? envelope["Message"] ?? envelope["message"]) as? String
            throw MobileAPIError.unavailable(message ?? "售后凭证上传失败，请重试")
        }
        guard let url = (envelope["Response"] ?? envelope["response"] ?? envelope["Data"] ?? envelope["data"]) as? String,
              url.lowercased().hasPrefix("https://"),
              store.session.map({ nativeTourismPrincipal($0.accessToken) }) == principal else {
            throw MobileAPIError.unavailable("售后凭证上传结果无效或登录账号已变化")
        }
        return url
    }

    private func uploadMyProductReviewImage(_ data: Data, expectedPrincipal: String?, canRefresh: Bool) async throws -> String {
        guard data.count >= 8, data.count <= 5 * 1024 * 1024, let old = store.session else {
            throw MobileAPIError.unavailable("评价图片无效或超过 5 MB，请重新选择")
        }
        let originalPrincipal = nativeTourismPrincipal(old.accessToken)
        guard expectedPrincipal == nil || expectedPrincipal == originalPrincipal else {
            throw MobileAPIError.unavailable("评价图片无效或超过 5 MB，请重新选择")
        }
        let boundary = "JHCTI-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"review.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        guard let url = URL(string: "/api/JHCTIProductReview/UploadMyReviewImage", relativeTo: baseURL) else {
            throw MobileAPIError.unavailable("评价图片上传地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(old.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await performNetworkRequest {
            try await URLSession.shared.upload(for: request, from: body)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        let apiStatus = envelope["status"] as? Int ?? envelope["Status"] as? Int
        if status == 401 || apiStatus == 401 {
            guard canRefresh, let current = store.session,
                  nativeTourismPrincipal(current.accessToken) == originalPrincipal else {
                throw MobileAPIError.unavailable("登录已失效或账号已变化，请重新登录后再上传")
            }
            _ = try await refreshSession(old)
            try Task.checkCancellation()
            return try await uploadMyProductReviewImage(data, expectedPrincipal: originalPrincipal, canRefresh: false)
        }
        if !(200..<300).contains(status) || envelope["Success"] as? Bool == false || envelope["success"] as? Bool == false {
            let message = (envelope["Msg"] ?? envelope["msg"] ?? envelope["Message"] ?? envelope["message"]) as? String
            throw MobileAPIError.unavailable(message ?? "评价图片上传失败，请重试")
        }
        guard let url = (envelope["Response"] ?? envelope["response"] ?? envelope["Data"] ?? envelope["data"]) as? String,
              url.lowercased().hasPrefix("https://"),
              store.session.map({ nativeTourismPrincipal($0.accessToken) }) == originalPrincipal else {
            throw MobileAPIError.unavailable("评价图片上传结果无效或登录账号已变化")
        }
        return url
    }

    private func uploadSupportTicketAttachment(_ data: Data, objectNo: String, canRefresh: Bool) async throws -> String {
        guard data.count > 0, data.count <= 5 * 1024 * 1024,
              objectNo == "0" || Int64(objectNo).map({ $0 > 0 }) == true,
              let old = store.session else {
            throw MobileAPIError.unavailable("图片大小或工单关联信息无效，请重新选择")
        }
        let boundary = "JHCTI-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (name, value) in [("AppName", "JHCTISupportTicket"), ("ObjectTable", "jhcti_support_ticket_message"), ("ObjectNo", objectNo), ("UploadFileTypeEnum", "1")] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"support.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        guard let url = URL(string: "/api/ObjectStorage/Post", relativeTo: baseURL) else {
            throw MobileAPIError.unavailable("上传地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(old.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await performNetworkRequest {
            try await URLSession.shared.upload(for: request, from: body)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        let apiStatus = envelope["status"] as? Int ?? envelope["Status"] as? Int
        if status == 401 || apiStatus == 401 {
            guard canRefresh else { throw MobileAPIError.unavailable("登录已失效，请重新登录后重试上传") }
            _ = try await refreshSession(old)
            try Task.checkCancellation()
            return try await uploadSupportTicketAttachment(data, objectNo: objectNo, canRefresh: false)
        }
        if !(200..<300).contains(status) || envelope["Success"] as? Bool == false || envelope["success"] as? Bool == false {
            let message = (envelope["Msg"] ?? envelope["msg"] ?? envelope["Message"] ?? envelope["message"]) as? String
            throw MobileAPIError.unavailable(message ?? "图片上传失败，请重试")
        }
        guard let result = (envelope["Response"] ?? envelope["response"] ?? envelope["Data"] ?? envelope["data"]) as? [String: Any],
              let path = result["url"] as? String ?? result["Url"] as? String,
              mediaURL(path) != nil, store.session?.accessToken == old.accessToken else {
            throw MobileAPIError.unavailable("上传结果无效或登录账号已变化，请刷新核对")
        }
        return path
    }

}
