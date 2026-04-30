import Foundation
import SwiftData

@MainActor
enum PreferenceFeedbackService {
    static func register(
        _ action: PreferenceSignal.Action,
        for episode: Episode,
        in context: ModelContext,
        notificationCenter: NotificationCenter = .default
    ) throws {
        let signal = PreferenceSignal(action: action, episode: episode)
        context.insert(signal)
        do {
            try context.save()
            notificationCenter.post(name: .offscriptRecommendationFeedbackChanged, object: episode.id)
        } catch {
            context.delete(signal)
            throw error
        }
    }
}
