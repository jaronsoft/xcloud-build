import Foundation

// 与移动网页的公开 COS 图片规则保持一致；签名地址不改写，原地址始终保留为失败回退。
func nativeImageCandidates(_ source: String, width: Int? = nil) -> [String] {
    guard !source.isEmpty else { return [] }
    guard let width else { return [source] }
    let thumbnail = nativeImageThumbnail(source, width: width)
    return thumbnail == source ? [source] : [thumbnail, source]
}

func nativeImageThumbnail(_ source: String, width: Int) -> String {
    func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
    func decode(_ value: String) -> String { value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value }
    guard let pattern = try? NSRegularExpression(pattern: "^https://([^/?#:]+)(?::[0-9]+)?(?:[/?#]|$)", options: .caseInsensitive),
          let match = pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          let hostRange = Range(match.range(at: 1), in: source) else { return source }
    let host = String(source[hostRange]).lowercased()
    let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
    guard normalizedHost == "cdn.jaronsoft.com" || matches(normalizedHost, "^(?:[^.]+\\.)?cos\\.[^.]+\\.myqcloud\\.com(?:\\.cn)?$") else { return source }
    let split = source.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let fragment = split.count == 2 ? "#" + split[1] : ""
    let raw = String(split[0])
    let query = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let base = String(query[0])
    var parts = query.count == 2 ? query[1].components(separatedBy: "&") : []
    let signature = "^(?:q-sign-algorithm|q-ak|q-sign-time|q-key-time|q-header-list|q-url-param-list|q-signature|sign|signature|authorization|x-amz-signature|x-amz-credential|x-amz-date|x-cos-signature|x-tc-signature)$"
    if parts.contains(where: { matches(decode($0.components(separatedBy: "=")[0]), signature) }) { return source }
    if matches(base, "\\.(?:gif|svg|svgz)$") { return source }
    let size = min(800, max(1, width > 0 ? width : 400))
    if let index = parts.firstIndex(where: { matches(decode($0.components(separatedBy: "=")[0]), "^image(?:Mogr2|View2)/") }) {
        let part = parts[index]
        let equal = part.firstIndex(of: "=")
        let suffix = equal.map { String(part[$0...]) } ?? ""
        var rule = decode(equal.map { String(part[..<$0]) } ?? part)
        if matches(rule, "^imageMogr2/") {
            if let range = rule.range(of: "/thumbnail/[^/]+", options: [.regularExpression, .caseInsensitive]) {
                let prefix = String(rule[range]).components(separatedBy: "/").dropLast().joined(separator: "/")
                rule.replaceSubrange(range, with: prefix + "/\(size)x")
            } else { rule = rule.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/thumbnail/\(size)x" }
        } else {
            rule = rule.replacingOccurrences(of: "^imageView2/3(?=/|$)", with: "imageView2/2", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "^imageView2/4(?=/|$)", with: "imageView2/5", options: [.regularExpression, .caseInsensitive])
            if let range = rule.range(of: "/w/[0-9]+(?=/|$)", options: [.regularExpression, .caseInsensitive]) {
                let prefix = String(rule[range]).components(separatedBy: "/").dropLast().joined(separator: "/")
                rule.replaceSubrange(range, with: prefix + "/\(size)")
            } else { rule = rule.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/w/\(size)" }
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()/")
        parts[index] = (rule.addingPercentEncoding(withAllowedCharacters: allowed) ?? rule) + suffix
    } else {
        // 去掉末尾分隔符留下的空项，避免生成双重 &；其他查询参数保持原样。
        if parts.last == "" { parts.removeLast() }
        parts.append("imageMogr2/thumbnail/\(size)x")
    }
    if host == "cdn.jaronsoft.com" {
        let cache = "jhcti_image_width=\(size)"
        if let index = parts.firstIndex(where: { decode($0.components(separatedBy: "=")[0]) == "jhcti_image_width" }) { parts[index] = cache }
        else { parts.append(cache) }
    }
    return base + "?" + parts.joined(separator: "&") + fragment
}
