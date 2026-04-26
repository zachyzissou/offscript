//
//  OffScriptApp.swift
//  OffScript
//
//  Created by Zach Gonser on 3/16/26.
//

import BackgroundTasks
import CarPlay
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: .carTemplateApplication)
            config.delegateClass = OffScriptCarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        return config
    }
}

@main
struct OffScriptApp: App {
    @UIApplicationDelegateAdaptor(OffScriptAppDelegate.self) private var appDelegate
    private static let logger = Logger(subsystem: "OffScript", category: "SwiftData")

    init() {
        // Boot crash + perf telemetry as the very first thing so anything
        // that explodes during the rest of init still lands in Sentry.
        // Both calls are no-ops if the DSN is missing (CI builds, forks).
        CrashReporter.configure()
        MetricKitReporter.shared.configure()

        AppSettings.applyLaunchOverridesIfNeeded()
        OffScriptTips.configureIfNeeded()

        // Tuner OLED tab bar: pure black, hairline top divider, mono labels.
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .black
        tabBarAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        // Item label styling — small uppercase mono with tracking.
        let signalYellow = UIColor(red: 232.0/255.0, green: 210.0/255.0, blue: 74.0/255.0, alpha: 1)
        let textMuted = UIColor(white: 0.953, alpha: 0.32)
        for itemAppearance in [
            tabBarAppearance.stackedLayoutAppearance,
            tabBarAppearance.inlineLayoutAppearance,
            tabBarAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = textMuted
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: textMuted,
                .font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold),
                .kern: 1.4
            ]
            itemAppearance.selected.iconColor = signalYellow
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: signalYellow,
                .font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold),
                .kern: 1.4
            ]
        }

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Navigation bar — flat black, mono uppercase title.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = .black
        navAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0.953, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .kern: 1.6
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = signalYellow
    }

    // MARK: - Model Container with Versioned Migration
    // Uses VersionedSchema + SchemaMigrationPlan for safe migrations.
    // Falls back to destructive reset only if the migration plan itself fails.
    var sharedModelContainer: ModelContainer = {
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
                .task {
                    let container = sharedModelContainer
                    ModelContainerRef.shared = container

                    // Validate Apple ID first — fast and may flip cloudSync off
                    // before any other launch work touches CloudKit.
                    await AppleAccountMonitor.shared.validateOnLaunch()

                    // Defer the heavy launch chores to a low-priority Task so
                    // they never block the first frame. Spotlight reindex
                    // touches every subscribed podcast + most-recent episodes
                    // and used to add a perceptible launch hitch.
                    Task(priority: .utility) {
                        try? await Task.sleep(for: .seconds(2))
                        let context = ModelContext(container)
                        SpotlightIndexer.shared.reindex(in: context)
                        BackgroundEnrichmentService.shared.backfill(in: context)
                    }
                }
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
