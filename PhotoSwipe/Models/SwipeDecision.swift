import Foundation

/// The verdict a user gives a single asset while swiping.
enum SwipeDecision: String, Codable, CaseIterable {
    case keep
    case delete
    case hide
}

/// Which way the session walks the library. `assetIDs` are always stored
/// newest → oldest, so `newestFirst` advances by +1 and `oldestFirst` by -1.
enum SwipeDirection: String, Codable, CaseIterable {
    case newestFirst
    case oldestFirst

    var step: Int { self == .newestFirst ? 1 : -1 }

    var title: String {
        switch self {
        case .newestFirst: return "Newest → oldest"
        case .oldestFirst: return "Oldest → newest"
        }
    }
}
