import Foundation
import Testing
@testable import AIS

struct AISMemoryModelsTests {
    @Test
    func snowflakeIdentifiersDecodeAsStrings() throws {
        let data = Data(
            """
            {
              "Id":"1949876543210987654",
              "ProjectId":"1949876543210987655",
              "Scope":"project",
              "MemoryType":"project_rule",
              "Category":"color_preference",
              "PreferenceKey":"image.color.family",
              "PreferenceValueJson":"{\\"operator\\":\\"prefer\\",\\"value\\":\\"navy_blue\\"}",
              "Content":"偏好墨蓝色",
              "Status":"confirmed",
              "Weight":70,
              "ApplyCount":2,
              "EvidenceCount":3,
              "RowVersion":4,
              "SupersedesMemoryId":"1949876543210987653",
              "SourceCount":1,
              "SourceSummary":[{
                "Id":"1949876543210987656",
                "SourceType":"history_job",
                "SourceScene":"image_generate",
                "SourceText":"脱敏摘录",
                "ExtractReason":"多次任务使用相同偏好",
                "Title":"工业产品主视觉",
                "Description":"深色背景中的金属设备",
                "Keywords":["工业设计","金属材质"],
                "ResultUrl":"https://cdn.example.com/result.webp",
                "MediaType":"image"
              }]
            }
            """.utf8
        )

        let item = try JSONDecoder().decode(AISMemoryItem.self, from: data)

        #expect(item.id == "1949876543210987654")
        #expect(item.projectId == "1949876543210987655")
        #expect(item.supersedesMemoryId == "1949876543210987653")
        #expect(item.sourceSummary.first?.id == "1949876543210987656")
        #expect(item.sourceSummary.first?.title == "工业产品主视觉")
        #expect(item.sourceSummary.first?.keywords == ["工业设计", "金属材质"])
        #expect(item.sourceSummary.first?.resultURL?.absoluteString == "https://cdn.example.com/result.webp")
    }

    @Test
    func memorySnapshotDecodesAppliedAndOverriddenItems() throws {
        let data = Data(
            """
            {
              "SchemaVersion":"1.0",
              "Scene":"image_generate",
              "Applied":[{"Id":"1","Content":"喜欢留白"}],
              "Overridden":[{"Id":"2","Content":"避免蓝色","DecisionReason":"本次页面选择了蓝色"}]
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(
            AISMemoryContextSnapshot.self,
            from: data
        )

        #expect(snapshot.applied.map(\.id) == ["1"])
        #expect(snapshot.overridden.map(\.id) == ["2"])
    }
}
