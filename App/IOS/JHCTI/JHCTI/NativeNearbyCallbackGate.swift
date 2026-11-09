import Foundation

@MainActor
enum NativeNearbyCallbackGate {
    /// 迟到回执只有在调用方的请求代次、位置和页面状态仍有效时才能写回。
    static func applyIfCurrent(_ isCurrent: @MainActor () -> Bool,
                               update: @MainActor () -> Void) -> Bool {
        guard isCurrent() else { return false }
        update()
        return true
    }
}
