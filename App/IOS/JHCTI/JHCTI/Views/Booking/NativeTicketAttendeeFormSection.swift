import SwiftUI

struct NativeTicketAttendeeFormSection: View {
    let fields: [[String: Any]]
    let quantity: Int
    @Binding var attendees: [[String: String]]
    let accountIdentityKeys: Set<String>
    let showsAccountIdentitySection: Bool
    let identityStatusText: String
    let identityProfileReady: Bool
    let identityProfile: [String: Any]?
    let identityLoading: Bool
    let identityError: String?
    let submitting: Bool
    let pendingBodyExists: Bool
    let hasIdentityField: Bool
    @Binding var identityConsent: Bool
    let onRetryIdentity: () -> Void
    let onOpenIdentityProfile: () -> Void
    let attendeeBinding: (Int, String) -> Binding<String>

    var body: some View {
        Group {
            if showsAccountIdentitySection {
                Section("账号实名资料") {
                    Text(identityStatusText)
                        .font(.footnote).foregroundStyle(.secondary)
                    if identityProfileReady {
                        Text("实名姓名：\(identityProfile?["MaskedRealName"] as? String ?? "待核对")")
                            .font(.footnote).privacySensitive()
                        Text("身份证号：\(identityProfile?["MaskedIdentityNumber"] as? String ?? "待核对")")
                            .font(.footnote).privacySensitive()
                    }
                    if identityLoading { ProgressView("正在核对账号实名资料…") }
                    if let identityError { Text(identityError).font(.footnote).foregroundStyle(.red) }
                    Button("重新核对实名状态", action: onRetryIdentity).disabled(submitting || identityLoading)
                    Button("登记或查看实名资料", action: onOpenIdentityProfile).disabled(submitting)
                }
            }
            if !fields.isEmpty {
                ForEach(0..<quantity, id: \.self) { attendeeIndex in
                    Section("购票人 \(attendeeIndex + 1)") {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            let key = field["Key"] as? String ?? ""
                            let label = field["Label"] as? String ?? key
                            let isRequired = field["Required"] as? Bool == true
                            let isAccountIdentity = attendeeIndex == 0 && accountIdentityKeys.contains(key.lowercased())
                            let identityFieldKey = field["Type"] as? String == "IdentityNumber" ? "MaskedIdentityNumber" : "MaskedRealName"
                            let identityText = identityProfileReady
                                ? identityProfile?[identityFieldKey] as? String ?? "账号资料"
                                : "账号实名资料待核对"
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(isRequired ? "\(label) *" : label)
                                    if isAccountIdentity {
                                        Text(identityText).foregroundStyle(.secondary).privacySensitive()
                                    } else {
                                        TextField(label, text: attendeeBinding(attendeeIndex, key))
                                            .keyboardType(nativeActivityKeyboard(field["Type"] as? String ?? "Text"))
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }
                                }
                                if field["Type"] as? String == "Text" && !isAccountIdentity {
                                    let value = attendees.indices.contains(attendeeIndex) ? attendees[attendeeIndex][key] ?? "" : ""
                                    let count = value.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
                                    Text("\(count) / 200").font(.caption)
                                        .foregroundStyle(count > 200 ? Color.red : Brand.muted)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            if hasIdentityField {
                Section("实名信息授权") {
                    Toggle("我同意为本次购票及入园核验提交所需身份证信息", isOn: $identityConsent)
                        .disabled(pendingBodyExists || submitting)
                    Text("身份证信息仅用于本次门票实名购票与入园核验。资料由服务端按安全规则处理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
