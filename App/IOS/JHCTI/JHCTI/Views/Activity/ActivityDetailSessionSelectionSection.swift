import SwiftUI

struct ActivityDetailSessionSelectionSection: View {
    let sessions: [[String: Any]]
    let availabilityRows: [[String: Any]]
    let selectedSessionID: String
    let isBusy: Bool
    let now: Date
    let isBookable: ([String: Any]?, Date) -> Bool
    let unavailableText: ([String: Any]?, Date) -> String
    let dateRange: (Any?, Any?) -> String
    let onSelect: (String, Int?) -> Void

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选择活动场次")
                    .font(.system(size: NativeTypography.size(14), weight: .semibold))
                    .foregroundStyle(Brand.primary)
                Spacer()
                Text("多场活动 · 共 \(sessions.count) 场")
                    .font(.system(size: NativeTypography.size(10), weight: .medium))
                    .foregroundStyle(Brand.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Brand.background, in: Capsule())
            }
            Text("默认选择第一场，可点击其他场次切换。")
                .font(.system(size: NativeTypography.size(10)))
                .foregroundStyle(Brand.muted)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(sessions.indices, id: \.self) { index in
                    let session = sessions[index]
                    let sessionID = session["Id"] as? String ?? ""
                    let selected = selectedSessionID == sessionID
                    let availabilityRow = availabilityRows.first { $0["Id"] as? String == sessionID }
                    let seats = availabilityRow?["RemainingCapacity"] as? Int
                    let bookable = isBookable(availabilityRow, now)
                    Button {
                        onSelect(sessionID, seats)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 4) {
                                Text(session["Name"] as? String ?? "活动场次")
                                    .font(.system(size: NativeTypography.size(11), weight: .semibold))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(dateRange(session["StartTime"], session["EndTime"]))
                                .font(.system(size: NativeTypography.size(9)))
                                .foregroundStyle(Brand.muted)
                                .lineLimit(2)
                            Text(bookable
                                 ? (selected ? "已选择 · 剩余名额 \(seats ?? 0)" : "剩余名额 \(seats ?? 0)")
                                 : unavailableText(availabilityRow, now))
                                .font(.system(size: NativeTypography.size(9), weight: selected ? .medium : .regular))
                                .foregroundStyle(selected ? Brand.primary : Brand.muted)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .background(selected ? Color(red: 0.91, green: 0.97, blue: 0.96) : Brand.background,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Brand.primary.opacity(0.55) : Brand.border.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || !bookable)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
