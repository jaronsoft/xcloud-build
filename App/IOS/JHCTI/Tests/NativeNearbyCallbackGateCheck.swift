import Foundation

@main
struct NativeNearbyCallbackGateCheck {
    @MainActor
    static func main() {
        var generation = 1
        var displayedRows = ["当前结果"]
        let requestGeneration = generation
        let lateCallback = {
            NativeNearbyCallbackGate.applyIfCurrent({ requestGeneration == generation }) {
                displayedRows = ["过期结果"]
            }
        }

        generation = 2
        _ = lateCallback()
        precondition(displayedRows == ["当前结果"], "过期回执不应覆盖当前结果")

        let accepted = NativeNearbyCallbackGate.applyIfCurrent({ generation == 2 }) {
            displayedRows = ["新结果"]
        }
        precondition(accepted && displayedRows == ["新结果"], "当前回执应正常写回")
        print("iOS 附近查询迟到回执门禁：3 项断言通过")
    }
}
