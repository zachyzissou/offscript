import Foundation

/// Process-wide cache of the most recently computed home recommendations.
///
/// Home recomputation is the heaviest synchronous main-actor work in the app
/// (multiple SwiftData fetches + per-episode scoring + diversification). This
/// cache lets `HomeView` paint instantly with the last-known sections while
/// background work decides whether to refresh.
@MainActor
final class HomeRecommendationCache {
    static let shared = HomeRecommendationCache()

    private(set) var sections: [HomeFeedSection] = []
    private var lastUpdate: Date = .distantPast
    private let staleAfter: TimeInterval = 60 * 5 // 5 minutes

    private init() {}

    var isStale: Bool {
        sections.isEmpty || Date().timeIntervalSince(lastUpdate) > staleAfter
    }

    func update(sections: [HomeFeedSection]) {
        self.sections = sections
        self.lastUpdate = .now
    }

    func invalidate() {
        sections = []
        lastUpdate = .distantPast
    }
}
