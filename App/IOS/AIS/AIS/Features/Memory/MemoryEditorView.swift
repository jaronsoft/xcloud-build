import SwiftUI

struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let memory: AISMemoryItem?
    let projectId: String?
    let isSaving: Bool
    let onSave: (AISMemoryDraft) async -> Bool
    @State private var draft: AISMemoryDraft

    private static let categories = [
        ("visual_style", "memory.category.visual_style"),
        ("color_preference", "memory.category.color_preference"),
        ("shape_preference", "memory.category.shape_preference"),
        ("image_composition", "memory.category.image_composition"),
        ("text_preference", "memory.category.text_preference"),
        ("negative_preference", "memory.category.negative_preference"),
        ("workflow_preference", "memory.category.workflow_preference"),
        ("brand_rule", "memory.category.brand_rule"),
        ("product_fact", "memory.category.product_fact"),
        ("correction", "memory.category.correction"),
        ("general", "memory.category.general")
    ]

    private static let priorities = [
        (30, "memory.priority.normal"),
        (50, "memory.priority.preferred"),
        (70, "memory.priority.strong"),
        (90, "memory.priority.essential")
    ]

    init(
        memory: AISMemoryItem?,
        projectId: String?,
        isSaving: Bool,
        onSave: @escaping (AISMemoryDraft) async -> Bool
    ) {
        self.memory = memory
        self.projectId = projectId
        self.isSaving = isSaving
        self.onSave = onSave
        _draft = State(initialValue: AISMemoryDraft(
            content: memory?.content ?? "",
            scope: memory?.scope ?? (projectId == nil ? "personal" : "project"),
            memoryType: memory?.memoryType ?? (projectId == nil ? "personal_preference" : "project_rule"),
            category: memory?.category ?? "general",
            brandKey: memory?.brandKey ?? "",
            productKey: memory?.productKey ?? "",
            preferenceKey: memory?.preferenceKey ?? "",
            preferenceValueJson: memory?.preferenceValueJson ?? "",
            weight: Self.priorityLevel(memory?.weight ?? 50),
            projectId: projectId ?? memory?.projectId,
            rowVersion: memory?.rowVersion
        ))
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    "memory.editor.content.placeholder",
                    text: $draft.content,
                    axis: .vertical
                )
                .lineLimit(5...12)
                Picker("memory.editor.scope", selection: $draft.scope) {
                    Text("memory.scope.personal").tag("personal")
                    Text("memory.scope.project").tag("project")
                    Text("memory.scope.brand").tag("brand")
                    Text("memory.scope.product").tag("product")
                }
                .disabled(projectId != nil)
            } footer: {
                Text("memory.editor.help")
            }

            Section("memory.editor.preferences") {
                Picker("memory.editor.category", selection: $draft.category) {
                    ForEach(Self.categories.indices, id: \.self) { index in
                        let option = Self.categories[index]
                        Text(LocalizedStringKey(option.1)).tag(option.0)
                    }
                }
                Picker("memory.editor.priority", selection: $draft.weight) {
                    ForEach(Self.priorities.indices, id: \.self) { index in
                        let option = Self.priorities[index]
                        Text(LocalizedStringKey(option.1)).tag(option.0)
                    }
                }
            }

            if draft.scope == "brand" {
                Section("memory.editor.brand.section") {
                    TextField("memory.editor.brand", text: $draft.brandKey)
                }
            }
            if draft.scope == "product" {
                Section("memory.editor.product.section") {
                    TextField("memory.editor.product", text: $draft.productKey)
                }
            }
        }
        .navigationTitle(memory == nil ? "memory.editor.new" : "memory.editor.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") {
                    Task {
                        if await onSave(draft) { dismiss() }
                    }
                }
                .disabled(
                    isSaving
                        || draft.content.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
        }
    }

    private static func priorityLevel(_ weight: Int) -> Int {
        if weight >= 80 { return 90 }
        if weight >= 60 { return 70 }
        if weight >= 40 { return 50 }
        return 30
    }
}
