import SwiftUI
import UIKit
import Network

@MainActor
final class NetworkConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.wekarepartners.mosa.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: MosaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var cloudSyncTask: Task<Void, Never>?
    @StateObject private var networkMonitor = NetworkConnectivityMonitor()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            NavigationStack { CanvasView() }
                .tabItem { Label("Canvas", systemImage: "square.grid.3x3.fill") }
                .tag(1)
            NavigationStack {
                RecordEditorView(
                    date: DateSupport.key(.now),
                    allowsDateSelection: true,
                    onSaved: {
                        selectedTab = 0
                    }
                )
            }
                .tabItem { Label("Record", systemImage: "square.and.pencil") }
                .tag(2)
            NavigationStack { GalleryView() }
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle.angled") }
                .tag(3)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(MosaPalette.navy)
        .sheet(isPresented: Binding(
            get: { !store.pendingGuestImport.isEmpty },
            set: { if !$0 { Task { await store.skipGuestImport() } } }
        )) {
            GuestImportView()
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .onAppear {
            startCloudSyncIfNeeded()
        }
        .onDisappear {
            cloudSyncTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startCloudSyncIfNeeded()
            } else {
                cloudSyncTask?.cancel()
            }
        }
        .onChange(of: store.isSignedIn) { _, isSignedIn in
            if isSignedIn, scenePhase == .active {
                startCloudSyncIfNeeded()
            } else {
                cloudSyncTask?.cancel()
            }
        }
        .onChange(of: networkMonitor.isConnected) { wasConnected, isConnected in
            if !wasConnected, isConnected, scenePhase == .active {
                startCloudSyncIfNeeded()
            }
        }
    }

    private func startCloudSyncIfNeeded() {
        guard store.isSignedIn, scenePhase == .active else { return }
        let previousTask = cloudSyncTask
        cloudSyncTask = Task {
            previousTask?.cancel()
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await store.syncWithCloud()
        }
    }
}

struct BackfillView: View {
    private struct StagePreset: Identifiable {
        let id: String
        let name: String
        let startYear: Int
        let startMonth: Int
        let endYear: Int
        let endMonth: Int
    }
    private enum MonthEndpoint: String, Identifiable {
        case start
        case end

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    private enum FocusedField: Hashable {
        case stageName
    }

    @EnvironmentObject private var store: MosaStore
    @Environment(\.dismiss) private var dismiss
    var initialCompletion: (() -> Void)?
    @State private var editingID: String?
    @State private var name = ""
    @State private var startYear = Calendar.current.component(.year, from: .now)
    @State private var startMonth = 1
    @State private var endYear = Calendar.current.component(.year, from: .now)
    @State private var endMonth = 1
    @State private var colorCodes = [MosaPalette.dayHex[0]]
    @State private var presetCode: String?
    @State private var birthYear = Calendar.current.component(.year, from: .now)
    @State private var birthMonth = 1
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var selectedMonthEndpoint: MonthEndpoint?
    @State private var visiblePortraitYearCount = 3
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Mark your past")
                Text("Your earlier chapters belong on the canvas.").font(.system(size: 38, weight: .medium, design: .serif))
                Text("Create broad life stages by month. You can change them at any time.").foregroundStyle(MosaPalette.muted)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Stage name (optional)").font(.subheadline.bold()).foregroundStyle(MosaPalette.muted)
                    TextField("A chapter only you can name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .stageName)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(stagePresets) { preset in Button(preset.name) { dismissKeyboard(); apply(preset) }.buttonStyle(.bordered).tint(presetCode == preset.id ? MosaPalette.navy : MosaPalette.muted) } }
                    }
                    monthRangePicker
                    Text("Stage colors").font(.subheadline.bold()).foregroundStyle(MosaPalette.muted)
                    Text("Choose one to three MOSA colors for the stage preview. They do not fill unrecorded days or count as daily feelings.")
                        .font(.caption)
                        .foregroundStyle(MosaPalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                        ForEach(MosaPalette.emotions) { emotion in
                            Button { dismissKeyboard(); toggleStageColor(emotion.hex) } label: {
                                VStack(spacing: 7) {
                                    Image(emotion.iconName).resizable().scaledToFit().frame(width: 48, height: 48)
                                    Text(emotion.name)
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(mosaHex: emotion.hex) ?? MosaPalette.navy).frame(width: 10, height: 10)
                                        Text(emotion.hex).font(.caption2).foregroundStyle(MosaPalette.muted)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .top)
                                .padding(10)
                                .background(colorCodes.contains(emotion.hex) ? MosaPalette.paperSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).stroke(colorCodes.contains(emotion.hex) ? MosaPalette.navy : MosaPalette.muted.opacity(0.18), lineWidth: colorCodes.contains(emotion.hex) ? 2 : 1) }
                            }
                            .buttonStyle(.plain)
                            .disabled(!colorCodes.contains(emotion.hex) && colorCodes.count >= 3)
                            .accessibilityLabel("Choose \(emotion.name), \(emotion.hex)")
                            .accessibilityAddTraits(colorCodes.contains(emotion.hex) ? .isSelected : [])
                        }
                    }
                    Text("\(colorCodes.count)/3 colors selected").font(.caption).foregroundStyle(MosaPalette.muted)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    if let successMessage { Text(successMessage).font(.footnote).foregroundStyle(.green) }
                    Button(editingID == nil ? "Add stage" : "Update stage") { dismissKeyboard(); Task { await save() } }.buttonStyle(MosaPrimaryButtonStyle())
                }
                .mosaCard()

                ForEach(store.lifeStages.filter { !$0.deleted }) { stage in
                    HStack {
                        MultiColorTile(colorCodes: stage.resolvedColorCodes, cornerRadius: 12).frame(width: 42, height: 42)
                        VStack(alignment: .leading) {
                            Text(stage.displayTitle).font(.headline)
                            if !stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("\(stage.startMonth) — \(stage.endMonth)").font(.caption).foregroundStyle(MosaPalette.muted)
                            }
                        }
                        Spacer()
                        Menu { Button("Edit") { edit(stage) }; Button("Delete", role: .destructive) { Task { await store.deleteLifeStage(id: stage.id) } } } label: { Image(systemName: "ellipsis.circle") }
                    }
                    .mosaCard()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "A first portrait")
                    Text("\(store.lifeStages.filter { !$0.deleted }.count) stages · \(markedMonths) marked months").font(.title2.bold())
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visiblePortraitYears, id: \.self) { year in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(year)).font(.headline)
                                MosaicOverview(
                                    year: year,
                                    records: store.records,
                                    stages: store.lifeStages,
                                    columns: 18,
                                    showsStageBackgrounds: true
                                )
                            }
                            .onAppear {
                                if year == visiblePortraitYears.last, visiblePortraitYearCount < portraitYears.count {
                                    visiblePortraitYearCount = min(visiblePortraitYearCount + 3, portraitYears.count)
                                }
                            }
                        }
                    }
                    Text("Stage colors appear only in this preview. Home, Canvas, Gallery and annual statistics use daily records only.").font(.caption).foregroundStyle(MosaPalette.muted)
                }.mosaCard()
                Button(store.lifeStages.isEmpty ? "Skip for now" : "Continue") { if let initialCompletion { initialCompletion() } else { dismiss() } }.buttonStyle(MosaPrimaryButtonStyle())
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Life stages").navigationBarTitleDisplayMode(.inline).mosaPage()
        .onAppear { if editingID == nil { birthYear = defaultStartYear; birthMonth = defaultStartMonth; startYear = defaultStartYear; startMonth = defaultStartMonth; endYear = defaultStartYear; endMonth = defaultStartMonth } }
        .onChange(of: portraitYears) { _, _ in visiblePortraitYearCount = 3 }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .sheet(item: $selectedMonthEndpoint) { endpoint in
            NavigationStack {
                HStack(spacing: 0) {
                    Picker("Month", selection: monthBinding(for: endpoint)) {
                        ForEach(availableMonths(for: endpoint), id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Year", selection: yearBinding(for: endpoint)) {
                        ForEach(availableYears(for: endpoint), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .navigationTitle("\(endpoint.title) month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selectedMonthEndpoint = nil }
                    }
                }
            }
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
        }
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    private var currentMonth: Int { Calendar.current.component(.month, from: .now) }
    private var minimumYear: Int { currentYear - 110 }
    private var defaultStartYear: Int { max(minimumYear, store.profile?.startYear ?? currentYear) }
    private var defaultStartMonth: Int { defaultStartYear == minimumYear ? currentMonth : 1 }
    private var years: [Int] { Array(minimumYear...currentYear) }
    private var stagePresets: [StagePreset] {
        let infancyEnd = addMonths(year: birthYear, month: birthMonth, offset: 24)
        let childhoodStart = addMonths(year: birthYear, month: birthMonth, offset: 25)
        return [
            StagePreset(id: "INFANCY", name: "Infancy", startYear: birthYear, startMonth: birthMonth, endYear: infancyEnd.0, endMonth: infancyEnd.1),
            StagePreset(id: "CHILDHOOD", name: "Childhood", startYear: childhoodStart.0, startMonth: childhoodStart.1, endYear: birthYear + 6, endMonth: 8),
            StagePreset(id: "PRIMARY_SCHOOL", name: "Primary school", startYear: birthYear + 6, startMonth: 9, endYear: birthYear + 12, endMonth: 6),
            StagePreset(id: "TEENAGE_YEARS", name: "Teenage years", startYear: birthYear + 12, startMonth: 9, endYear: birthYear + 18, endMonth: 6),
            StagePreset(id: "COLLEGE", name: "College", startYear: birthYear + 18, startMonth: 9, endYear: birthYear + 22, endMonth: 6),
            StagePreset(id: "EARLY_CAREER", name: "Early career", startYear: birthYear + 22, startMonth: 7, endYear: currentYear, endMonth: currentMonth)
        ].filter { monthKey($0.startYear, $0.startMonth) <= monthKey(currentYear, currentMonth) }
    }
    private var portraitYears: [Int] {
        var values = Set([currentYear])
        for stage in store.lifeStages where !stage.deleted {
            guard let start = Int(stage.startMonth.prefix(4)),
                  let end = Int(stage.endMonth.prefix(4)),
                  start <= min(end, currentYear) else { continue }
            values.formUnion(start...min(end, currentYear))
        }
        for record in store.records where !record.deleted && !record.colorCodes.isEmpty {
            if let year = Int(record.recordDate.prefix(4)) { values.insert(year) }
        }
        return values.filter { $0 >= (store.profile?.startYear ?? currentYear) && $0 <= currentYear }.sorted(by: >)
    }
    private var visiblePortraitYears: [Int] {
        PortraitYearPagination.visibleYears(portraitYears, count: visiblePortraitYearCount)
    }
    private var markedMonths: Int {
        Set(store.lifeStages.filter { !$0.deleted }.flatMap { stage -> [String] in
            guard let start = monthIndex(stage.startMonth), let end = monthIndex(stage.endMonth), start <= end else { return [] }
            return (start...end).map { String(format: "%04d-%02d", $0 / 12, $0 % 12 + 1) }
        }).count
    }
    private func monthKey(_ year: Int, _ month: Int) -> String { String(format: "%04d-%02d", year, month) }
    private func monthIndex(_ value: String) -> Int? { let parts = value.split(separator: "-").compactMap { Int($0) }; return parts.count == 2 ? parts[0] * 12 + parts[1] - 1 : nil }

    private var monthRangePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Month range").font(.subheadline.bold()).foregroundStyle(MosaPalette.muted)
            HStack(alignment: .center, spacing: 8) {
                monthEndpoint(label: "Start", year: startYear, month: startMonth, endpoint: .start)
                Image(systemName: "arrow.right").foregroundStyle(MosaPalette.muted)
                monthEndpoint(label: "End", year: endYear, month: endMonth, endpoint: .end)
            }
            .padding(12)
            .background(MosaPalette.paperSecondary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func monthEndpoint(label: String, year: Int, month: Int, endpoint: MonthEndpoint) -> some View {
        Button {
            dismissKeyboard()
            selectedMonthEndpoint = endpoint
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.caption.bold()).foregroundStyle(MosaPalette.muted)
                HStack(spacing: 6) {
                    Text(verbatim: "\(monthName(month)) \(year)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MosaPalette.navy)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(MosaPalette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) month, \(monthName(month)) \(year)")
        .accessibilityHint("Opens the month and year picker")
    }

    private func yearBinding(for endpoint: MonthEndpoint) -> Binding<Int> {
        Binding {
            endpoint == .start ? startYear : endYear
        } set: { newYear in
            presetCode = nil
            if endpoint == .start {
                startYear = newYear
                endYear = newYear
                endMonth = startMonth
                if newYear == currentYear { startMonth = min(startMonth, currentMonth) }
                endMonth = startMonth
            } else {
                endYear = newYear
                if newYear == currentYear { endMonth = min(endMonth, currentMonth) }
            }
        }
    }

    private func monthBinding(for endpoint: MonthEndpoint) -> Binding<Int> {
        Binding {
            endpoint == .start ? startMonth : endMonth
        } set: { newMonth in
            presetCode = nil
            if endpoint == .start {
                startMonth = newMonth
                endYear = startYear
                endMonth = newMonth
            } else {
                endMonth = newMonth
            }
        }
    }

    private func availableMonths(for endpoint: MonthEndpoint) -> ClosedRange<Int> {
        let year = endpoint == .start ? startYear : endYear
        let canvasFirstMonth = year == minimumYear ? currentMonth : 1
        let firstMonth = endpoint == .end && year == startYear ? max(startMonth, canvasFirstMonth) : canvasFirstMonth
        return firstMonth...(year == currentYear ? currentMonth : 12)
    }

    private func availableYears(for endpoint: MonthEndpoint) -> [Int] {
        endpoint == .start ? years : Array(startYear...currentYear)
    }

    private func monthName(_ month: Int) -> String {
        DateFormatter().shortMonthSymbols[month - 1]
    }

    private func save() async {
        dismissKeyboard()
        errorMessage = nil
        successMessage = nil
        do {
            try await store.saveLifeStage(id: editingID, name: name, startMonth: monthKey(startYear, startMonth), endMonth: monthKey(endYear, endMonth), colorCodes: colorCodes, presetCode: presetCode)
            reset()
            successMessage = "Stage saved. Its colors now appear in the stage preview."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    private func edit(_ stage: LocalLifeStage) { successMessage = nil; editingID = stage.id; name = stage.name; colorCodes = stage.resolvedColorCodes; presetCode = stage.presetCode; let start = stage.startMonth.split(separator: "-").compactMap { Int($0) }; let end = stage.endMonth.split(separator: "-").compactMap { Int($0) }; if start.count == 2 { birthYear = start[0]; birthMonth = start[1]; startYear = start[0]; startMonth = start[1] }; if end.count == 2 { endYear = end[0]; endMonth = end[1] } }
    private func reset() { editingID = nil; name = ""; presetCode = nil; colorCodes = [MosaPalette.dayHex[0]]; birthYear = defaultStartYear; birthMonth = defaultStartMonth; startYear = defaultStartYear; startMonth = defaultStartMonth; endYear = defaultStartYear; endMonth = defaultStartMonth }
    private func toggleStageColor(_ hex: String) { if let index = colorCodes.firstIndex(of: hex) { if colorCodes.count > 1 { colorCodes.remove(at: index) } } else if colorCodes.count < 3 { colorCodes.append(hex) } }
    private func apply(_ preset: StagePreset) {
        presetCode = preset.id
        name = preset.name
        startYear = min(preset.startYear, currentYear)
        startMonth = preset.startYear == currentYear ? min(preset.startMonth, currentMonth) : preset.startMonth
        endYear = min(preset.endYear, currentYear)
        endMonth = preset.endYear >= currentYear ? min(preset.endMonth, currentMonth) : preset.endMonth
    }
    private func dismissKeyboard() {
        focusedField = nil
    }
    private func addMonths(year: Int, month: Int, offset: Int) -> (Int, Int) { let index = year * 12 + month - 1 + offset; return (index / 12, index % 12 + 1) }
}

struct GalleryView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var drafts: [Int: String] = [:]
    @State private var includeNotes: [Int: Bool] = [:]
    @State private var themes: [Int: ArtworkTheme] = [:]
    @State private var errors: [Int: String] = [:]
    @State private var showGenerationNotice = false
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    private var years: [Int] {
        GalleryResolver.years(records: store.records, stages: store.lifeStages, startYear: store.profile?.startYear ?? currentYear, currentYear: currentYear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Life Gallery")
                Text("A year becomes a work of art.").font(.system(size: 40, weight: .medium, design: .serif))
                Text("AI creates a private image from a past year or from the current year through today. Your color structure always participates; you decide whether daily words are included.")
                    .foregroundStyle(MosaPalette.muted)
                NavigationLink(destination: BackfillView()) { Text("Color your past") }.buttonStyle(MosaSecondaryButtonStyle())
                if years.isEmpty {
                    Text("Add at least one daily record to create your first annual artwork. Stage background colors do not count as daily records.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MosaPalette.muted)
                        .frame(maxWidth: .infinity)
                        .mosaCard()
                }
                ForEach(years, id: \.self) { year in
                    let existing = store.annualWorks.first { $0.year == year }
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: String(year))
                        if existing?.isYearToDate == true || (existing == nil && year == currentYear) {
                            Text("Year-to-date artwork · through \(artworkDate(existing?.periodEnd ?? DateSupport.key(.now)))")
                                .font(.subheadline.bold())
                                .foregroundStyle(MosaPalette.muted)
                        }
                        TextField("Untitled, \(year)", text: Binding(get: { drafts[year] ?? existing?.title ?? "Untitled, \(year)" }, set: { drafts[year] = $0 })).textFieldStyle(.roundedBorder)

                        Text("Choose a natural theme")
                            .font(.subheadline.bold())
                            .foregroundStyle(MosaPalette.navy)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach(ArtworkTheme.allCases, id: \.self) { theme in
                                let selected = selectedTheme(year: year, work: existing) == theme
                                Button {
                                    themes[year] = theme
                                    errors[year] = nil
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(theme.title).font(.subheadline.bold())
                                        Text(theme.detail)
                                            .font(.caption2)
                                            .foregroundStyle(MosaPalette.muted)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                                    .padding(11)
                                    .background(selected ? MosaPalette.paperSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(selected ? MosaPalette.navy : MosaPalette.muted.opacity(0.25), lineWidth: selected ? 2 : 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        if selectedTheme(year: year, work: existing) == nil {
                            Text("Select one theme to enable generation.")
                                .font(.caption)
                                .foregroundStyle(MosaPalette.muted)
                        }

                        Toggle(isOn: Binding(get: { includeNotes[year] ?? existing?.includeNotes ?? true }, set: { includeNotes[year] = $0 })) {
                            Text("Include this year’s daily words as private creative material. AI may translate them into subtle natural imagery, but must not quote them or identify people.")
                                .font(.subheadline)
                        }
                        if store.artworkGenerationPolicy?.quotaReached == true {
                            Text("This month’s artwork has already been requested. You can generate again \(quotaResetDescription).")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let message = errors[year], !message.isEmpty {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        Button("Save title") { Task { await store.saveAnnualTitle(year: year, title: drafts[year] ?? existing?.title ?? "Untitled, \(year)") } }.buttonStyle(MosaSecondaryButtonStyle())
                        if existing?.generationStatus == "SUBMITTING" || existing?.generationStatus == "QUEUED" || existing?.generationStatus == "RUNNING" {
                            Button("Refresh status") { Task { await store.refreshGallery() } }
                                .buttonStyle(MosaSecondaryButtonStyle())
                        }
                        Button(generateTitle(existing)) {
                            Task { await generate(year: year) }
                        }
                        .buttonStyle(MosaPrimaryButtonStyle())
                        .disabled(
                            selectedTheme(year: year, work: existing) == nil
                                || existing?.generationStatus == "SUBMITTING"
                                || existing?.generationStatus == "QUEUED"
                                || existing?.generationStatus == "RUNNING"
                                || existing?.workflowStatus == "PENDING"
                                || existing?.workflowStatus == "RUNNING"
                                || existing?.workflowStatus == "RETRYING"
                                || store.artworkGenerationPolicy?.quotaReached == true
                        )
                        AnnualArtworkPreview(year: year, work: existing)
                    }
                    .mosaCard()
                }
            }
            .padding(20)
        }
        .navigationTitle("Gallery").navigationBarTitleDisplayMode(.inline).mosaPage()
        .alert("Your share card is taking shape", isPresented: $showGenerationNotice) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("This may take a little while. Feel free to rest or explore MOSA—we’ll keep creating in the background. Come back soon to see your finished image.")
        }
        .task {
            await store.refreshGallery()
        }
        .task(id: pendingTaskSignature) {
            guard !pendingTaskSignature.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await store.refreshGallery()
                if pendingTaskSignature.isEmpty { return }
            }
        }
    }

    private var pendingTaskSignature: String {
        store.annualWorks
            .filter {
                $0.generationStatus == "SUBMITTING" || $0.generationStatus == "QUEUED" || $0.generationStatus == "RUNNING"
                    || $0.workflowStatus == "PENDING" || $0.workflowStatus == "RUNNING" || $0.workflowStatus == "RETRYING"
            }
            .map { "\($0.year):\($0.workflowID ?? $0.taskID ?? ""):\($0.workflowStatus ?? $0.generationStatus ?? "")" }
            .joined(separator: "|")
    }

    private func generateTitle(_ work: LocalAnnualWork?) -> String {
        let status = work?.generationStatus
        if work?.workflowStatus == "FAILED" || status == "FAILED" { return "Retry share card" }
        if work?.workflowStatus == "COMPLETED" { return "Regenerate share card" }
        if status == "SUBMITTING" { return "Sending…" }
        if status == "QUEUED" { return "Waiting…" }
        if status == "RUNNING" { return "AI is painting…" }
        if work?.workflowStatus == "RUNNING" || work?.workflowStatus == "RETRYING" { return "Building card…" }
        return "Generate share card"
    }

    private func generate(year: Int) async {
        errors[year] = nil
        let work = store.annualWorks.first { $0.year == year }
        guard let theme = selectedTheme(year: year, work: work) else {
            errors[year] = "Choose an artwork theme before generating."
            return
        }
        do {
            try await store.generateAnnualArtwork(
                year: year,
                includeNotes: includeNotes[year] ?? work?.includeNotes ?? true,
                themeType: theme
            )
            showGenerationNotice = true
        } catch {
            errors[year] = generationErrorMessage(error)
            await store.refreshArtworkGenerationPolicy()
        }
    }

    private func selectedTheme(year: Int, work: LocalAnnualWork?) -> ArtworkTheme? {
        themes[year] ?? work?.themeType
    }

    private func generationErrorMessage(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        switch apiError.code {
        case "MOSA_AI_MONTHLY_LIMIT_REACHED":
            return "This month’s artwork request has already been used."
        case "UNKNOWN_THEME":
            return "Choose a supported artwork theme."
        case "LEGACY_MAPPING_REQUIRED":
            return "Map historical colors before generating this artwork."
        default:
            return apiError.message
        }
    }

    private var quotaResetDescription: String {
        guard let value = store.artworkGenerationPolicy?.nextResetAt else { return "next month" }
        return artworkDate(String(value.prefix(10)))
    }

    private func artworkDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(value.prefix(10))) else { return value }
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

private struct AnnualArtworkPreview: View {
    @EnvironmentObject private var store: MosaStore
    let year: Int
    let work: LocalAnnualWork?
    @State private var imageData: Data?
    @State private var loadProgress: ArtworkImageDownloadProgress?
    @State private var loadError: String?
    @State private var loadAttempt = 0
    @State private var shareURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share card", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(MosaSecondaryButtonStyle())
                    .accessibilityHint("Shares only this artwork image through the iOS share sheet.")
                }
            } else if work?.shareCardAvailable == true, let loadProgress {
                VStack(spacing: 10) {
                    if let fraction = loadProgress.fractionCompleted {
                        ProgressView(value: fraction)
                            .progressViewStyle(.circular)
                        Text("Loading share card · \(Int((fraction * 100).rounded()))%")
                            .font(.caption.bold())
                    } else {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading share card…")
                            .font(.caption.bold())
                    }
                    Text("Your share card is ready and is being loaded securely.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(MosaPalette.muted)
                .padding(24)
            } else if work?.shareCardAvailable == true, let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                    Text(loadError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Retry loading share card") { loadAttempt += 1 }
                        .buttonStyle(MosaSecondaryButtonStyle())
                }
                .foregroundStyle(MosaPalette.muted)
                .padding(24)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: displayStatus == "FAILED" ? "exclamationmark.triangle" : status == "RUNNING" ? "paintbrush.pointed.fill" : "photo.artframe")
                        .font(.system(size: 34))
                    Text(statusHeading).font(.headline)
                    if let theme = work?.themeType {
                        Text(theme.title.uppercased())
                            .font(.caption.bold())
                    }
                    Text(statusMessage).font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(MosaPalette.muted)
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(MosaPalette.paperSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .clipped()
        .task(id: "\(work?.workflowID ?? work?.taskID ?? ""):\(work?.workflowStatus ?? status):\(loadAttempt)") {
            imageData = nil
            shareURL = nil
            loadError = nil
            if let cachedData = store.cachedShareCardImage(year: year),
               let cachedImage = UIImage(data: cachedData),
               let pngData = cachedImage.pngData() {
                imageData = cachedData
                shareURL = try? ArtworkImageShareFile.write(pngData: pngData, year: year)
            }
            guard work?.shareCardAvailable == true else {
                loadProgress = nil
                return
            }
            if let work, store.hasCurrentShareCardImage(work) {
                loadProgress = nil
                return
            }
            loadProgress = ArtworkImageDownloadProgress(receivedBytes: 0, expectedBytes: nil)
            do {
                guard let work else { return }
                let data = try await store.refreshShareCardImageCache(for: work) { progress in
                    loadProgress = progress
                }
                try Task.checkCancellation()
                guard let image = UIImage(data: data), let pngData = image.pngData() else {
                    throw APIError(message: "The share card image could not be decoded.", code: "MOSA_SHARE_CARD_IMAGE_INVALID", statusCode: 0, retryAfterSeconds: nil)
                }
                imageData = data
                shareURL = try ArtworkImageShareFile.write(pngData: pngData, year: year)
                loadProgress = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                loadProgress = nil
                loadError = "We couldn’t load this share card. Check your connection and try again."
            }
        }
        .accessibilityLabel("\(year) MOSA share card, \((work?.workflowStatus ?? status).lowercased())")
    }

    private var status: String { work?.generationStatus ?? "NOT_GENERATED" }
    private var displayStatus: String {
        if work?.workflowStatus == "FAILED" { return "FAILED" }
        if work?.workflowStatus == "RUNNING" || work?.workflowStatus == "RETRYING" {
            return work?.workflowStatus ?? "RUNNING"
        }
        return status
    }
    private var statusHeading: String {
        guard displayStatus == "FAILED", let failedStage = work?.failedStage else {
            return displayStatus.replacingOccurrences(of: "_", with: " ")
        }
        return "FAILED · \(stageLabel(failedStage))"
    }
    private var statusMessage: String {
        if work?.workflowStatus == "RUNNING" || work?.workflowStatus == "RETRYING" {
            return "Building your share card · \(stageLabel(work?.currentStage).lowercased())."
        }
        if work?.workflowStatus == "FAILED" {
            switch work?.errorCode {
            case "MOSA_AI_NOT_CONFIGURED":
                return "Share-card AI is not configured on the server yet. Your completed artwork is preserved."
            case "MOSA_AI_INPUT_CHANGED":
                return "This year changed before the share card was completed. Start again with the latest records."
            case "MOSA_ARTWORK_VALIDATION_FAILED":
                return "The annual artwork did not pass visual review. The original image and your records are preserved."
            case "MOSA_AI_OUTPUT_INVALID":
                return "The AI returned an invalid result during \(stageLabel(work?.failedStage).lowercased()). You can retry safely."
            case "MOSA_AI_PROVIDER_REJECTED":
                return "The share-card AI service rejected this request. Your completed artwork is preserved."
            case "THIRD_PARTY_AI_NODE_FAILED", "AI_NODE_UNAVAILABLE", "MOSA_AI_UPSTREAM_UNAVAILABLE":
                return "The assigned image node could not complete this stage. Retry when an allowed node is available."
            case "AI_PROVIDER_TIMEOUT", "MOSA_AI_PROVIDER_PENDING":
                return "The image service did not finish in time. You can retry without changing your records."
            case "MOSA_SHARE_CARD_VISUAL_MISSING":
                return "The portrait card visual was not available after generation. Retry to rebuild only this stage."
            default:
                break
            }
            return "The share card stopped during \(stageLabel(work?.failedStage).lowercased()). Your completed artwork and records are preserved."
        }
        switch status {
        case "SUBMITTING": return "Sending your artwork request…"
        case "QUEUED": return "Waiting for an image server…"
        case "RUNNING": return "AI is painting this year…"
        case "FAILED":
            switch work?.errorCode {
            case "MOSA_AI_NOT_CONFIGURED": return "Share-card AI is not configured on the server yet."
            case "MOSA_AI_INPUT_CHANGED": return "This year changed before painting began. Start a new artwork with the latest records."
            case "LEGACY_MAPPING_REQUIRED": return "Map historical colors before generating this artwork."
            case "MOSA_AI_PROVIDER_REJECTED": return "The image service could not complete this artwork. Your records are unchanged."
            default: return "Generation failed. Your records are unchanged."
            }
        default: return "No share card has been generated yet."
        }
    }

    private func stageLabel(_ stage: String?) -> String {
        switch stage {
        case "ARTWORK": return "ANNUAL ARTWORK"
        case "ARTWORK_VALIDATION": return "VISUAL REVIEW"
        case "STORY": return "STORY"
        case "SHARE_CARD_VISUAL_LAYER": return "CARD VISUAL"
        case "LAYOUT": return "CARD LAYOUT"
        case "BRAND": return "BRAND LAYER"
        case "EXPORT": return "CARD EXPORT"
        case "FINAL_RESULT_ASSEMBLY": return "FINAL ASSEMBLY"
        default: return "PROCESSING"
        }
    }
}

private struct GuestImportView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "Keep your local days")
            Text("Import \(store.pendingGuestImport.count) record\(store.pendingGuestImport.count == 1 ? "" : "s")?")
                .font(.system(size: 30, weight: .medium, design: .serif))
            Text("Cloud dates with existing records stay unchanged. You can keep using this device if you choose Not now.")
                .foregroundStyle(MosaPalette.muted)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            Button(busy ? "Importing…" : "Import local records") {
                Task {
                    busy = true
                    do { try await store.importPendingGuestData() }
                    catch { errorMessage = error.localizedDescription }
                    busy = false
                }
            }
            .buttonStyle(MosaPrimaryButtonStyle())
            .disabled(busy)
            Button("Not now") { Task { await store.skipGuestImport() } }
                .buttonStyle(MosaSecondaryButtonStyle())
                .disabled(busy)
        }
        .padding(24)
        .mosaPage()
    }
}
