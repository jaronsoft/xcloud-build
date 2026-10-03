import SwiftUI

struct MosaEmotionDefinition: Identifiable {
    let code: EmotionCode
    let name: String
    let childLabel: String
    let hex: String
    let iconName: String

    var id: EmotionCode { code }
}

enum MosaPalette {
    static let canvas = Color(light: 0xFBF8F2, dark: 0x151719)
    static let paper = Color(light: 0xFFFFFF, dark: 0x202327)
    static let paperSecondary = Color(light: 0xF1ECE3, dark: 0x2A2E33)
    static let navy = Color(light: 0x2F4B7C, dark: 0xAFC8F2)
    static let text = Color(light: 0x2C3038, dark: 0xF2EFE9)
    static let muted = Color(light: 0x687280, dark: 0xA9B0BA)
    static let coral = Color(hex: 0xD9948A)
    static let gold = Color(hex: 0xE2C466)
    static let blue = Color(hex: 0x7FA7C6)
    static let green = Color(hex: 0x87B78F)
    static let slate = Color(hex: 0x687280)
    static let dayHex = ["#E2C466", "#E5A15B", "#D46F65", "#7FA7C6", "#9A83B8", "#87B78F", "#D99AB4", "#9A8068"]
    static let dayColors = dayHex.compactMap(Color.init(mosaHex:))

    static let emotions: [MosaEmotionDefinition] = [
        .init(code: .joy, name: "Joy", childLabel: "I feel happy today.", hex: dayHex[0], iconName: "EmotionJoy"),
        .init(code: .excitement, name: "Excitement", childLabel: "I am looking forward to it.", hex: dayHex[1], iconName: "EmotionExcitement"),
        .init(code: .anger, name: "Anger", childLabel: "Something made me angry.", hex: dayHex[2], iconName: "EmotionAnger"),
        .init(code: .sadness, name: "Sadness", childLabel: "I feel a little sad.", hex: dayHex[3], iconName: "EmotionSadness"),
        .init(code: .fear, name: "Fear", childLabel: "I am worried about what may happen.", hex: dayHex[4], iconName: "EmotionFear"),
        .init(code: .calm, name: "Calm", childLabel: "I feel quiet and safe.", hex: dayHex[5], iconName: "EmotionCalm"),
        .init(code: .love, name: "Love", childLabel: "I feel close and cared for.", hex: dayHex[6], iconName: "EmotionLove"),
        .init(code: .disgust, name: "Disgust", childLabel: "I want to move away from this.", hex: dayHex[7], iconName: "EmotionDisgust")
    ]

    static func emotion(forHex hex: String) -> MosaEmotionDefinition? {
        emotions.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    init?(mosaHex value: String) {
        let normalized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt32(normalized, radix: 16), normalized.count == 6 else { return nil }
        self.init(hex: number)
    }
}

struct MosaCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(MosaPalette.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MosaPalette.muted.opacity(0.14))
            }
    }
}

extension View {
    func mosaCard() -> some View { modifier(MosaCardModifier()) }

    func mosaPage() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MosaPalette.canvas.ignoresSafeArea())
            .foregroundStyle(MosaPalette.text)
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.8)
            .foregroundStyle(MosaPalette.navy)
    }
}

struct MosaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white)
            .background(MosaPalette.navy.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MosaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(MosaPalette.navy)
            .background(MosaPalette.paperSecondary.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
