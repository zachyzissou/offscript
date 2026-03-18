//
//  OffScriptApp.swift
//  OffScript
//
//  Created by Zach Gonser on 3/16/26.
//

import BackgroundTasks
import Foundation
import OSLog
import SwiftData
import SwiftUI
import UIKit

final class OffScriptAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            DownloadService.shared.backgroundCompletionHandler = completionHandler
        }
    }
}

@main
struct OffScriptApp: App {
    @UIApplicationDelegateAdaptor(OffScriptAppDelegate.self) private var appDelegate
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

    // MARK: - Model Container with Versioned Migration
    // Uses VersionedSchema + SchemaMigrationPlan for safe migrations.
    // Falls back to destructive reset only if the migration plan itself fails.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        do {
            return try Self.makeModelContainer(schema: schema)
        } catch {
            Self.logger.error("Primary SwiftData store failed to load: \(String(describing: error), privacy: .public)")

            // Safety net: wipe the store and recreate if migration fails.
            do {
                try Self.resetPersistentStore()
                Self.logger.info("Persistent store deleted — recreating with current schema")
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
        .backgroundTask(.appRefresh(BackgroundFeedRefresh.taskIdentifier)) {
            await BackgroundFeedRefresh.performRefresh(container: sharedModelContainer)
        }
    }

    private static func makeModelContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: persistentStoreURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: OffScriptMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static let persistentStoreURL: URL = {
        let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = applicationSupportDirectory.appendingPathComponent("OffScript", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path()) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("OffScript.store")
    }()

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
