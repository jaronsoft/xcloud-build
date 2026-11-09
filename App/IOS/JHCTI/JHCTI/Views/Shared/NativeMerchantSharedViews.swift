import SwiftUI

struct StatusView: View {
    let loading: Bool
    let error: String?
    let retry: () -> Void

    var body: some View {
        if loading { ProgressView().tint(Brand.primary) }
        if let error {
            VStack(spacing: 8) {
                Text(error).foregroundStyle(.red)
                Button("重试", action: retry)
            }
        }
    }
}

extension View {
    func merchantCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
