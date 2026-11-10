import SwiftUI

struct DineWiseLaunchAnimationView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Color(red: 21 / 255, green: 92 / 255, blue: 57 / 255)
                .ignoresSafeArea()
            ZStack {
                DineWiseWhiteLogo(progress: reduceMotion ? 1 : progress)
                    .fill(Color(red: 248 / 255, green: 247 / 255, blue: 243 / 255))
                Circle()
                    .fill(Color(red: 248 / 255, green: 247 / 255, blue: 243 / 255))
                    .frame(width: 39, height: 39)
                    .position(x: 175, y: 109.4)
                DineWiseGoldArrow()
                    .fill(Color(red: 217 / 255, green: 163 / 255, blue: 74 / 255))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: 350 * min(1, max(0,
                            ((reduceMotion ? 1 : progress) - 0.48) / 0.52)))
                    }
            }
            .frame(width: 350, height: 350)
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("餐有数").font(.system(size: 30, weight: .bold))
                Text("DineWise").font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(.white)
            .offset(y: 260)
        }
        .task {
            if reduceMotion {
                progress = 1
                try? await Task.sleep(for: .milliseconds(180))
                onFinished()
            } else {
                withAnimation(.easeOut(duration: 0.9), completionCriteria: .removed) {
                    progress = 1
                } completion: {
                    onFinished()
                }
            }
        }
    }
}

private struct DineWiseWhiteLogo: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 1024
        var path = Path()
        path.addArc(center: CGPoint(x: 512, y: 657), radius: 314,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        let outline = path.strokedPath(StrokeStyle(lineWidth: 46, lineCap: .round))
        path = outline
        var plate = Path()
        plate.move(to: CGPoint(x: 160, y: 720))
        plate.addLine(to: CGPoint(x: 864, y: 720))
        plate.addCurve(to: CGPoint(x: 512, y: 839),
                       control1: CGPoint(x: 831, y: 793), control2: CGPoint(x: 729, y: 839))
        plate.addCurve(to: CGPoint(x: 160, y: 720),
                       control1: CGPoint(x: 295, y: 839), control2: CGPoint(x: 193, y: 793))
        path.addPath(plate)
        for (index, top) in [578.0, 536.0, 494.0].enumerated() {
            let factor = min(1, max(0, (progress - CGFloat(index) * 0.16) / 0.58))
            let height = (689 - top) * factor
            path.addRoundedRect(in: CGRect(x: CGFloat(355 + index * 106), y: 689 - height,
                                           width: 103, height: height), cornerSize: CGSize(width: 18, height: 18))
        }
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

private struct DineWiseGoldArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var arrow = Path()
        arrow.move(to: CGPoint(x: 333, y: 522))
        arrow.addCurve(to: CGPoint(x: 614, y: 370),
                       control1: CGPoint(x: 425, y: 493), control2: CGPoint(x: 523, y: 444))
        arrow.addLine(to: CGPoint(x: 605, y: 348))
        arrow.addLine(to: CGPoint(x: 680, y: 334))
        arrow.addLine(to: CGPoint(x: 666, y: 410))
        arrow.addLine(to: CGPoint(x: 645, y: 395))
        arrow.addCurve(to: CGPoint(x: 333, y: 522),
                       control1: CGPoint(x: 553, y: 471), control2: CGPoint(x: 447, y: 509))
        arrow.closeSubpath()
        let scale = rect.width / 1024
        return arrow.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
