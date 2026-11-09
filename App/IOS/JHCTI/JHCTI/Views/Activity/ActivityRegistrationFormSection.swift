import SwiftUI

struct ActivityRegistrationFormSection: View {
    let fields: [[String: Any]]
    let quantity: Int
    let remainingQuota: Int
    let configuredLimit: Int
    let maxQuantity: Int
    let remainingSeats: Int
    let selectedSessionBookable: Bool
    let requiresSession: Bool
    let hasSelectedSession: Bool
    @Binding var participantAnswers: [[String: String]]
    @Binding var identityConsent: Bool
    let submitError: String?
    let isBusy: Bool
    let onQuantityChange: (Int) -> Void
    let onAnswerChange: (String, String, Int, Int?) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("报名人数").font(.system(size: NativeTypography.size(12), weight: .semibold)).foregroundStyle(Brand.ink)
                Spacer()
                Text("本人剩余名额 \(remainingQuota) 人 / 活动上限 \(configuredLimit) 人")
                    .font(.system(size: NativeTypography.size(10))).foregroundStyle(Brand.muted)
                Button { onQuantityChange(max(1, quantity - 1)) } label: {
                    Image(systemName: "minus").font(.system(size: NativeTypography.size(11), weight: .semibold))
                        .frame(width: 34, height: 34).foregroundStyle(Brand.muted)
                        .overlay(Circle().stroke(Brand.border, lineWidth: 1))
                }.disabled(quantity <= 1)
                Text("\(quantity)").font(.system(size: NativeTypography.size(13), weight: .semibold)).frame(width: 24)
                Button { onQuantityChange(min(quantity + 1, maxQuantity)) } label: {
                    Image(systemName: "plus").font(.system(size: NativeTypography.size(11), weight: .semibold))
                        .frame(width: 34, height: 34).foregroundStyle(Brand.primary)
                        .overlay(Circle().stroke(Brand.border, lineWidth: 1))
                }.disabled(quantity >= maxQuantity)
            }

            Text("参与者信息").font(.system(size: NativeTypography.size(14), weight: .semibold)).foregroundStyle(Brand.primary)
            ForEach(0..<quantity, id: \.self) { participantIndex in
                if quantity > 1 {
                    Text("参与者 \(participantIndex + 1)").font(.system(size: NativeTypography.size(11), weight: .medium))
                        .foregroundStyle(Brand.muted)
                }
                ForEach(fields.indices, id: \.self) { index in
                    let field = fields[index]
                    let key = field["Key"] as? String ?? ""
                    let label = field["Label"] as? String ?? "报名信息"
                    let required = field["Required"] as? Bool == true
                    let type = field["Type"] as? String ?? "Text"
                    let fieldLabel = label + (required ? " *" : "（选填）")
                    if type == "Select" {
                        Picker(fieldLabel, selection: Binding(get: { participantAnswers[participantIndex][key] ?? "" },
                            set: { onAnswerChange($0, key, participantIndex, nil) })) {
                            Text("请选择\(label)").tag("")
                            ForEach(field["Options"] as? [String] ?? [], id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } else {
                        NativeActivityTextInput(label: fieldLabel, type: type, text: Binding(
                            get: { participantAnswers[participantIndex][key] ?? "" },
                            set: { onAnswerChange($0, key, participantIndex, nativeActivitySignupMaxLength(type)) }))
                    }
                }
            }

            if fields.contains(where: { $0["Type"] as? String == "IdentityNumber" }) {
                Toggle("我已阅读并同意为本次活动报名及签到提供身份证信息", isOn: $identityConsent)
                    .font(.system(size: NativeTypography.size(12))).tint(Brand.primary)
            }
            if let submitError { Text(submitError).font(.system(size: NativeTypography.size(12))).foregroundStyle(.red) }
            Button(isBusy ? "提交中…" : "提交报名", action: onSubmit)
                .disabled(isBusy || quantity > maxQuantity || remainingSeats < 1 || !selectedSessionBookable
                    || (requiresSession && !hasSelectedSession))
                .frame(maxWidth: .infinity).frame(height: 40)
                .foregroundStyle(.white).background(Brand.primary, in: Capsule())
        }
    }
}
