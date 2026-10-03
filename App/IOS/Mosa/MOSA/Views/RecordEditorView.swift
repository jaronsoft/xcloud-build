import SwiftUI

struct RecordEditorView: View {
    private enum FocusedField {
        case note
        case tags
    }

    private struct Draft: Equatable {
        let note: String
        let emotions: [LocalEmotion]
        let intensity: EmotionIntensity
        let tags: String
    }

    @EnvironmentObject private var store: MosaStore
    @Environment(\.dismiss) private var dismiss
    let date: String
    let allowsDateSelection: Bool
    let onSaved: (() -> Void)?

    @State private var selectedDate: Date
    @State private var note = ""
    @State private var selectedEmotions: [LocalEmotion] = []
    @State private var intensity: EmotionIntensity = .clear
    @State private var tags = ""
    @State private var saving = false
    @State private var confirmsDelete = false
    @State private var saveError: String?
    @State private var baselineDraft: Draft?
    @State private var pendingDate: Date?
    @State private var revertingDateChange = false
    @State private var confirmsDiscard = false
    @FocusState private var focusedField: FocusedField?

    init(
        date: String,
        allowsDateSelection: Bool = false,
        onSaved: (() -> Void)? = nil
    ) {
        self.date = date
        self.allowsDateSelection = allowsDateSelection
        self.onSaved = onSaved
        _selectedDate = State(initialValue: DateSupport.date(date) ?? .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Daily record")
                Text(DateSupport.readable(recordDate))
                    .font(.system(size: 38, weight: .medium, design: .serif))
                if allowsDateSelection {
                    dateSelectionSection
                }
                colorSection
                detailsSection
                actionSection
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            if baselineDraft == nil {
                loadRecord(for: recordDate)
            }
        }
        .onChange(of: selectedDate, handleDateChange)
        .confirmationDialog("Delete this day?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.deleteRecord(date: recordDate)
                    if allowsDateSelection {
                        loadRecord(for: recordDate)
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard and switch date", role: .destructive) {
                switchToPendingDate()
            }
            Button("Keep editing", role: .cancel) {
                pendingDate = nil
            }
        } message: {
            Text("Your changes for \(DateSupport.readable(recordDate)) have not been saved.")
        }
    }

    private var dateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Record date", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                DatePicker(
                    "Record date",
                    selection: $selectedDate,
                    in: earliestRecordDate...Calendar.current.startOfDay(for: .now),
                    displayedComponents: .date
                )
                .labelsHidden()
            }

            Divider()

            NavigationLink(destination: BackfillView()) {
                Label("Color a time period", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(MosaSecondaryButtonStyle())
        }
        .mosaCard()
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What feelings belong to this day?").font(.headline)
            Text("Choose up to three. The first is the main feeling; MOSA keeps each color's meaning fixed.")
                .font(.subheadline)
                .foregroundStyle(MosaPalette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(MosaPalette.emotions) { emotion in
                    emotionButton(emotion: emotion)
                }
            }
            Text("\(selectedEmotions.count)/3 feelings selected")
                .font(.caption)
                .foregroundStyle(MosaPalette.muted)
            if !selectedEmotions.isEmpty {
                Picker("Intensity", selection: $intensity) {
                    Text("A little").tag(EmotionIntensity.mild)
                    Text("Clearly").tag(EmotionIntensity.clear)
                    Text("Strongly").tag(EmotionIntensity.strong)
                }.pickerStyle(.segmented)
            }
        }
        .mosaCard()
    }

    private func emotionButton(emotion: MosaEmotionDefinition) -> some View {
        let selectedIndex = selectedEmotions.firstIndex { $0.emotionCode == emotion.code }
        let isSelected = selectedIndex != nil
        return Button {
            if isSelected {
                selectedEmotions.removeAll { $0.emotionCode == emotion.code }
            } else if selectedEmotions.count < 3 {
                selectedEmotions.append(LocalEmotion(emotionCode: emotion.code, role: .secondary, colorCode: emotion.hex))
            }
            selectedEmotions = selectedEmotions.enumerated().map { offset, value in
                var copy = value
                copy.role = offset == 0 ? .primary : .secondary
                return copy
            }
        } label: {
            VStack(spacing: 7) {
                Image(emotion.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(mosaHex: emotion.hex) ?? MosaPalette.navy)
                        .frame(width: 10, height: 10)
                    Text(emotion.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Text(selectedIndex == 0 ? "Main feeling" : emotion.childLabel)
                    .font(.caption)
                    .foregroundStyle(MosaPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(height: 32, alignment: .top)
            }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
                .padding(10)
                .background(isSelected ? MosaPalette.paperSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isSelected && selectedEmotions.count >= 3)
        .accessibilityLabel("Choose \(emotion.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A few words (optional)").font(.headline)
            TextEditor(text: $note)
                .frame(minHeight: 140)
                .padding(8)
                .background(MosaPalette.paperSecondary, in: RoundedRectangle(cornerRadius: 14))
                .focused($focusedField, equals: .note)
                .onChange(of: note) { _, value in
                    if value.count > 1000 { note = String(value.prefix(1000)) }
                }
            TextField("family, work, journey", text: $tags)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .tags)
            Text("Separate up to five tags with commas.")
                .font(.caption)
                .foregroundStyle(MosaPalette.muted)
        }
        .mosaCard()
    }

    @ViewBuilder
    private var actionSection: some View {
        if !hasMeaningfulContent {
            Label("Add a note or choose a color.", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let saveError {
            Text(saveError)
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button(saving ? "Saving…" : "Save this day") {
            Task { await save() }
        }
        .buttonStyle(MosaPrimaryButtonStyle())
        .disabled(saving || !hasMeaningfulContent)

        if store.record(for: recordDate) != nil {
            Button("Delete this record", role: .destructive) { confirmsDelete = true }
                .frame(maxWidth: .infinity)
        }
    }

    private var recordDate: String {
        allowsDateSelection ? DateSupport.key(selectedDate) : date
    }

    private var earliestRecordDate: Date {
        Calendar.current.date(
            from: DateComponents(
                year: store.profile?.startYear ?? Calendar.current.component(.year, from: .now),
                month: 1,
                day: 1
            )
        ) ?? Calendar.current.startOfDay(for: .now)
    }

    private var currentDraft: Draft {
        Draft(
            note: note,
            emotions: selectedEmotions,
            intensity: intensity,
            tags: tags
        )
    }

    private func loadRecord(for date: String) {
        let record = store.record(for: date)
        note = record?.note ?? ""
        selectedEmotions = record?.emotions ?? []
        intensity = record?.emotionIntensity ?? .clear
        tags = record?.tagNames.joined(separator: ", ") ?? ""
        saveError = nil
        baselineDraft = currentDraft
    }

    private func handleDateChange(oldDate: Date, newDate: Date) {
        guard allowsDateSelection else { return }
        if revertingDateChange {
            revertingDateChange = false
            return
        }
        if let baselineDraft, currentDraft != baselineDraft {
            pendingDate = newDate
            revertingDateChange = true
            selectedDate = oldDate
            confirmsDiscard = true
            return
        }
        loadRecord(for: DateSupport.key(newDate))
    }

    private func switchToPendingDate() {
        guard let pendingDate else { return }
        self.pendingDate = nil
        revertingDateChange = true
        selectedDate = pendingDate
        loadRecord(for: DateSupport.key(pendingDate))
    }

    private func save() async {
        guard hasMeaningfulContent else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        let names = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try await store.saveRecord(
                date: recordDate,
                note: note,
                intentionalBlank: false,
                colorCodes: selectedEmotions.map(\.colorCode),
                tagNames: names,
                emotions: selectedEmotions,
                emotionIntensity: selectedEmotions.isEmpty ? nil : intensity,
                blankSource: nil
            )
            baselineDraft = currentDraft
            focusedField = nil
            store.notice = store.isSignedIn
                ? "Saved on this iPhone · Syncing to cloud."
                : "Saved on this iPhone."
            if allowsDateSelection {
                onSaved?()
            } else {
                dismiss()
            }
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "The record could not be saved."
        }
    }

    private var hasMeaningfulContent: Bool {
        !selectedEmotions.isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
