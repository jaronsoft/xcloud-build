import Foundation

public enum SchoolProfileDataState: Equatable {
    case loading
    case available
    case notConfigured
    case pendingVerification
    case notAvailable
    case notApplicable
    case error

    public static func response(hasData: Bool, isLoading: Bool, hasError: Bool) -> SchoolProfileDataState {
        if isLoading { return .loading }
        if hasError { return .error }
        return hasData ? .available : .notAvailable
    }

    public static func explicitServerStatus(_ value: String?) -> SchoolProfileDataState? {
        guard let value else { return nil }
        switch value.uppercased() {
        case "AVAILABLE", "CONFIRMED", "REPORTED": return .available
        case "NOT_CONFIGURED": return .notConfigured
        case "PARTIAL", "UNCONFIRMED", "PENDING_VERIFICATION": return .pendingVerification
        case "NOT_AVAILABLE", "NOT_AVAILABLE_FOR_CYCLE", "NOT_REPORTED": return .notAvailable
        case "NOT_APPLICABLE": return .notApplicable
        case "ERROR": return .error
        default: return nil
        }
    }

    public static func programSelection(_ value: String?) -> SchoolProfileDataState? {
        guard let value else { return nil }
        switch value.uppercased() {
        case "SELECTED", "NONE": return .available
        case "NOT_SURE": return .pendingVerification
        case "NOT_CONFIGURED": return .notConfigured
        default: return nil
        }
    }

    public func localizedLabel(zh: Bool) -> String {
        switch self {
        case .loading: return zh ? "加载中" : "Loading"
        case .available: return zh ? "有可用资料" : "Available"
        case .notConfigured: return zh ? "尚未配置" : "Not configured"
        case .pendingVerification: return zh ? "待核验" : "Pending verification"
        case .notAvailable: return zh ? "尚未收录" : "Not available"
        case .notApplicable: return zh ? "不适用" : "Not applicable"
        case .error: return zh ? "加载失败" : "Load error"
        }
    }
}

public enum SchoolCalendarQuery {
    public static func scopedItems(
        startDate: String,
        endDate: String,
        schoolId: String,
        childId: String?
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
            URLQueryItem(name: "school_id", value: schoolId)
        ]
        if let childId, !childId.isEmpty {
            items.append(URLQueryItem(name: "child_id", value: childId))
        }
        return items
    }
}
