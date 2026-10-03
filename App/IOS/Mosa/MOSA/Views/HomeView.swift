import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var recentPage = 0
    private let today = DateSupport.key(.now)
    private let year = Calendar.current.component(.year, from: .now)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Eyebrow(text: "Today in your life")
                Text(store.profile?.displayName.isEmpty == false ? "Hello, \(store.profile!.displayName)." : "A quiet moment for today.")
                    .font(.system(size: 40, weight: .medium, design: .serif))
                Text(DateSupport.readable(today)).foregroundStyle(MosaPalette.muted)

                NavigationLink(destination: RecordEditorView(date: today)) {
                    Text("Record today")
                }
                .buttonStyle(MosaPrimaryButtonStyle())

                if let deleted = store.lastDeletedDate {
                    HStack {
                        Text("\(deleted) was removed.").font(.subheadline)
                        Spacer()
                        Button("Undo") { Task { await store.restoreRecord(date: deleted) } }
                    }
                    .mosaCard()
                }

                if let notice = store.notice {
                    HStack(alignment: .top) {
                        Text(notice).font(.subheadline)
                        Spacer()
                        Button("Dismiss") { store.notice = nil }
                    }
                    .mosaCard()
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Eyebrow(text: "\(year)")
                            Text("Your canvas so far").font(.title3.weight(.semibold))
                        }
                        Spacer()
                        NavigationLink(destination: CanvasView()) {
                            Text("Choose date")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    NavigationLink(destination: CanvasView()) {
                        MosaicOverview(year: year, records: store.records)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(year) monthly calendar")
                    HStack(spacing: 16) { Label("Colored", systemImage: "square.fill").foregroundStyle(MosaPalette.navy); Label("White canvas", systemImage: "square").foregroundStyle(MosaPalette.muted) }
                    .font(.caption)
                }
                .mosaCard()

                NavigationLink(destination: BackfillView()) {
                    VStack(alignment: .leading, spacing: 6) { Eyebrow(text: "Your earlier chapters"); Text("Color your past").font(.title3.bold()); Text("Mark broad life stages without filling unrecorded days.").font(.subheadline).foregroundStyle(MosaPalette.muted) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mosaCard()
                }
                .buttonStyle(.plain)

                HStack {
                    Text("Recent days").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(store.visibleRecords.count) recorded").font(.subheadline).foregroundStyle(MosaPalette.muted)
                }

                if store.visibleRecords.isEmpty {
                    Text("Your first day is waiting.")
                        .foregroundStyle(MosaPalette.muted)
                        .frame(maxWidth: .infinity)
                        .mosaCard()
                } else {
                    ForEach(recentRecords) { record in
                        NavigationLink(destination: RecordEditorView(date: record.recordDate)) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(DateSupport.readable(record.recordDate))
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(record.note.isEmpty ? (record.colorCodes.isEmpty ? "A note on the canvas" : "A colored day") : record.note)
                                        .font(.subheadline)
                                        .foregroundStyle(MosaPalette.muted)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                SyncBadge(state: record.syncState)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(MosaPalette.text)
                            .mosaCard()
                        }
                        .buttonStyle(.plain)
                    }
                    if store.visibleRecords.count > 4 {
                        Button(recentPage + 1 < recentPageCount ? "Show older recorded days" : "Back to newest days") {
                            recentPage = (recentPage + 1) % recentPageCount
                        }
                        .buttonStyle(MosaSecondaryButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("MOSA")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
    }

    private var recentPageCount: Int { max(1, (store.visibleRecords.count + 3) / 4) }
    private var recentRecords: ArraySlice<LocalRecord> {
        let safePage = min(recentPage, recentPageCount - 1)
        let start = safePage * 4
        return store.visibleRecords.dropFirst(start).prefix(4)
    }
}
