import Observation
import PhotosUI
import SwiftUI

struct ProjectsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ProjectsViewModel()
    @State private var presentsLogin = false
    @State private var presentsCreate = false
    @State private var selectedProject: AISProjectListItem?

    var body: some View {
        ZStack {
            AISPageBackground()
            if session.isRestoring {
                ProgressView("common.loading")
            } else if !session.isAuthenticated {
                signedOutContent
            } else if model.isLoading && model.projects.isEmpty {
                ProgressView("projects.loading")
            } else {
                projectContent
            }
        }
        .navigationTitle("tab.projects")
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentsCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("projects.create")
                }
            }
        }
        .sheet(isPresented: $presentsLogin) {
            LoginView()
        }
        .sheet(isPresented: $presentsCreate) {
            ProjectCreateView { name, description in
                await model.create(
                    name: name,
                    description: description,
                    session: session
                )
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(project: project) {
                Task {
                    await model.load(
                        session: session,
                        force: true
                    )
                }
            }
        }
        .task(id: session.user?.id) {
            guard session.isAuthenticated else {
                model.reset()
                return
            }
            await model.load(session: session)
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AISTheme.auroraGradient)
            Text("projects.title")
                .font(.title2.bold())
            Text("projects.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                presentsLogin = true
            } label: {
                Text("account.signin").aisPrimaryButton()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 420)
        .padding(24)
    }

    private var projectContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AISVisualHeader(imageName: "ProjectsVisual") {
                    VStack(alignment: .leading, spacing: 8) {
                        AISSectionLabel(
                            title: "projects.status",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        Text("projects.title")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("projects.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(AISTheme.muted)
                    }
                }

                if let error = model.errorMessage, model.projects.isEmpty {
                    ContentUnavailableView(
                        "common.error",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else if model.projects.isEmpty {
                    ContentUnavailableView(
                        "projects.empty",
                        systemImage: "folder.badge.plus",
                        description: Text("projects.empty.helper")
                    )
                } else {
                    ForEach(model.projects) { project in
                        Button {
                            selectedProject = project
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 820)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await model.load(session: session, force: true)
        }
    }
}

@MainActor
@Observable
private final class ProjectsViewModel {
    private let api = APIClient()
    private(set) var projects: [AISProjectListItem] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func load(session: SessionStore, force: Bool = false) async {
        guard let token = await session.validAccessToken() else {
            reset()
            return
        }
        let key = AISResponseCache.key(
            scope: "user:\(session.user?.id ?? "unknown")",
            resource: "agent-projects"
        )
        if !force,
           let cached = await AISResponseCache.shared.read(
               PageResponse<AISProjectListItem>.self,
               key: key
           ) {
            projects = cached.value.items
            if cached.isFresh { return }
        }
        isLoading = projects.isEmpty
        defer { isLoading = false }
        do {
            let page: PageResponse<AISProjectListItem> = try await api.get(
                "/api/ais/agent/projects",
                query: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "30")
                ],
                accessToken: token
            )
            projects = page.items
            await AISResponseCache.shared.write(page, key: key)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(
        name: String,
        description: String,
        session: SessionStore
    ) async -> Bool {
        guard let token = await session.validAccessToken() else { return false }
        do {
            let _: String = try await api.post(
                "/api/ais/agent/projects",
                body: AISCreateProjectRequest(
                    name: name,
                    description: description,
                    brandKey: nil,
                    productKey: nil,
                    referenceAssetIds: [],
                    context: [:]
                ),
                accessToken: token
            )
            await load(session: session, force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        projects = []
        isLoading = false
        errorMessage = nil
    }
}

private struct ProjectCard: View {
    let project: AISProjectListItem

    var body: some View {
        HStack(spacing: 14) {
            preview
            VStack(alignment: .leading, spacing: 7) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let description = project.description?.nilIfEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    Label(
                        "\(project.deliverableCount)",
                        systemImage: "photo.stack"
                    )
                    Label(
                        "\(project.memoryCount)",
                        systemImage: "brain.head.profile"
                    )
                    if let status = project.latestRunStatus?.nilIfEmpty {
                        Text(status)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .aisSurface(cornerRadius: 22)
    }

    private var preview: some View {
        Group {
            if let value = project.previewUrls.first,
               let url = URL(string: value) {
                AISCachedAsyncImage(
                    url: url,
                    preset: .thumbnail,
                    module: .projectsAssets
                ) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
            } else {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(AISTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AISTheme.accent.opacity(0.08))
            }
        }
        .frame(width: 78, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 17))
    }
}

private struct ProjectCreateView: View {
    private enum Field {
        case name
        case description
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    let onCreate: (String, String) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("projects.create.name", text: $name)
                    .focused($focusedField, equals: .name)
                TextField(
                    "projects.create.description",
                    text: $description,
                    axis: .vertical
                )
                .focused($focusedField, equals: .description)
                .lineLimit(3...6)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("projects.create")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        focusedField = nil
                        Task {
                            isSaving = true
                            if await onCreate(
                                name.trimmingCharacters(in: .whitespacesAndNewlines),
                                description.trimmingCharacters(in: .whitespacesAndNewlines)
                            ) {
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(
                        isSaving
                            || name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        focusedField = nil
                    }
                }
            }
        }
    }
}

private struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @FocusState private var isMessageFocused: Bool
    @State private var model: ProjectDetailViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var message = ""
    @State private var proposesMemory = false
    @State private var selectedSkill: AISSkillSummary?
    @State private var selectedRun: AISProjectRun?
    @State private var confirmsDelete = false
    let onChanged: () -> Void

    init(project: AISProjectListItem, onChanged: @escaping () -> Void) {
        _model = State(initialValue: ProjectDetailViewModel(project: project))
        self.onChanged = onChanged
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    projectHeader
                    assetsSection
                    conversationSection
                    memorySection
                    skillSection
                    runSection
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AISPageBackground())
            .navigationTitle(model.project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") {
                        isMessageFocused = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        isMessageFocused = false
                    }
                }
            }
            .task {
                await model.load(session: session)
                await model.loadSkills(session: session)
            }
            .photosPicker(
                isPresented: $model.presentsPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: max(1, 3 - model.assets.count),
                matching: .images
            )
            .onChange(of: selectedPhotos) { _, items in
                Task {
                    await model.addPhotos(items, session: session)
                    selectedPhotos = []
                }
            }
            .sheet(item: $selectedSkill) { skill in
                ProjectSkillView(
                    projectID: model.project.id,
                    skill: skill,
                    assets: model.assets
                ) {
                    await model.load(session: session)
                }
            }
            .sheet(item: $selectedRun) { run in
                ProjectRunBoardView(run: run)
            }
            .alert(
                "projects.delete.title",
                isPresented: $confirmsDelete
            ) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    Task {
                        if await model.delete(session: session) {
                            onChanged()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("projects.delete.message")
            }
            .alert(
                "common.error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.project.name).font(.title2.bold())
            if let description = model.project.description?.nilIfEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("projects.boundary")
                .font(.caption)
                .foregroundStyle(AISTheme.accentSecondary)
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("projects.assets", systemImage: "photo.stack")
                    .font(.headline)
                Spacer()
                Button {
                    model.presentsPhotoPicker = true
                } label: {
                    Label("projects.assets.add", systemImage: "plus")
                }
                .disabled(model.assets.count >= 3 || model.isWorking)
            }
            if model.assets.isEmpty {
                Text("projects.assets.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.assets.enumerated()), id: \.element.id) {
                    index,
                    asset in
                    HStack {
                        AISCachedAsyncImage(
                            url: asset.resolvedURL,
                            preset: .thumbnail,
                            module: .projectsAssets
                        ) { phase in
                            if case let .success(image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        Text(
                            asset.title
                                ?? asset.originalFileName
                                ?? String(localized: "projects.assets.photo")
                        )
                        .font(.subheadline)
                        .lineLimit(1)
                        Spacer()
                        Button {
                            Task {
                                await model.moveAsset(
                                    at: index,
                                    offset: -1,
                                    session: session
                                )
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button {
                            Task {
                                await model.moveAsset(
                                    at: index,
                                    offset: 1,
                                    session: session
                                )
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == model.assets.count - 1)
                        Button(role: .destructive) {
                            Task {
                                await model.removeAsset(
                                    asset.id,
                                    session: session
                                )
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("projects.conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Text("projects.questions")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.messages) { item in
                Text(item.content)
                    .font(.subheadline)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        item.role == "user"
                            ? AISTheme.accent.opacity(0.10)
                            : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            TextField(
                "projects.message.placeholder",
                text: $message,
                axis: .vertical
            )
            .focused($isMessageFocused)
            .lineLimit(3...7)
            Toggle("projects.memory.propose", isOn: $proposesMemory)
                .font(.caption)
            Button {
                isMessageFocused = false
                let value = message
                Task {
                    if await model.sendMessage(
                        value,
                        proposesMemory: proposesMemory,
                        session: session
                    ) {
                        message = ""
                        proposesMemory = false
                    }
                }
            } label: {
                Label("projects.message.send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AISTheme.accent)
            .disabled(
                message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.isWorking
            )
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("projects.memories", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MemoryCenterView(projectId: model.project.id)
                } label: {
                    Text("memory.manage")
                }
                .buttonStyle(.bordered)
            }
            if model.memories.isEmpty {
                Text("projects.memories.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.memories) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.content).font(.subheadline)
                    HStack {
                        Text(memory.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if memory.status != "confirmed" {
                            Button("projects.memory.confirm") {
                                Task {
                                    await model.updateMemory(
                                        memory,
                                        status: "confirmed",
                                        session: session
                                    )
                                }
                            }
                        }
                        Button("projects.memory.disable") {
                            Task {
                                await model.updateMemory(
                                    memory,
                                    status: "disabled",
                                    session: session
                                )
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await model.deleteMemory(
                                    memory,
                                    session: session
                                )
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .font(.caption)
                }
                .padding(12)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("projects.skills", systemImage: "wand.and.stars")
                .font(.headline)
            Text("projects.skills.helper")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.skills) { skill in
                Button {
                    selectedSkill = skill
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.localizedName)
                                .font(.subheadline.weight(.semibold))
                            if let description = skill.localizedDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "projects.skills.outputs"),
                                skill.outputCount
                            )
                        )
                        .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("projects.runs", systemImage: "rectangle.stack")
                .font(.headline)
            if model.runs.isEmpty {
                Text("projects.runs.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.runs) { run in
                Button {
                    selectedRun = run
                } label: {
                    HStack {
                        Text(String(run.id.suffix(8)))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(run.status)
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .aisSurface(cornerRadius: 22)
    }
}

@MainActor
@Observable
private final class ProjectDetailViewModel {
    private let api = APIClient()
    let project: AISProjectListItem
    private(set) var assets: [AISProjectAsset] = []
    private(set) var messages: [AISProjectMessage] = []
    private(set) var memories: [AISProjectMemory] = []
    private(set) var runs: [AISProjectRun] = []
    private(set) var skills: [AISSkillSummary] = []
    private(set) var isWorking = false
    var presentsPhotoPicker = false
    var errorMessage: String?

    init(project: AISProjectListItem) {
        self.project = project
    }

    func load(session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let detail: AISProjectDetail = try await api.get(
                "/api/ais/agent/projects/\(project.id)",
                accessToken: token
            )
            assets = detail.referenceAssets
            messages = detail.messages
            memories = detail.memories
            runs = detail.runs
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSkills(session: SessionStore) async {
        let token = await session.validAccessToken()
        do {
            let page: PageResponse<AISSkillSummary> = try await api.get(
                "/api/ais/skills",
                query: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "size", value: "20")
                ],
                accessToken: token
            )
            skills = page.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhotos(
        _ items: [PhotosPickerItem],
        session: SessionStore
    ) async {
        guard let token = await session.validAccessToken() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            var ids = assets.map(\.id)
            for (index, item) in items.prefix(max(0, 3 - ids.count)).enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
                let result: AISAssetUploadResult = try await api.upload(
                    "/api/ais/assets",
                    fileData: data,
                    fileName: "project-\(project.id)-\(index + 1).\(isPNG ? "png" : "jpg")",
                    mimeType: isPNG ? "image/png" : "image/jpeg",
                    accessToken: token,
                    fields: [
                        "assetType": "reference",
                        "referenceRole": "product_photo",
                        "preserveMode": "reference",
                        "displayName": project.name
                    ]
                )
                ids.append(result.id)
            }
            try await updateAssets(ids, token: token)
            await load(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveAsset(
        at index: Int,
        offset: Int,
        session: SessionStore
    ) async {
        let destination = index + offset
        guard assets.indices.contains(index),
              assets.indices.contains(destination),
              let token = await session.validAccessToken() else { return }
        var values = assets
        values.swapAt(index, destination)
        do {
            try await updateAssets(values.map(\.id), token: token)
            assets = values
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAsset(_ id: String, session: SessionStore) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            try await updateAssets(
                assets.filter { $0.id != id }.map(\.id),
                token: token
            )
            assets.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(
        _ content: String,
        proposesMemory: Bool,
        session: SessionStore
    ) async -> Bool {
        guard let token = await session.validAccessToken() else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let _: AISProjectMessageResult = try await api.post(
                "/api/ais/agent/projects/\(project.id)/messages",
                body: AISProjectMessageRequest(
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    proposeMemory: proposesMemory,
                    memoryType: "project_rule"
                ),
                accessToken: token
            )
            await load(session: session)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateMemory(
        _ memory: AISProjectMemory,
        status: String,
        session: SessionStore
    ) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let _: String = try await api.put(
                "/api/ais/agent/memories/\(memory.id)",
                body: AISMemoryStatusRequest(content: nil, status: status),
                accessToken: token
            )
            await load(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMemory(
        _ memory: AISProjectMemory,
        session: SessionStore
    ) async {
        guard let token = await session.validAccessToken() else { return }
        do {
            let _: String = try await api.delete(
                "/api/ais/agent/memories/\(memory.id)",
                accessToken: token
            )
            await load(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(session: SessionStore) async -> Bool {
        guard let token = await session.validAccessToken() else { return false }
        do {
            let _: String = try await api.delete(
                "/api/ais/agent/projects/\(project.id)",
                accessToken: token
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateAssets(_ ids: [String], token: String) async throws {
        let _: [String: [String]] = try await api.put(
            "/api/ais/agent/projects/\(project.id)/assets",
            body: AISProjectAssetsRequest(referenceAssetIds: ids),
            accessToken: token
        )
    }
}

private struct ProjectSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @FocusState private var isRequirementFocused: Bool
    let projectID: String
    let skill: AISSkillSummary
    let assets: [AISProjectAsset]
    let onStarted: () async -> Void
    @State private var requirement = ""
    @State private var selectedSteps: Set<String> = []
    @State private var quote: AISSkillQuote?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(skill.localizedName).font(.headline)
                    if let description = skill.localizedDescription {
                        Text(description)
                    }
                }
                Section("projects.skills.requirement") {
                    TextField(
                        "projects.skills.requirement.placeholder",
                        text: $requirement,
                        axis: .vertical
                    )
                    .focused($isRequirementFocused)
                    .lineLimit(4...8)
                }
                Section("projects.skills.deliverables") {
                    ForEach(skill.outputs) { output in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    output.required
                                        || selectedSteps.contains(output.key)
                                },
                                set: { selected in
                                    if selected {
                                        selectedSteps.insert(output.key)
                                    } else if !output.required {
                                        selectedSteps.remove(output.key)
                                    }
                                }
                            )
                        ) {
                            Text(output.localizedTitle)
                        }
                        .disabled(output.required)
                    }
                }
                if let quote {
                    Section("projects.skills.quote") {
                        LabeledContent(
                            "projects.skills.points",
                            value: "\(quote.totalPoints)"
                        )
                        LabeledContent(
                            "projects.skills.estimate",
                            value: "\(quote.estimatedMinutes) min"
                        )
                        ForEach(quote.steps) { step in
                            LabeledContent(
                                step.localizedTitle,
                                value: "\(step.pointCost)"
                            )
                        }
                        Button("projects.skills.confirm") {
                            isRequirementFocused = false
                            Task { await confirm(quote) }
                        }
                        .disabled(isWorking || quote.expiresAt <= .now)
                    }
                } else {
                    Button("projects.skills.get_quote") {
                        isRequirementFocused = false
                        Task { await loadQuote() }
                    }
                    .disabled(
                        isWorking
                            || requirement.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("projects.skills.start")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        isRequirementFocused = false
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        isRequirementFocused = false
                    }
                }
            }
            .alert(
                "common.error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("common.done", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                selectedSteps = Set(
                    skill.outputs.filter(\.required).map(\.key)
                )
            }
        }
    }

    private func loadQuote() async {
        guard let token = await session.validAccessToken() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            quote = try await APIClient().post(
                "/api/ais/agent/projects/\(projectID)/skills/\(skill.id)/quote",
                body: AISSkillQuoteRequest(
                    requirement: requirement.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    language: AISLocalization.isChinese ? "zh" : "en",
                    referenceAssetIds: assets.map(\.id),
                    selectedStepKeys: Array(selectedSteps).sorted(),
                    isFollowUp: false,
                    inputs: [:]
                ),
                accessToken: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(_ quote: AISSkillQuote) async {
        guard let token = await session.validAccessToken() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let _: AISSkillRunConfirmation = try await APIClient().post(
                "/api/ais/agent/runs/confirm",
                body: AISSkillConfirmRequest(quoteToken: quote.quoteToken),
                accessToken: token
            )
            NotificationCenter.default.post(
                name: .aisTaskSubmitted,
                object: quote.runId
            )
            await onStarted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProjectRunBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    let run: AISProjectRun
    @State private var detail: AISSkillRunDetail?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(detail?.jobs ?? []) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            AISCachedAsyncImage(
                                url: job.mediaURL,
                                preset: .thumbnail,
                                module: .projectsAssets
                            ) { phase in
                                if case let .success(image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            Text(job.status)
                                .font(.caption.weight(.semibold))
                            Text(job.userRequirement)
                                .font(.caption2)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .aisSurface(cornerRadius: 18)
                    }
                }
                .padding()
            }
            .navigationTitle("projects.runs.board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .task {
                await monitor()
            }
        }
    }

    private func monitor() async {
        guard let token = await session.validAccessToken() else { return }
        do {
            for _ in 0..<120 {
                let value: AISSkillRunDetail = try await APIClient().get(
                    "/api/ais/agent/runs/\(run.id)",
                    accessToken: token
                )
                detail = value
                if !value.jobs.contains(where: \.isActive) { return }
                try await Task.sleep(for: .seconds(5))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("ProjectsView") {
    NavigationStack {
        ProjectsView()
    }
    .environment(SessionStore())
}
