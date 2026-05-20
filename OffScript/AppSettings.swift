import Foundation
import Network

// MARK: - Network Monitor

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var connectionType: NWInterface.InterfaceType?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.offscript.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - App Settings

enum AppSettings {
    private enum Key {
        static let hasSeenOnboarding = "offscript.hasSeenOnboarding"
        static let autoPlayNext = "offscript.autoPlayNext"
        static let preferShortEpisodes = "offscript.preferShortEpisodes"
        static let preferredGenres = "offscript.preferredGenres"
        static let recommendationMode = "offscript.recommendationMode"
        static let recentSearches = "offscript.recentSearches"
        static let cloudSyncEnabled = "offscript.cloudSyncEnabled"
        static let cloudSyncRuntimeState = "offscript.cloudSyncRuntimeState"
        static let downloadsWiFiOnly = "offscript.downloadsWiFiOnly"
    }

    enum CloudSyncRuntimeState: String {
        case localOnly
        case cloudBacked
        case fallbackFailed
    }

    nonisolated enum RecommendationMode: String, CaseIterable {
        case signalLocked
        case balanced
        case discovery

        var label: String {
            switch self {
            case .signalLocked: "SIGNAL"
            case .balanced: "BALANCED"
            case .discovery: "DISCOVERY"
            }
        }

        var detail: String {
            switch self {
            case .signalLocked:
                "Only episodes with explicit local evidence. No new-show discovery."
            case .balanced:
                "Prioritize queue, resume, completion, and topic signal with a small discovery lane."
            case .discovery:
                "Keep local signal first, then surface more new-show candidates from your taste profile."
            }
        }

        var allowsDiscovery: Bool {
            self != .signalLocked
        }

        var discoveryLimit: Int {
            switch self {
            case .signalLocked: 0
            case .balanced: 6
            case .discovery: 10
            }
        }
    }

    private static let defaults = UserDefaults.standard

    static var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasSeenOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasSeenOnboarding) }
    }

    static var autoPlayNext: Bool {
        get {
            if defaults.object(forKey: Key.autoPlayNext) == nil { return true }
            return defaults.bool(forKey: Key.autoPlayNext)
        }
        set { defaults.set(newValue, forKey: Key.autoPlayNext) }
    }

    static var preferShortEpisodes: Bool {
        get { defaults.bool(forKey: Key.preferShortEpisodes) }
        set { defaults.set(newValue, forKey: Key.preferShortEpisodes) }
    }

    static var preferredGenres: [Genre] {
        get {
            defaults.stringArray(forKey: Key.preferredGenres)?
                .compactMap(Genre.init(rawValue:)) ?? []
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: Key.preferredGenres)
        }
    }

    static var recommendationMode: RecommendationMode {
        get {
            guard let raw = defaults.string(forKey: Key.recommendationMode),
                  let mode = RecommendationMode(rawValue: raw) else {
                return .balanced
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.recommendationMode) }
    }

    static var recentSearchesStorage: String {
        get { defaults.string(forKey: Key.recentSearches) ?? "" }
        set { defaults.set(newValue, forKey: Key.recentSearches) }
    }

    static var cloudSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.cloudSyncEnabled) }
        set { defaults.set(newValue, forKey: Key.cloudSyncEnabled) }
    }

    static var cloudSyncRuntimeState: CloudSyncRuntimeState {
        get {
            guard let raw = defaults.string(forKey: Key.cloudSyncRuntimeState),
                  let state = CloudSyncRuntimeState(rawValue: raw) else {
                return .localOnly
            }
            return state
        }
        set { defaults.set(newValue.rawValue, forKey: Key.cloudSyncRuntimeState) }
    }

    /// When `true`, `DownloadService` defers starting new downloads while the
    /// device is on cellular. Already-running URLSession tasks are not killed
    /// (they may have started on Wi-Fi); only newly-requested downloads queue.
    /// Default is `true` — most users expect podcast app downloads to respect
    /// metered data unless they explicitly opt in. Surface in Settings.
    static var downloadsWiFiOnly: Bool {
        get {
            if defaults.object(forKey: Key.downloadsWiFiOnly) == nil { return true }
            return defaults.bool(forKey: Key.downloadsWiFiOnly)
        }
        set { defaults.set(newValue, forKey: Key.downloadsWiFiOnly) }
    }

    static var currentUserID: String? {
        UserProfileService.currentUserID
    }

    static var displayName: String? {
        get { UserProfileService.displayName }
        set { UserProfileService.displayName = newValue }
    }

    static func saveCredential(userID: String, displayName: String?) throws {
        try UserProfileService.saveCredential(userID: userID, displayName: displayName)
    }

    static func clearCredential() {
        UserProfileService.deleteCredential()
    }

    static func applyLaunchOverridesIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let onboardingIndex = arguments.firstIndex(of: "-offscript.hasSeenOnboarding"),
              arguments.indices.contains(arguments.index(after: onboardingIndex)) else {
            return
        }

        let value = arguments[arguments.index(after: onboardingIndex)]
        hasSeenOnboarding = NSString(string: value).boolValue
    }
}
