import Foundation
import Testing
@testable import AIS

struct AISAPIRoutingTests {
    @Test("只有明显更快时才切换 API 节点")
    func switchesOnlyForMaterialImprovement() {
        let selected = AppRoutingEndpointSelector.select(
            measurements: [
                .init(endpointID: "cn-primary", latency: 0.50),
                .init(endpointID: "global-primary", latency: 0.30),
            ],
            preferredEndpointID: "cn-primary"
        )

        #expect(selected == "global-primary")
    }

    @Test("延迟差异不明显时保持当前 API 节点")
    func keepsPreferredEndpointForMinorDifference() {
        let selected = AppRoutingEndpointSelector.select(
            measurements: [
                .init(endpointID: "cn-primary", latency: 0.50),
                .init(endpointID: "global-primary", latency: 0.40),
            ],
            preferredEndpointID: "cn-primary"
        )

        #expect(selected == "cn-primary")
    }

    @Test("当前节点不可用时选择可用节点")
    func selectsReachableEndpointWhenPreferredIsUnavailable() {
        let selected = AppRoutingEndpointSelector.select(
            measurements: [
                .init(endpointID: "global-primary", latency: 0.80),
            ],
            preferredEndpointID: "cn-primary"
        )

        #expect(selected == "global-primary")
    }

    @Test("所有探测失败时保持当前 API 节点")
    func keepsPreferredEndpointWhenAllProbesFail() {
        let selected = AppRoutingEndpointSelector.select(
            measurements: [],
            preferredEndpointID: "cn-primary"
        )

        #expect(selected == "cn-primary")
    }
}
