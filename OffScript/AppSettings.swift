import Foundation
import Network

// MARK: - Network Monitor

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    private(set) var connectionType: NWInterface.InterfaceType?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.offscript.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
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
        static let recentSearches = "offscript.recentSearches"
        static let libraryShowDownloadedOnly = "offscript.libraryShowDownloadedOnly"
        static let librarySortMode = "offscript.librarySortMode"
        static let cloudSyncEnabled = "offscript.cloudSyncEnabled"
        static let lastCloudSyncDate = "offscript.lastCloudSyncDate"
    }

    enum LibrarySortMode: String, CaseIterable {
        case newest
        case oldest
        case recentlyPlayed
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

    static var recentSearchesStorage: String {
        get { defaults.string(forKey: Key.recentSearches) ?? "" }
        set { defaults.set(newValue, forKey: Key.recentSearches) }
    }

    static var libraryShowDownloadedOnly: Bool {
        get { defaults.bool(forKey: Key.libraryShowDownloadedOnly) }
        set { defaults.set(newValue, forKey: Key.libraryShowDownloadedOnly) }
    }

    static var librarySortMode: LibrarySortMode {
        get {
            guard let raw = defaults.string(forKey: Key.librarySortMode),
                  let mode = LibrarySortMode(rawValue: raw) else {
                return .newest
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.librarySortMode) }
    }

    static var cloudSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.cloudSyncEnabled) }
        set { defaults.set(newValue, forKey: Key.cloudSyncEnabled) }
    }

    static var lastCloudSyncDate: Date? {
        get { defaults.object(forKey: Key.lastCloudSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCloudSyncDate) }
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
