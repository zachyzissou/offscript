//
//  OffScriptApp.swift
//  OffScript
//
//  Created by Zach Gonser on 3/16/26.
//

import BackgroundTasks
import CloudKit
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
        // Crash + perf telemetry. Sentry first so its hooks are installed
        // before AppSettings.applyLaunchOverridesIfNeeded() (which can touch
        // UserDefaults / debug toggles that we'd want to see in Sentry breadcrumbs
        // if anything goes sideways during boot).
        CrashReporter.configure()
        MetricKitReporter.shared.configure()
        AppSettings.applyLaunchOverridesIfNeeded()

        // Tab bar is custom (TunerTabBar in ContentView) — no SwiftUI TabView
        // in the tree, so UITabBarAppearance config would do nothing. iOS 26
        // was ignoring it anyway and forcing the floating Liquid Glass
        // capsule, which is what made the tab bar look like a foreign UI on
        // top of the otherwise-Tuner instrument cluster.
    }

    // MARK: - Model Container with Versioned Migration
    // Uses VersionedSchema + SchemaMigrationPlan for safe migrations.
    // Falls back to destructive reset only if the migration plan itself fails.
    var sharedModelContainer: ModelContainer = {
        // Use the VersionedSchema so SwiftData can run our migration plan
        // (OffScriptMigrationPlan) when the on-disk store predates the
        // current schema. Origin/main's flat Schema([...]) was simpler but
        // would force-wipe the store on every breaking schema change — the
        // versioned path is what keeps user libraries intact across releases.
        let schema = Schema(versionedSchema: SchemaV2.self)
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
        let cloudKitEnabled = AppSettings.cloudSyncEnabled && AppSettings.currentUserID != nil

        if cloudKitEnabled {
            // Try CloudKit first, fall back to local if it fails (e.g., no dev account)
            do {
                let cloudConfig = ModelConfiguration(
                    schema: schema,
                    url: persistentStoreURL,
                    cloudKitDatabase: .automatic
                )
                logger.info("CloudKit sync enabled — creating ModelContainer with iCloud backing")
                return try ModelContainer(
                    for: schema,
                    migrationPlan: OffScriptMigrationPlan.self,
                    configurations: [cloudConfig]
                )
            } catch {
                logger.warning("CloudKit ModelContainer failed, falling back to local: \(String(describing: error), privacy: .public)")
                // Fall through to local-only
            }
        }

        let localConfig = ModelConfiguration(
            schema: schema,
            url: persistentStoreURL,
            cloudKitDatabase: .none
        )
        logger.info("Using local-only ModelContainer")
        return try ModelContainer(
            for: schema,
            migrationPlan: OffScriptMigrationPlan.self,
            configurations: [localConfig]
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
