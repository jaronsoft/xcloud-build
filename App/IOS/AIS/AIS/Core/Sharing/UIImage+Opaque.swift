import UIKit

extension UIImage {
    /// 分享海报没有透明内容，移除 Alpha 通道可避免系统保存时重复解码并降低内存占用。
    func aisOpaqueImage(
        backgroundColor: UIColor = .white
    ) -> UIImage {
        guard let alphaInfo = cgImage?.alphaInfo else { return self }
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return self
        default:
            break
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { context in
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
