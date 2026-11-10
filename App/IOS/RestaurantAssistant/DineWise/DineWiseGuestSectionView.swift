import SwiftUI

struct DineWiseGuestSectionView: View {
    let section: String
    let onLogin: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let ink = Color(red: 0.11, green: 0.12, blue: 0.16)
    private var green: Color { DineWiseTheme.accent(for: colorScheme) }
    private var actionGreen: Color { DineWiseTheme.action(for: colorScheme) }
    private var gold: Color { DineWiseTheme.gold(for: colorScheme) }
    private var surfaceGold: Color { DineWiseTheme.surfaceGold(for: colorScheme) }
    private var heroPrimary: Color {
        .white
    }
    private var heroSecondary: Color {
        .white.opacity(0.9)
    }

    private var title: String {
        switch section {
        case "suggestions": "建议"
        case "report": "报告"
        default: "资料"
        }
    }

    private var subtitle: String {
        switch section {
        case "suggestions": "先说依据，再让老板决定"
        case "report": "每个数字都能回到原始资料"
        default: "资料核对后才进入经营报告"
        }
    }

    private var heroTitle: String {
        switch section {
        case "suggestions": "从问题到行动"
        case "report": "经营数字有来源"
        default: "从提交到核对"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(surfaceGold)
                Text("云巷小馆 · 演示门店").font(.caption.bold())
                Spacer()
                Text("构造数据").font(.caption2.weight(.semibold))
            }
            .padding(12)
            .background(DineWiseTheme.inset,
                        in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(subtitle).font(.subheadline.bold()).foregroundStyle(DineWiseTheme.gold(for: .dark))
                Text(heroTitle).font(.system(size: 31, weight: .heavy, design: .rounded))
                Text("以下仅演示餐有数的工作方式，不代表真实门店。")
                    .font(.footnote).foregroundStyle(heroSecondary)
            }
            .foregroundStyle(heroPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(LinearGradient(colors: [ink, Color(red: 0.09, green: 0.26, blue: 0.23)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22))

            if section == "suggestions" { suggestionsContent }
            else if section == "report" { reportContent }
            else { materialsContent }

            Button(action: onLogin) {
                Text("登录后查看自己的\(title)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(actionGreen, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private var suggestionsContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("周末备菜方案").font(.headline)
                Spacer()
                Text("待老板决定").font(.caption.bold()).foregroundStyle(surfaceGold)
            }
            Text("建议厨师长与采购核对备货量，再由老板确认是否执行。")
                .font(.subheadline).foregroundStyle(.secondary)
            evidence("为什么", "演示订位与上周备菜记录已核对；食材库存仍需采购补充。")
            evidence("怎么做", "先确认订位，再调整备菜清单；执行人提交结果后复盘。")
        }
        .guestCard()
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("本周经营阶段摘要").font(.headline)
                Spacer()
                Text("示例数据").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                metric("¥78,400", "已确认营业额小计")
                metric("5 / 7 天", "演示资料覆盖")
            }
            Text("还有 2 天资料待核对，因此这里只展示已确认部分，不作为完整周报。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .guestCard()
    }

    private var materialsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("资料进入报告的路径").font(.headline)
            ForEach(Array(["岗位提交原始文字或附件", "核对字段、单位与营业日期",
                           "老板查看确认后的单店报告"].enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(green)
                        .frame(width: 28, height: 28)
                        .background(green.opacity(0.11), in: Circle())
                    Text(item).font(.subheadline)
                }
            }
            Divider()
            Text("待核对资料 2 份").font(.subheadline.bold())
            Text("采购进货单与经营截图需先核对，未确认内容不会进入报告。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .guestCard()
    }

    private func evidence(_ label: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline.bold()).foregroundStyle(green)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .overlay(alignment: .top) { Color.black.opacity(0.06).frame(height: 1) }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(green).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
    }
}

private extension View {
    func guestCard() -> some View {
        self.padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DineWiseTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}
