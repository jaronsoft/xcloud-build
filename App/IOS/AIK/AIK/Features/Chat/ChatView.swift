import SwiftUI

struct ChatView: View {
    let session: SessionStore
    let tenantStore: TenantStore
    let tenant: TenantSummary

    @State private var model: ChatViewModel
    @State private var showsClearConfirmation = false
    @State private var showsTools = false

    init(
        session: SessionStore,
        tenantStore: TenantStore,
        tenant: TenantSummary
    ) {
        self.session = session
        self.tenantStore = tenantStore
        self.tenant = tenant
        _model = State(
            initialValue: ChatViewModel(
                session: session,
                tenantStore: tenantStore,
                tenant: tenant
            )
        )
    }

    var body: some View {
        errorAlertView
    }

    private var navigationView: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    ChatMessagesList(
                        messages: model.messages,
                        isLoading: model.isLoading,
                        agentLogo: tenant.AgentLogo,
                        onCopy: copyMessage,
                        onRate: rateMessage
                    )
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: scrollRevision) { _, _ in
                    guard let target = model.messages.last?.id else { return }
                    let bottomAnchor = UnitPoint.bottom
                    proxy.scrollTo(target, anchor: bottomAnchor)
                }
            }
            .background(AIKTheme.background)
            .navigationTitle(tenant.AgentName ?? tenant.TenantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu(
                        logoURL: tenant.AgentLogo,
                        canLogout: session.mode == .system,
                        onSwitch: tenantStore.switchTenant,
                        onLogout: logout
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChatActionsMenu(
                        onNewChat: model.startNewChat,
                        onClear: { showsClearConfirmation = true },
                        onTools: { showsTools = true }
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .task {
                await model.load()
            }
            .sheet(isPresented: $showsTools) {
                SupportToolsView(onClearTenantCache: tenantStore.clearDirectoryCache)
            }
        }
    }

    private var clearAlertView: some View {
        navigationView.alert(
            "chat.clear_title",
            isPresented: $showsClearConfirmation
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("chat.clear_confirm", role: .destructive) {
                Task { await model.clearHistory() }
            }
        } message: {
            Text("chat.clear_message")
        }
    }

    private var errorAlertView: some View {
        clearAlertView.alert(
            "common.notice",
            isPresented: errorIsPresented
        ) {
            Button("common.ok", action: dismissError)
        } message: {
            Text(verbatim: presentedError)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || model.voiceRecorder.errorMessage != nil },
            set: { if !$0 { dismissError() } }
        )
    }

    private func dismissError() {
        model.errorMessage = nil
        model.voiceRecorder.clearError()
    }

    private var presentedError: String {
        if let value = model.errorMessage {
            return value
        }
        if let value = model.voiceRecorder.errorMessage {
            return value
        }
        return ""
    }

    private var scrollRevision: String {
        guard let message = model.messages.last else { return "" }
        return "\(message.id)-\(message.content.count)"
    }

    private func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
    }

    private func rateMessage(_ message: ChatMessage, value: Int) {
        Task { await model.rate(message, value: value) }
    }

    private func logout() {
        tenantStore.reset()
        session.logout()
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if model.voiceRecorder.isRecording {
                Label("voice.recording", systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if tenant.EnableVoice == true {
                    Button {
                        Task { await model.toggleVoice() }
                    } label: {
                        Image(systemName: model.voiceRecorder.isRecording
                            ? "stop.circle.fill"
                            : "mic.circle")
                            .font(.title2)
                            .foregroundStyle(
                                model.voiceRecorder.isRecording ? .red : AIKTheme.accent
                            )
                    }
                    .accessibilityLabel(
                        model.voiceRecorder.isRecording
                            ? String(localized: "voice.stop")
                            : String(localized: "voice.start")
                    )
                }

                TextField("chat.placeholder", text: $model.input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AIKTheme.background, in: .rect(cornerRadius: 18))
                    .onSubmit {
                        guard model.canSend else { return }
                        Task { await model.send() }
                    }

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(!model.canSend)
                .accessibilityLabel("chat.send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct AccountMenu: View {
    let logoURL: String?
    let canLogout: Bool
    let onSwitch: () -> Void
    let onLogout: () -> Void

    var body: some View {
        Menu {
            Button("chat.switch_tenant", systemImage: "building.2", action: onSwitch)
            if canLogout {
                Button(
                    "account.logout",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive,
                    action: onLogout
                )
            }
        } label: {
            TenantLogo(url: logoURL, size: 34)
        }
    }
}

private struct ChatActionsMenu: View {
    let onNewChat: () -> Void
    let onClear: () -> Void
    let onTools: () -> Void

    var body: some View {
        Menu {
            Button("chat.new", systemImage: "plus.bubble", action: onNewChat)
            Button(
                "chat.clear",
                systemImage: "trash",
                role: .destructive,
                action: onClear
            )
            Button("tools.title", systemImage: "stethoscope", action: onTools)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct ChatMessagesList: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let agentLogo: String?
    let onCopy: (ChatMessage) -> Void
    let onRate: (ChatMessage, Int) -> Void

    var body: some View {
        LazyVStack(spacing: 18) {
            ForEach(messages) { message in
                ChatMessageRow(
                    message: message,
                    agentLogo: agentLogo,
                    onCopy: { onCopy(message) },
                    onRate: { onRate(message, $0) }
                )
                .id(message.id)
            }
            if isLoading {
                HStack {
                    ProgressView()
                    Text("chat.thinking")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let agentLogo: String?
    let onCopy: () -> Void
    let onRate: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 48)
            } else {
                agentAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let status = message.statusMessage, message.content.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(status)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .background(AIKTheme.surface, in: .rect(cornerRadius: 16))
                } else {
                    MarkdownMessageView(content: message.content)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .padding(14)
                        .background(
                            message.role == .user
                                ? AnyShapeStyle(AIKTheme.gradient())
                                : AnyShapeStyle(AIKTheme.surface),
                            in: .rect(cornerRadius: 16)
                        )
                }

                if message.role == .assistant,
                   message.id != "welcome",
                   !message.id.hasPrefix("local-"),
                   !message.content.isEmpty {
                    HStack(spacing: 16) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            onRate(1)
                        } label: {
                            Image(systemName: message.userRating == 1
                                ? "hand.thumbsup.fill"
                                : "hand.thumbsup")
                        }
                        Button {
                            onRate(-1)
                        } label: {
                            Image(systemName: message.userRating == -1
                                ? "hand.thumbsdown.fill"
                                : "hand.thumbsdown")
                        }
                        if let responseTime = responseTimeText {
                            Label(responseTime, systemImage: "timer")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(message.userRating != 0)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 28)
            }
        }
    }

    private var responseTimeText: String? {
        guard let milliseconds = message.responseTimeMilliseconds else {
            return nil
        }
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        return String(format: "%.1fs", Double(milliseconds) / 1_000)
    }

    private var agentAvatar: some View {
        AsyncImage(url: URL(string: agentLogo ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AIKTheme.gradient())
        }
        .frame(width: 34, height: 34)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
