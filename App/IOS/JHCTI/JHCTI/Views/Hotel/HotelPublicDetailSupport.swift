import SwiftUI

func dialableHotelPhoneURL(_ value: String) -> URL? {
    let normalized = value.replacingOccurrences(of: "[\\s()（）-]", with: "", options: .regularExpression)
    guard normalized.range(of: "^\\+?[0-9]{5,20}$", options: .regularExpression) != nil else { return nil }
    return URL(string: "tel:\(normalized)")
}

enum HotelBusinessDate {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    static func offset(_ days: Int, from date: Date? = nil) -> Date {
        let value = calendar
        let start = value.startOfDay(for: date ?? Date())
        return value.date(byAdding: .day, value: days, to: start) ?? start
    }
}

struct HotelDateField: View {
    let title: String
    @Binding var selection: Date
    let range: ClosedRange<Date>
    @State private var isPickerPresented = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = HotelBusinessDate.timeZone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: selection)
    }

    var body: some View {
        Button { isPickerPresented = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(Brand.ink)
                    Spacer(minLength: 8)
                    Text(formattedDate).fontWeight(.medium).foregroundStyle(Brand.primary)
                        .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                    Image(systemName: "calendar").foregroundStyle(Brand.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(Brand.muted)
                    HStack {
                        Text(formattedDate).fontWeight(.medium).foregroundStyle(Brand.primary)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(Brand.muted)
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                DatePicker(title, selection: $selection, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.calendar, HotelBusinessDate.calendar)
                    .environment(\.timeZone, HotelBusinessDate.timeZone)
                    .padding()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isPickerPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
