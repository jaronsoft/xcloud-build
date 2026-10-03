import SwiftUI

struct MultiColorTile: View {
    let colorCodes: [String]
    var cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            if colorCodes.isEmpty {
                RoundedRectangle(cornerRadius: cornerRadius).fill(MosaPalette.paperSecondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(colorCodes.prefix(3).enumerated()), id: \.offset) { _, code in
                        (Color(mosaHex: code) ?? MosaPalette.navy)
                            .frame(width: proxy.size.width / CGFloat(min(colorCodes.count, 3)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

struct SyncBadge: View {
    let state: SyncState

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state == .syncFailed ? Color.orange : MosaPalette.muted)
    }

    private var label: String {
        switch state {
        case .localOnly: "On device"
        case .syncing: "Syncing"
        case .syncFailed: "Cloud pending"
        case .synced: "Cloud saved"
        }
    }

    private var icon: String {
        switch state {
        case .localOnly: "iphone"
        case .syncing: "arrow.triangle.2.circlepath"
        case .syncFailed: "exclamationmark.icloud"
        case .synced: "checkmark.icloud"
        }
    }
}

struct MosaicOverview: View {
    let year: Int
    let records: [LocalRecord]
    var stages: [LocalLifeStage] = []
    var columns = 22
    var showsStageBackgrounds = false

    var body: some View {
        let recordIndex = records.filter { !$0.deleted }.reduce(into: [String: LocalRecord]()) {
            $0[$1.recordDate] = $1
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: columns), spacing: 3) {
            ForEach(DateSupport.days(in: year), id: \.self) { date in
                let key = DateSupport.key(date)
                let record = recordIndex[key]
                MultiColorTile(colorCodes: CanvasResolver.colors(
                    date: key,
                    record: record,
                    stages: stages,
                    includeStageBackgrounds: showsStageBackgrounds
                ))
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel(accessibilityText(record, date: key))
            }
        }
    }

    private func accessibilityText(_ record: LocalRecord?, date: String) -> String {
        let count = CanvasResolver.colors(
            date: date,
            record: record,
            stages: stages,
            includeStageBackgrounds: showsStageBackgrounds
        ).count
        return count == 0 ? "\(date), white canvas" : "\(date), \(count) colors"
    }
}
