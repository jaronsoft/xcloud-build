import SwiftUI
import UIKit

func nativeActivityTextLength(_ value: String) -> Int {
    value.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
}

func nativeActivityTextLengthError(_ fields: [[String: Any]], participants: [[String: String]]) -> String? {
    for (index, answers) in participants.enumerated() {
        for field in fields where ["Text", "LongText"].contains(field["Type"] as? String ?? "") {
            let key = field["Key"] as? String ?? ""
            if nativeActivityTextLength(answers[key] ?? "") > 500 {
                return "参与者\(index + 1)的“\(field["Label"] as? String ?? key)”不能超过500个字符。"
            }
        }
    }
    return nil
}

func nativeActivityKeyboard(_ type: String) -> UIKeyboardType {
    switch type {
    case "Number": .decimalPad
    case "Phone": .phonePad
    case "IdentityNumber": .asciiCapable
    default: .default
    }
}

struct NativeActivityTextInput: View {
    let label: String
    let type: String
    @Binding var text: String

    private var isText: Bool { type == "Text" || type == "LongText" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $text, axis: type == "LongText" ? .vertical : .horizontal)
                .lineLimit(type == "LongText" ? 3...6 : 1...1)
                .keyboardType(nativeActivityKeyboard(type))
                .textInputAutocapitalization(isText ? .sentences : .never)
                .autocorrectionDisabled(!isText)
                .textFieldStyle(.roundedBorder)
            if isText {
                let count = nativeActivityTextLength(text)
                Text("\(count) / 500").font(.caption)
                    .foregroundStyle(count > 500 ? Color.red : Brand.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
