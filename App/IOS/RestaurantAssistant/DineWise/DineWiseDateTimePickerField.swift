import SwiftUI

private struct DineWiseInputSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DineWiseTheme.inputSurface(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func dineWiseInputSurface() -> some View {
        modifier(DineWiseInputSurface())
    }
}

struct DineWisePlaceholderField<Field: View>: View {
    let placeholder: String
    let accessibilityLabel: String
    let isEmpty: Bool
    let alignment: Alignment
    let topPadding: CGFloat
    let field: Field

    @Environment(\.colorScheme) private var colorScheme

    init(_ placeholder: String, accessibilityLabel: String? = nil,
         isEmpty: Bool, alignment: Alignment = .leading, topPadding: CGFloat = 0,
         @ViewBuilder field: () -> Field) {
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel ?? placeholder
        self.isEmpty = isEmpty
        self.alignment = alignment
        self.topPadding = topPadding
        self.field = field()
    }

    var body: some View {
        ZStack(alignment: alignment) {
            field
                .dineWiseInputSurface()
                .accessibilityLabel(accessibilityLabel)
            if isEmpty {
                Text(placeholder)
                    .foregroundStyle(DineWiseTheme.placeholder(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 12)
                    .padding(.top, topPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct DineWiseDateTimePickerField: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var accessibilityTitle: String? = nil
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    var maximumDate: Date? = nil
    var calendar: Calendar? = nil
    var timeZone: TimeZone? = nil
    var quickTimes = ["06:00", "08:00", "09:00", "10:00", "11:00", "12:00",
                      "14:00", "16:00", "17:00", "18:00", "20:00", "22:00"]
    var validationMessage: ((Date) -> String?)? = nil

    @State private var draft = Date.now
    @State private var isPresented = false
    @State private var validationError: String?
    @State private var showsExactTimePicker = false
    @State private var showsAllQuickTimes = false

    private var isTimeOnly: Bool {
        displayedComponents == .hourAndMinute
    }

    private var selectionCalendar: Calendar {
        var value = calendar ?? .current
        value.timeZone = timeZone ?? value.timeZone
        return value
    }

    private var formattedSelection: String {
        if isTimeOnly {
            return formattedTime(selection)
        }
        var format = Date.FormatStyle(date: .abbreviated,
            time: displayedComponents.contains(.hourAndMinute) ? .shortened : .omitted)
        format.calendar = selectionCalendar
        format.timeZone = selectionCalendar.timeZone
        return selection.formatted(format)
    }

    private var formattedDraftTime: String { formattedTime(draft) }

    private var visibleQuickTimes: [String] {
        guard isTimeOnly else { return [] }
        if showsAllQuickTimes || quickTimes.count <= 6 { return quickTimes }
        let featured = Array(quickTimes.prefix(6))
        return featured.contains(formattedDraftTime) ? featured : [formattedDraftTime] + featured
    }

    private var timePickerSheetHeight: CGFloat {
        if showsExactTimePicker && showsAllQuickTimes { return 560 }
        if showsExactTimePicker { return 500 }
        if showsAllQuickTimes { return 440 }
        return 340
    }

    var body: some View {
        Button(action: presentPicker) {
            fieldLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityTitle ?? title)，\(formattedSelection)")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        if !isTimeOnly || showsExactTimePicker {
                            Group {
                                if let maximumDate {
                                    DatePicker(title, selection: $draft, in: ...maximumDate,
                                               displayedComponents: displayedComponents)
                                } else {
                                    DatePicker(title, selection: $draft,
                                               displayedComponents: displayedComponents)
                                }
                            }
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.calendar, selectionCalendar)
                            .environment(\.timeZone, selectionCalendar.timeZone)
                            .environment(\.locale, displayedComponents == .hourAndMinute
                                ? Locale(identifier: "zh_CN") : .current)
                            .frame(maxWidth: .infinity,
                                   minHeight: isTimeOnly ? 220 : 420,
                                   maxHeight: isTimeOnly ? 240 : .infinity)
                            .onChange(of: draft) { _, _ in validationError = nil }
                        }
                    }
                    if let validationError {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(DineWiseTheme.danger(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    if isTimeOnly {
                        Text("当前时间：\(formattedDraftTime)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        Text("常用时刻 · 点按后立即应用")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                 count: visibleQuickTimes.count > 9 ? 4 : visibleQuickTimes.count > 4 ? 3 : 2),
                                  spacing: 8) {
                            ForEach(visibleQuickTimes, id: \.self) { time in
                                Button {
                                    let parts = time.split(separator: ":").compactMap { Int($0) }
                                    if parts.count == 2 {
                                        commit(selectionCalendar.date(bySettingHour: parts[0],
                                            minute: parts[1], second: 0, of: draft) ?? draft)
                                    }
                                } label: {
                                    let isSelected = formattedDraftTime == time
                                    Text(time)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(isSelected ? DineWiseTheme.accent(for: colorScheme) : .primary)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(isSelected
                                            ? DineWiseTheme.accent(for: colorScheme).opacity(0.16)
                                            : DineWiseTheme.inset, in: Capsule())
                                        .overlay {
                                            Capsule().stroke(isSelected
                                                ? DineWiseTheme.accent(for: colorScheme) : .clear,
                                                lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("立即应用该时间并关闭选择器")
                            }
                        }
                        .padding(.horizontal)
                        .accessibilityLabel("常用时间")
                        if quickTimes.count > 6 {
                            Button(showsAllQuickTimes ? "收起常用时刻" : "更多常用时刻") {
                                showsAllQuickTimes.toggle()
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(showsExactTimePicker ? "收起精确选择" : "精确调整时间") {
                            showsExactTimePicker.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 8)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            commit(draft)
                        }
                    }
                }
            }
            .presentationDetents(isTimeOnly ? [.height(timePickerSheetHeight)] : [.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var fieldLabel: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if isTimeOnly {
                HStack(spacing: 6) {
                    Text(formattedSelection)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DineWiseTheme.inputSurface(for: colorScheme), in: Capsule())
            } else {
                Text(formattedSelection).foregroundStyle(.secondary)
                Image(systemName: "calendar").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private func presentPicker() {
        draft = selection
        validationError = nil
        // 首次打开就展示系统滚轮，减少非预设时间的操作步骤。
        showsExactTimePicker = isTimeOnly
        showsAllQuickTimes = false
        isPresented = true
    }

    private func formattedTime(_ value: Date) -> String {
        let components = selectionCalendar.dateComponents([.hour, .minute], from: value)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func commit(_ value: Date) {
        if let message = validationMessage?(value) {
            validationError = message
            draft = value
            if !isPresented { isPresented = true }
            return
        }
        selection = value
        validationError = nil
        isPresented = false
    }
}
