import Combine
import Foundation

@MainActor
final class ResourceDetailReviewRuntime: ObservableObject {
    @Published private(set) var review: [String: Any]?
    @Published private(set) var loading = false
    @Published private(set) var reviewBusy = false
    @Published private(set) var appealBusy = false
    @Published private(set) var error: String?
    @Published private(set) var featureState: NativePublicFeatureAccessState = .unavailable
    @Published var rating = 5
    @Published var content = ""
    @Published var appealContent = ""

    private let store: SessionStore
    private var resourceID: String
    private var requestSequence = 0
    private var contextGeneration = 0
    private var reviewLoaded = false
    private var loadedPrincipal: String?
    private var loadedResourceID: String?

    init(store: SessionStore, resourceID: String) {
        self.store = store
        self.resourceID = resourceID
    }

    func updateResource(id: String) {
        guard resourceID != id else { return }
        resourceID = id
        resetForAccountChange()
    }

    func resetForAccountChange() {
        contextGeneration += 1
        requestSequence += 1
        loading = false
        reviewBusy = false
        appealBusy = false
        review = nil
        reviewLoaded = false
        loadedPrincipal = nil
        loadedResourceID = nil
        error = nil
        featureState = .unavailable
        rating = 5
        content = ""
        appealContent = ""
    }

    func load() async {
        requestSequence += 1
        let sequence = requestSequence
        let currentResourceID = resourceID
        featureState = .unavailable
        let api = MobileAPI(store: store)
        let access = await api.featureAccessState("USER-REVIEWS", forceRefresh: true)
        guard resourceID == currentResourceID, requestSequence == sequence else { return }
        featureState = access
        guard let token = store.session?.accessToken, !token.isEmpty else {
            review = nil
            reviewLoaded = true
            loadedPrincipal = nil
            loadedResourceID = nil
            error = nil
            loading = false
            content = ""
            appealContent = ""
            return
        }
        guard let expectedPrincipal = nativeTourismPrincipal(token) else { return }
        reviewLoaded = false
        loadedPrincipal = nil
        loadedResourceID = nil
        loading = true
        error = nil
        defer {
            if store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
               requestSequence == sequence, resourceID == currentResourceID {
                loading = false
            }
        }
        do {
            let value = try await api.get(
                "/api/JHCTITourismResource/GetMyReview?resourceId=\(currentResourceID)", authenticated: true,
                expectedPrincipal: expectedPrincipal)
            guard resourceID == currentResourceID,
                  store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
                  requestSequence == sequence else { return }
            review = value as? [String: Any]
            reviewLoaded = true
            loadedPrincipal = expectedPrincipal
            loadedResourceID = currentResourceID
        } catch {
            if resourceID == currentResourceID,
               store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
               requestSequence == sequence {
                self.error = "本人评价状态暂不可用：\(error.localizedDescription)"
            }
        }
    }

    func submitReview() async {
        guard let token = store.session?.accessToken, !token.isEmpty,
              let expectedPrincipal = nativeTourismPrincipal(token) else {
            error = "请先登录文旅账号。"
            return
        }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentResourceID = resourceID
        let currentContextGeneration = contextGeneration
        guard featureState == .open, !trimmedContent.isEmpty, trimmedContent.utf16.count <= 2000,
              reviewLoaded, loadedPrincipal == expectedPrincipal,
              !reviewBusy, !loading, review == nil else { return }
        reviewBusy = true
        error = nil
        defer {
            if contextGeneration == currentContextGeneration,
               store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
               resourceID == currentResourceID { reviewBusy = false }
        }
        do {
            let api = MobileAPI(store: store)
            let access = await api.featureAccessState("USER-REVIEWS", forceRefresh: true)
            guard resourceID == currentResourceID,
                  contextGeneration == currentContextGeneration,
                  store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal else { return }
            featureState = access
            guard access == .open else {
                error = access.message(featureName: "评价功能", action: "暂不能提交新评价")
                return
            }
            let value = try await api.post("/api/JHCTITourismResource/SubmitReview",
                body: ["ResourceId": currentResourceID, "Rating": rating, "Content": trimmedContent],
                authenticated: true, expectedPrincipal: expectedPrincipal)
            guard resourceID == currentResourceID,
                  contextGeneration == currentContextGeneration,
                  store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
                  let result = value as? [String: Any], result["ResourceId"] as? String == currentResourceID else {
                throw MobileAPIError.unavailable("评价回执无法确认，请刷新本人评价状态。")
            }
            requestSequence += 1
            review = result
            content = ""
            reviewLoaded = true
        } catch {
            if resourceID == currentResourceID,
               contextGeneration == currentContextGeneration,
               store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal {
                self.error = error.localizedDescription
            }
        }
    }

    func submitAppeal() async {
        guard let token = store.session?.accessToken, !token.isEmpty,
              let expectedPrincipal = nativeTourismPrincipal(token),
              let currentReview = review,
              let reviewID = currentReview["Id"] as? String else {
            error = "请先登录并刷新本人评价状态。"
            return
        }
        let trimmedContent = appealContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentResourceID = resourceID
        let currentContextGeneration = contextGeneration
        guard reviewLoaded, loadedPrincipal == expectedPrincipal,
              currentReview["ResourceId"] as? String == currentResourceID,
              currentReview["ReviewStatus"] as? Int == 2,
              (currentReview["AppealStatus"] as? Int) != 1,
              (5...2000).contains(trimmedContent.utf16.count), !appealBusy else { return }
        appealBusy = true
        error = nil
        defer {
            if contextGeneration == currentContextGeneration,
               store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
               resourceID == currentResourceID { appealBusy = false }
        }
        do {
            let receipt = try await MobileAPI(store: store).post("/api/JHCTITourismResource/SubmitAppeal",
                body: ["ReviewId": reviewID, "Content": trimmedContent], authenticated: true,
                expectedPrincipal: expectedPrincipal)
            guard resourceID == currentResourceID,
                  contextGeneration == currentContextGeneration,
                  store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal,
                  receipt as? String == reviewID else {
                throw MobileAPIError.unavailable("申诉回执无法确认，请刷新本人评价状态。")
            }
            appealContent = ""
            await load()
        } catch {
            if resourceID == currentResourceID,
               contextGeneration == currentContextGeneration,
               store.session.map({ nativeTourismPrincipal($0.accessToken) }) == expectedPrincipal {
                self.error = error.localizedDescription
            }
        }
    }

    static func limitedText(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        var length = 0
        for scalar in value.unicodeScalars {
            let scalarLength = scalar.value > 0xFFFF ? 2 : 1
            guard length + scalarLength <= 2000 else { break }
            result.append(scalar)
            length += scalarLength
        }
        return String(result)
    }

    func reviewForCurrentContext(resourceID expectedResourceID: String) -> [String: Any]? {
        guard reviewLoaded, loadedResourceID == expectedResourceID,
              loadedPrincipal == nativeTourismPrincipal(store.session?.accessToken) else { return nil }
        return review
    }

    func isLoadingCurrentContext(resourceID expectedResourceID: String) -> Bool {
        guard store.session?.accessToken != nil else { return false }
        return loading || !reviewLoaded || loadedResourceID != expectedResourceID
            || loadedPrincipal != nativeTourismPrincipal(store.session?.accessToken)
    }
}
