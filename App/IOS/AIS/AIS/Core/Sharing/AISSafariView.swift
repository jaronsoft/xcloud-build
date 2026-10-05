import SafariServices
import SwiftUI

struct AISSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(AISTheme.accent)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}
