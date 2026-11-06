import SwiftUI

struct DineWiseGuestHomeView: View {
    private let ink = Color(red: 0.11, green: 0.12, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("云巷小馆 · 今日经营").font(.headline)
                    Text("未登录预览 · 全部为构造数据")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("演示").font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.13), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("今天要处理").font(.headline)
                    Spacer()
                    Text("3 件").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                .padding(.bottom, 8)
                task("核对", "采购进货单的单位待确认", "资料核对后才能进入报告", .orange)
                task("建议", "周末备菜方案待老板决定", "确认后再分派给岗位", .yellow)
                task("执行", "门店运营任务等待回执", "完成情况由负责人提交", .green)
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(ink, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("示例关键数字").font(.headline)
                    Spacer()
                    Text("构造数据").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    metric("¥12,860", "营业额")
                    metric("56 桌", "桌数")
                    metric("¥230", "桌均")
                }
                Divider()
                HStack(spacing: 20) {
                    Label("已核对 2 项", systemImage: "checkmark.circle")
                    Label("待处理 3 件", systemImage: "clock")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 12) {
                Text("岗位完成情况").font(.headline)
                HStack {
                    progress("厨师长", "2/3")
                    progress("采购", "1/2")
                    progress("运营", "3/3")
                    progress("店长", "1/2")
                }
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            Text("公开价格、天气和附近活动将在来源、地点及有效期核实后接入。")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline.bold()).minimumScaleFactor(0.75).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func task(_ label: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(label).font(.caption.bold()).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Color.white.opacity(0.12).frame(height: 1) }
    }

    private func progress(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
