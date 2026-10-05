import Foundation
import Observation
import UIKit

@MainActor
private final class AIKBackgroundExecution {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "AIKKnowledgeChat"
        ) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@MainActor
@Observable
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var sessionID: String?
    var input = ""
    var errorMessage: String?

    let voiceRecorder = VoiceRecorder()

    private let session: SessionStore
    private let tenantStore: TenantStore
    private let tenant: TenantSummary
    private let client: APIClient
    private let defaults: UserDefaults
    private var hasLoaded = false

    init(
        session: SessionStore,
        tenantStore: TenantStore,
        tenant: TenantSummary,
        client: APIClient = APIClient(),
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.tenantStore = tenantStore
        self.tenant = tenant
        self.client = client
        self.defaults = defaults
    }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        do {
            let latest: FlexibleStringID? = try await client.getOptional(
                "/KnowledgeChat/GetLatestSessionByFingerprint",
                queryItems: [
                    URLQueryItem(name: "fingerprint", value: installationID),
                    URLQueryItem(name: "tenantId", value: tenant.id),
                    URLQueryItem(name: "userId", value: session.user?.Id.rawValue),
                ].filter { $0.value != nil },
                context: tenantStore.context(for: session),
                as: FlexibleStringID.self
            )
            if let latest,
               defaults.string(forKey: skippedSessionKey) != latest.rawValue {
                sessionID = latest.rawValue
                let history: [ChatHistoryMessage] = try await client.get(
                    "/KnowledgeChat/GetSessionMessages",
                    queryItems: [
                        URLQueryItem(name: "sessionId", value: latest.rawValue),
                    ],
                    context: tenantStore.context(for: session),
                    as: [ChatHistoryMessage].self
                )
                messages = history.compactMap { item in
                    guard let content = item.Content, !content.isEmpty else {
                        return nil
                    }
                    return ChatMessage(
                        id: item.Id.rawValue,
                        role: item.Role?.lowercased() == "user" ? .user : .assistant,
                        content: content,
                        userRating: item.UserRating ?? 0,
                        logDate: item.CreateTime
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        if messages.isEmpty {
            messages = [welcomeMessage]
        }
    }

    func send(_ forcedText: String? = nil) async {
        let text = (forcedText ?? input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading,
              let tenantID = Int64(tenant.id) else {
            return
        }
        if forcedText == nil {
            input = ""
        }
        let userMessage = ChatMessage(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            content: text,
            userRating: 0
        )
        let localAssistantID = "local-assistant-\(UUID().uuidString)"
        messages.append(userMessage)
        messages.append(
            ChatMessage(
                id: localAssistantID,
                localID: localAssistantID,
                role: .assistant,
                content: "",
                statusMessage: String(localized: "chat.thinking"),
                userRating: 0
            )
        )
        isLoading = true
        errorMessage = nil
        let requestStartedAt = Date()
        let backgroundExecution = AIKBackgroundExecution()
        backgroundExecution.begin()
        defer {
            backgroundExecution.end()
            isLoading = false
        }

        do {
            let body = StreamAskRequest(
                question: text,
                sessionId: sessionID.flatMap(Int64.init),
                tenantId: tenantID,
                source: "iOS-AIK",
                userName: session.user?.RealName
                    ?? session.user?.UserName
                    ?? String(localized: "chat.guest"),
                fingerprint: installationID,
                userId: session.user.flatMap { Int64($0.Id.rawValue) }
            )
            var request = try client.makeRequest(
                path: "/KnowledgeChat/StreamAsk",
                method: "POST",
                context: tenantStore.context(for: session)
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 180
            request.httpBody = try JSONEncoder().encode(body)

            let (bytes, _) = try await client.bytes(for: request)
            var parser = SSEParser()
            var chunk: [UInt8] = []
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 512 || byte == 0x0A {
                    apply(
                        parser.feed(Data(chunk)),
                        to: localAssistantID,
                        requestStartedAt: requestStartedAt
                    )
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty {
                apply(
                    parser.feed(Data(chunk)),
                    to: localAssistantID,
                    requestStartedAt: requestStartedAt
                )
            }
            apply(
                parser.finish(),
                to: localAssistantID,
                requestStartedAt: requestStartedAt
            )
            updateMessage(localAssistantID) { message in
                if message.content.isEmpty {
                    message.content = String(localized: "chat.interrupted")
                }
                message.statusMessage = nil
            }
        } catch {
            updateMessage(localAssistantID) { message in
                message.content = String(localized: "chat.network_error")
                message.statusMessage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    func startNewChat() {
        if let sessionID {
            defaults.set(sessionID, forKey: skippedSessionKey)
        }
        self.sessionID = nil
        messages = [welcomeMessage]
    }

    func clearHistory() async {
        guard let tenantID = Int64(tenant.id) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let _: EmptyResponse = try await client.post(
                "/KnowledgeChat/ClearHistory",
                body: ClearHistoryRequest(
                    Fingerprint: installationID,
                    TenantId: tenantID
                ),
                context: tenantStore.context(for: session),
                as: EmptyResponse.self
            )
            defaults.removeObject(forKey: skippedSessionKey)
            sessionID = nil
            messages = [welcomeMessage]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rate(_ message: ChatMessage, value: Int, comment: String = "") async {
        guard let messageID = Int64(message.id),
              let tenantID = Int64(tenant.id) else {
            return
        }
        do {
            let _: String = try await client.post(
                "/KnowledgeChat/SubmitRating",
                body: RatingRequest(
                    MessageId: messageID,
                    Rating: value,
                    Comment: comment,
                    LogDate: message.logDate,
                    TenantId: tenantID
                ),
                context: tenantStore.context(for: session),
                as: String.self
            )
            updateMessage(message.id) {
                $0.userRating = comment.isEmpty ? value : 2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleVoice() async {
        if voiceRecorder.isRecording {
            if let url = voiceRecorder.stop() {
                await sendVoice(url)
            }
        } else {
            await voiceRecorder.start()
        }
    }

    private func sendVoice(_ fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        defer { try? FileManager.default.removeItem(at: fileURL) }
        isLoading = true
        defer { isLoading = false }
        do {
            let boundary = "AIK-\(UUID().uuidString)"
            var body = Data()
            body.appendMultipart(
                name: "tenantId",
                value: tenant.id,
                boundary: boundary
            )
            body.appendMultipart(
                name: "file",
                filename: "voice.m4a",
                contentType: "audio/mp4",
                data: data,
                boundary: boundary
            )
            body.append(Data("--\(boundary)--\r\n".utf8))
            var request = try client.makeRequest(
                path: "/KnowledgeChat/VoiceAsk",
                method: "POST",
                context: tenantStore.context(for: session)
            )
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = body
            let responseData = try await client.rawData(for: request)
            let envelope = try JSONDecoder().decode(
                MessageEnvelope<VoiceResponse>.self,
                from: responseData
            )
            guard envelope.success, let question = envelope.response?.question else {
                throw APIError.server(
                    envelope.msg ?? String(localized: "voice.failed")
                )
            }
            isLoading = false
            await send(question)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(
        _ events: [SSEEvent],
        to localID: String,
        requestStartedAt: Date
    ) {
        for event in events {
            switch event {
            case let .status(value):
                updateMessage(localID) { $0.statusMessage = value }
            case let .content(delta):
                updateMessage(localID) { message in
                    if message.responseTimeMilliseconds == nil {
                        message.responseTimeMilliseconds = max(
                            0,
                            Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
                        )
                    }
                    message.content += delta
                    if message.content.hasPrefix(")") {
                        message.content.removeFirst()
                        message.content = message.content
                            .trimmingCharacters(in: .whitespaces)
                    }
                    message.statusMessage = nil
                }
            case let .metadata(messageID, newSessionID, logDate):
                if let newSessionID {
                    sessionID = newSessionID
                }
                updateMessage(localID) { message in
                    if let messageID {
                        message.id = messageID
                    }
                    message.logDate = logDate
                }
            case let .failure(message):
                updateMessage(localID) {
                    $0.content = message
                    $0.statusMessage = nil
                }
            case .done:
                break
            }
        }
    }

    private func updateMessage(
        _ id: String,
        mutation: (inout ChatMessage) -> Void
    ) {
        guard let index = messages.firstIndex(where: {
            $0.id == id || $0.localID == id
        }) else {
            return
        }
        mutation(&messages[index])
    }

    private var welcomeMessage: ChatMessage {
        let configured = tenant.WelcomeMessage?
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .randomElement()
        let fallback = String(
            format: String(localized: "chat.welcome"),
            tenant.AgentName ?? tenant.TenantName
        )
        return ChatMessage(
            id: "welcome",
            role: .assistant,
            content: configured ?? fallback,
            userRating: 0
        )
    }

    private var installationID: String {
        if let value = defaults.string(forKey: "aik.installation-id") {
            return value
        }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: "aik.installation-id")
        return value
    }

    private var skippedSessionKey: String {
        "aik.skipped-session.\(tenant.id)"
    }
}

private extension Data {
    mutating func appendMultipart(
        name: String,
        value: String,
        boundary: String
    ) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }

    mutating func appendMultipart(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        append(Data("--\(boundary)\r\n".utf8))
        append(
            Data(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .utf8
            )
        )
        append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        append(data)
        append(Data("\r\n".utf8))
    }
}
