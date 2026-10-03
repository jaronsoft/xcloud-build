import SwiftUI

struct CanvasView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var displayedMonth: Date
    @State private var selectedDate: Date?
    @State private var editorDate: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = Calendar.current.veryShortWeekdaySymbols

    init(initialYear: Int? = nil, initialMonth: Int? = nil) {
        let calendar = Calendar.current
        let now = Date.now
        let year = initialYear ?? calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let month = initialMonth ?? (year == calendar.component(.year, from: now) ? currentMonth : 12)
        _displayedMonth = State(initialValue: calendar.date(
            from: DateComponents(year: year, month: month, day: 1)
        ) ?? now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Life canvas")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 38, weight: .medium, design: .serif))
                        Text("\(dailyRecordCount) daily records · unrecorded days stay blank")
                            .foregroundStyle(MosaPalette.muted)
                    }
                    Spacer()
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(!canMove(-1))
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(!canMove(1))
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Picker("Year", selection: Binding(get: { displayedYear }, set: { setDisplayed(year: $0, month: min(displayedMonthNumber, $0 == currentYear ? currentMonth : 12)) })) {
                        ForEach(Array((store.profile?.startYear ?? currentYear)...currentYear).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Month", selection: Binding(get: { displayedMonthNumber }, set: { setDisplayed(year: displayedYear, month: $0) })) {
                        ForEach(1...(displayedYear == currentYear ? currentMonth : 12), id: \.self) { Text(DateFormatter().monthSymbols[$0 - 1]).tag($0) }
                    }
                }
                .pickerStyle(.menu)

                VStack(spacing: 10) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(weekdays.indices, id: \.self) { index in
                            Text(weekdays[index])
                                .font(.caption.bold())
                                .foregroundStyle(MosaPalette.muted)
                        }
                        ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                            if let date {
                                dayButton(date)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                .mosaCard()
                Label("Only daily records add color to the canvas", systemImage: "square.fill")
                    .font(.caption)
                    .foregroundStyle(MosaPalette.navy)

                NavigationLink(destination: AnnualView(year: displayedYear)) {
                    Text("View year reflection")
                }
                .buttonStyle(MosaSecondaryButtonStyle())
                NavigationLink(destination: BackfillView()) { Text("Color your past") }
                    .buttonStyle(MosaSecondaryButtonStyle())
            }
            .padding(20)
        }
        .navigationTitle("Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
        .navigationDestination(item: $editorDate) { date in
            RecordEditorView(date: date)
        }
    }

    private var displayedYear: Int { Calendar.current.component(.year, from: displayedMonth) }
    private var displayedMonthNumber: Int { Calendar.current.component(.month, from: displayedMonth) }
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    private var currentMonth: Int { Calendar.current.component(.month, from: .now) }
    private var monthCells: [Date?] { DateSupport.monthCells(year: displayedYear, month: displayedMonthNumber) }
    private var dailyRecordCount: Int {
        monthCells.compactMap { $0 }.filter { store.record(for: DateSupport.key($0)) != nil }.count
    }
    @ViewBuilder
    private func dayButton(_ date: Date) -> some View {
        let key = DateSupport.key(date)
        let hasRecord = store.record(for: key) != nil
        let resolution = store.colorResolution(for: key)
        let future = Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: .now)
        Button {
            selectedDate = date
            editorDate = key
        } label: {
            ZStack {
                MultiColorTile(colorCodes: resolution.colorCodes, cornerRadius: 12)
                    .overlay {
                        if Calendar.current.isDate(date, inSameDayAs: selectedDate ?? .distantPast) {
                            RoundedRectangle(cornerRadius: 12).stroke(MosaPalette.navy, lineWidth: 3)
                        }
                    }
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resolution.colorCodes.isEmpty ? MosaPalette.text : Color.white)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .opacity(future ? 0.35 : 1)
        .accessibilityLabel(hasRecord ? "View and edit \(DateSupport.readable(key))" : "Record \(DateSupport.readable(key))")
        .accessibilityHint("Opens the daily record editor")
    }

    private func moveMonth(_ offset: Int) {
        guard let value = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = value
        selectedDate = nil
    }

    private func setDisplayed(year: Int, month: Int) {
        displayedMonth = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        selectedDate = nil
    }

    private func canMove(_ offset: Int) -> Bool {
        guard let profile = store.profile,
              let target = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return false }
        let targetYear = Calendar.current.component(.year, from: target)
        if targetYear < profile.startYear { return false }
        return target <= Date.now || Calendar.current.isDate(target, equalTo: .now, toGranularity: .month)
    }
}

struct AnnualView: View {
    @EnvironmentObject private var store: MosaStore
    let year: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Year reflection")
                Text("The shape of \(year)")
                    .font(.system(size: 40, weight: .medium, design: .serif))
                HStack(spacing: 10) {
                    stat(colored, "Colored")
                    stat(percentage, "Colored %")
                }
                NavigationLink(destination: CanvasView(initialYear: year)) {
                    VStack(alignment: .leading, spacing: 12) {
                        MosaicOverview(year: year, records: store.records, columns: 18)
                        Label("Choose a date in the monthly calendar", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MosaPalette.navy)
                    }
                    .mosaCard()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(year) monthly calendar")
                Text("Recurring threads").font(.title3.bold())
                if tagCounts.isEmpty {
                    Text("Tags will reveal the themes of your year.").foregroundStyle(MosaPalette.muted)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(tagCounts, id: \.0) { tag, count in
                            Text("\(tag) · \(count)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(MosaPalette.paperSecondary, in: Capsule())
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("\(year)")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
    }

    private var yearRecords: [LocalRecord] { store.records.filter { !$0.deleted && $0.recordDate.hasPrefix("\(year)-") } }
    private var colored: Int { DateSupport.days(in: year).filter { !store.colors(for: DateSupport.key($0)).isEmpty }.count }
    private var percentage: Int { Int((Double(colored) / Double(DateSupport.days(in: year).count) * 100).rounded()) }
    private var tagCounts: [(String, Int)] {
        Dictionary(grouping: yearRecords.flatMap(\.tagNames), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 28, weight: .medium, design: .serif))
            Text(label).font(.caption).foregroundStyle(MosaPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mosaCard()
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
