import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sloganIndex = 0

    private let slogans = [
        "A life in pieces, still whole.",
        "Gather the colors of your days.",
        "Your days become a life you can see."
    ]

    var body: some View {
        VStack(spacing: 24) {
            AnimatedMosaicMark()
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Eyebrow(text: "A life, seen gently")
                Text("MOSA")
                    .font(.system(size: 58, weight: .medium, design: .serif))
                    .tracking(2)
                Text(slogans[sloganIndex])
                    .id(sloganIndex)
                    .font(.subheadline)
                    .foregroundStyle(MosaPalette.muted)
                    .multilineTextAlignment(.center)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 7)),
                        removal: .opacity.combined(with: .offset(y: -7))
                    ))
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { CompanyFooter().padding(.bottom, 22) }
        .mosaPage()
        .task {
            guard !reduceMotion else { return }
            for index in slogans.indices.dropFirst() {
                try? await Task.sleep(for: .milliseconds(760))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.34)) {
                    sloganIndex = index
                }
            }
        }
    }
}

private struct MosaicTile: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let color: Color
}

struct AnimatedMosaicMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var assembled = false
    @State private var breathing = false

    private let tiles = [
        MosaicTile(id: 0, x: -56, y: -53, width: 42, height: 49, rotation: -13, color: MosaPalette.coral),
        MosaicTile(id: 1, x: -15, y: -64, width: 34, height: 38, rotation: -8, color: MosaPalette.green),
        MosaicTile(id: 2, x: 20, y: -68, width: 42, height: 42, rotation: 2, color: MosaPalette.gold),
        MosaicTile(id: 3, x: 58, y: -55, width: 34, height: 42, rotation: 14, color: MosaPalette.coral),
        MosaicTile(id: 4, x: -62, y: -6, width: 45, height: 43, rotation: -2, color: MosaPalette.blue),
        MosaicTile(id: 5, x: -24, y: -23, width: 38, height: 58, rotation: -17, color: MosaPalette.navy),
        MosaicTile(id: 6, x: 23, y: -22, width: 39, height: 58, rotation: 17, color: MosaPalette.blue),
        MosaicTile(id: 7, x: 62, y: -8, width: 42, height: 45, rotation: 3, color: MosaPalette.green),
        MosaicTile(id: 8, x: -65, y: 36, width: 38, height: 36, rotation: -5, color: MosaPalette.green),
        MosaicTile(id: 9, x: -25, y: 30, width: 34, height: 48, rotation: -1, color: MosaPalette.slate),
        MosaicTile(id: 10, x: 24, y: 30, width: 34, height: 48, rotation: 1, color: MosaPalette.navy),
        MosaicTile(id: 11, x: 64, y: 34, width: 37, height: 42, rotation: 5, color: MosaPalette.gold),
        MosaicTile(id: 12, x: -47, y: 70, width: 66, height: 39, rotation: 0, color: MosaPalette.navy),
        MosaicTile(id: 13, x: 0, y: 72, width: 30, height: 36, rotation: 0, color: MosaPalette.blue),
        MosaicTile(id: 14, x: 49, y: 70, width: 65, height: 39, rotation: 0, color: MosaPalette.coral)
    ]

    var body: some View {
        ZStack {
            ForEach(tiles) { tile in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tile.color)
                    .frame(width: tile.width, height: tile.height)
                    .rotationEffect(.degrees(assembled ? tile.rotation : tile.rotation * 2.2))
                    .offset(
                        x: tile.x + (assembled ? 0 : tile.x * 0.62),
                        y: tile.y + (assembled ? 0 : tile.y * 0.62)
                    )
                    .scaleEffect(assembled ? 1 : 0.38)
                    .opacity(assembled ? 1 : 0)
                    .animation(
                        .spring(response: 0.72, dampingFraction: 0.72)
                            .delay(Double(tile.id) * 0.035),
                        value: assembled
                    )
            }
        }
        .frame(width: 190, height: 190)
        .scaleEffect(breathing ? 1.018 : 0.992)
        .rotationEffect(.degrees(breathing ? 0.45 : -0.35))
        .onAppear {
            assembled = true
            guard !reduceMotion else {
                breathing = false
                return
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(1.1)) {
                breathing = true
            }
        }
    }
}
