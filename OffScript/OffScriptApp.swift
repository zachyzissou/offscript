//
//  OffScriptApp.swift
//  OffScript
//
//  Created by Zach Gonser on 3/16/26.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI
import UIKit

@main
struct OffScriptApp: App {
    private static let logger = Logger(subsystem: "OffScript", category: "SwiftData")

    init() {
        AppSettings.applyLaunchOverridesIfNeeded()

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        tabBarAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Podcast.self,
            Episode.self,
            EpisodeProfile.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            QueueItem.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
        ])
        do {
            return try Self.makeModelContainer(schema: schema)
        } catch {
            Self.logger.error("Primary SwiftData store failed to load: \(String(describing: error), privacy: .public)")

            do {
                try Self.resetPersistentStore()
                return try Self.makeModelContainer(schema: schema)
            } catch {
                Self.logger.fault("SwiftData store recovery failed: \(String(describing: error), privacy: .public)")
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: persistentStoreURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static var persistentStoreURL: URL {
        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = applicationSupportDirectory.appendingPathComponent("OffScript", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path()) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("OffScript.store")
    }

    private static func resetPersistentStore() throws {
        let fileManager = FileManager.default
        let baseURL = persistentStoreURL
        let companionExtensions = ["", "-shm", "-wal"]

        for suffix in companionExtensions {
            let targetURL = URL(fileURLWithPath: baseURL.path() + suffix)
            if fileManager.fileExists(atPath: targetURL.path()) {
                try fileManager.removeItem(at: targetURL)
            }
        }
    }
}
