import SwiftUI
import UIKit

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder
    let onLoadResult: ((Bool) -> Void)?
    @State private var image: UIImage?

    init(url: URL?, onLoadResult: ((Bool) -> Void)? = nil,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.onLoadResult = onLoadResult
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { placeholder() }
        }
        .task(id: url) {
            onLoadResult?(false)
            image = nil
            let loaded = await NativePublicCache.shared.thumbnail(for: url, width: 400)
            guard !Task.isCancelled else { return }
            image = loaded
            onLoadResult?(loaded != nil)
        }
    }
}
