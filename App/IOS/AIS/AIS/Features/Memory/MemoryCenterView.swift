import SwiftUI

struct MemoryCenterView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: MemoryCenterViewModel
    @State private var editingMemory: AISMemoryItem?
    @State private var presentsEditor = false
    @State private var presentsExtraction = false
    @State private var selectionMode = false
    private let projectId: String?

    init(projectId: String? = nil) {
        self.projectId = projectId
        _model = State(
            initialValue: MemoryCenterViewModel(projectId: projectId)
        )
    }

    var body: some View {
        Group {
            if model.isLoading && model.items.isEmpty {
                ProgressView("common.loading")
            } else {
                list
            }
        }
        .navigationTitle("memory.title")
        .searchable(text: $model.keyword, prompt: "memory.search")
        .onSubmit(of: .search) {
            Task { await model.reload(session: session) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    presentsExtraction = true
                } label: {
                    Label("memory.extraction.title", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    selectionMode.toggle()
                    if !selectionMode { model.selectedIDs.removeAll() }
                } label: {
                    Text(selectionMode ? "common.done" : "memory.select")
                }
                Button {
                    editingMemory = nil
                    presentsEditor = true
                } label: {
                    Label("memory.editor.new", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectionMode && !model.selectedIDs.isEmpty {
                bulkBar
            }
        }
        .task {
            await model.reload(session: session)
            model.resumePolling(session: session)
        }
        .refreshable {
            await model.reload(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resumePolling(session: session)
            } else {
                model.stopPolling()
            }
        }
        .onDisappear {
            model.stopPolling()
        }
        .sheet(isPresented: $presentsEditor) {
            NavigationStack {
                MemoryEditorView(
                    memory: editingMemory,
                    projectId: projectId ?? editingMemory?.projectId,
                    isSaving: model.isWorking
                ) { draft in
                    await model.save(
                        draft: draft,
                        editing: editingMemory,
                        session: session
                    )
                }
            }
        }
        .sheet(isPresented: $presentsExtraction) {
            NavigationStack {
                MemoryExtractionView(
                    batches: model.batches,
                    isWorking: model.isWorking
                ) {
                    await model.startExtraction(session: session)
                } showCandidates: {
                    presentsExtraction = false
                    model.status = "proposed"
                    Task { await model.reload(session: session) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.done") {
                            presentsExtraction = false
                        }
                    }
                }
            }
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

    private var list: some View {
        List {
            filterSection
            ForEach(model.items) { memory in
                memoryRow(memory)
                    .onAppear {
                        if memory.id == model.items.last?.id {
                            Task { await model.loadNext(session: session) }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if memory.status == "disabled" {
                            statusButton(memory, action: "enable", title: "memory.enable")
                                .tint(.green)
                        } else if memory.status == "proposed" {
                            statusButton(memory, action: "confirm", title: "memory.confirm")
                                .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await model.delete(memory, session: session) }
                        } label: {
                            Label("common.delete", systemImage: "trash")
                        }
                        if memory.status != "disabled" {
                            statusButton(memory, action: "disable", title: "memory.disable")
                                .tint(.orange)
                        }
                    }
            }
            if model.isLoading && !model.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .overlay {
            if model.items.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "memory.empty",
                    systemImage: "brain.head.profile",
                    description: Text("memory.empty.description")
                )
            }
        }
    }

    private var filterSection: some View {
        Section {
            if let latestBatch = model.batches.first,
               latestBatch.status == "succeeded",
               latestBatch.candidateCount > 0 {
                Button {
                    model.status = "proposed"
                    Task { await model.reload(session: session) }
                } label: {
                    Label(
                        String.localizedStringWithFormat(
                            String(localized: "memory.extraction.view_candidates"),
                            latestBatch.candidateCount
                        ),
                        systemImage: "sparkles"
                    )
                }
            }
            Picker("memory.filter.status", selection: $model.status) {
                Text("memory.filter.all").tag("")
                Text("memory.status.confirmed").tag("confirmed")
                Text("memory.status.proposed").tag("proposed")
                Text("memory.status.disabled").tag("disabled")
                Text("memory.status.rejected").tag("rejected")
            }
            .onChange(of: model.status) {
                Task { await model.reload(session: session) }
            }
        }
    }

    private func memoryRow(_ memory: AISMemoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if selectionMode {
                Button {
                    if model.selectedIDs.contains(memory.id) {
                        model.selectedIDs.remove(memory.id)
                    } else {
                        model.selectedIDs.insert(memory.id)
                    }
                } label: {
                    Image(
                        systemName: model.selectedIDs.contains(memory.id)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("memory.select")
            }
            NavigationLink {
                MemoryDetailView(memory: memory)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(memory.content)
                        .font(.body)
                        .lineLimit(4)
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(memory.statusLocalizationKey))
                            .font(.caption.bold())
                        Text(LocalizedStringKey(memory.categoryLocalizationKey))
                            .font(.caption)
                        Text(LocalizedStringKey(memory.priorityLocalizationKey))
                            .font(.caption)
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "memory.evidence_count"),
                                memory.evidenceCount
                            )
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .disabled(selectionMode)
            Button {
                editingMemory = memory
                presentsEditor = true
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("memory.editor.edit")
        }
    }

    private func statusButton(
        _ memory: AISMemoryItem,
        action: String,
        title: LocalizedStringKey
    ) -> some View {
        Button {
            Task { await model.change(memory, action: action, session: session) }
        } label: {
            Label(title, systemImage: "checkmark.circle")
        }
    }

    private var bulkBar: some View {
        HStack {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "memory.selected_count"),
                    model.selectedIDs.count
                )
            )
            .font(.subheadline.bold())
            Spacer()
            Button("memory.bulk.confirm") {
                Task { await model.bulk(action: "bulk-confirm", session: session) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Button("memory.bulk.reject") {
                Task { await model.bulk(action: "bulk-reject", session: session) }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .background(.regularMaterial)
    }
}
