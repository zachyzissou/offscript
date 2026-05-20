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
    private static let logger = Logger(subsystem: "com.offscript", category: "SwiftData")

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
    //
    // Three-tier recovery:
    //   1. Open the on-disk store with the SchemaV3 migration plan. Lets
    //      existing user data carry forward via the V1→V2→V3 stages.
    //   2. If (1) fails (e.g. "Cannot use staged migration with an unknown
    //      model version" — happens when the on-disk store has metadata
    //      that doesn't match either V1 or V2; possible if a build between
    //      versions wrote the store and was never released), QUARANTINE the
    //      failing store (rename to .corrupted-<timestamp>) and create a
    //      fresh one. We don't delete in case the user wants to recover it
    //      via Files later.
    //   3. If (2) ALSO fails (extremely rare), fall back to an in-memory
    //      container so the app at least launches. User loses data but the
    //      UI works and they can reinstall to get a clean slate.
    //
    // Earlier versions called `resetPersistentStore()` which only deleted
    // the .store / .store-shm / .store-wal trio at the standard path. iOS 26
    // SwiftData seems to also leave migration-metadata caches in the same
    // directory or in app-private dirs that break the second attempt with
    // the same error. Quarantining the entire OffScript subdirectory and
    // creating a fresh one sidesteps that.
    /// Exposed for non-SwiftUI scene entry points (notably
    /// `CarPlaySceneDelegate`) that cannot read the SwiftUI
    /// `\.modelContext` environment. Set in the lazy initializer below as a
    /// side effect of building `sharedModelContainer`. CarPlay scene-connect
    /// can fire either before or after the main `WindowGroup` is constructed,
    /// so this property must be safe to read at any point after `init()`.
    /// `nonisolated(unsafe)` because the assignment happens once during
    /// container init (single thread) and reads are guarded by the optional —
    /// CarPlay reads on the main actor.
    nonisolated(unsafe) static var carPlayModelContainer: ModelContainer?

    var sharedModelContainer: ModelContainer = {
        let container = Self.buildModelContainer()
        // Publish for non-SwiftUI scene entry points (CarPlay). Safe to
        // assign here because this initializer runs exactly once during
        // `OffScriptApp.init()`.
        Self.carPlayModelContainer = container
        return container
    }()

    private static func buildModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV3.self)
        do {
            return try Self.makeModelContainer(schema: schema)
        } catch {
            Self.logger.error("Primary SwiftData store failed to load: \(String(describing: error), privacy: .public)")

            do {
                try Self.quarantineStoreDirectory()
                Self.logger.info("Quarantined corrupted store directory — retrying with fresh schema")
                // Rebuild Schema instance — keeps SwiftData's internal
                // state from carrying over the failed first attempt.
                let freshSchema = Schema(versionedSchema: SchemaV3.self)
                return try Self.makeModelContainer(schema: freshSchema)
            } catch {
                Self.logger.fault("Quarantine + retry failed: \(String(describing: error), privacy: .public). Falling back to in-memory store so the app at least launches.")
                do {
                    let inMemory = try ModelContainer(
                        for: Schema(versionedSchema: SchemaV3.self),
                        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                    )
                    Self.logger.fault("In-memory ModelContainer active — user data will not persist across launches until the on-disk store can be opened again.")
                    AppSettings.cloudSyncRuntimeState = .fallbackFailed
                    return inMemory
                } catch let inMemoryError {
                    Self.logger.fault("In-memory ModelContainer init also failed: \(String(describing: inMemoryError), privacy: .public)")
                    fatalError("Could not create ModelContainer: quarantine error=\(error); in-memory error=\(inMemoryError)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ActivityKit doesn't auto-end Live Activities when the host
                // app is force-quit, so a previously-pinned now-playing
                // activity stays frozen on the Dynamic Island / Lock Screen
                // until the user swipes it away. Sweep stale activities on
                // every cold launch — the helper checks `Activity<...>.activities`
                // and ends any that don't match a current playback session.
                //
                // Also bootstraps the BGTaskScheduler subsystems. The
                // .backgroundTask modifier below ONLY runs the handler when
                // iOS already has a pending submission for that identifier;
                // it doesn't self-submit on first launch. Without these
                // scheduleNext...() calls the feed-refresh + background-
                // transcription subsystems never fire because nothing
                // ever submits a BGAppRefreshTaskRequest. Flagged by the
                // 2026-05-20 dead-code-wiring sweep as BROKEN-WIRING #3.
                .task {
                    await NowPlayingActivityCoordinator.endStaleActivities()
                    BackgroundFeedRefresh.scheduleNextRefresh()
                    BackgroundTranscriptionService.scheduleNextRound()
                }
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh(BackgroundFeedRefresh.taskIdentifier)) {
            await BackgroundFeedRefresh.performRefresh(container: sharedModelContainer)
        }
        .backgroundTask(.appRefresh(BackgroundTranscriptionService.taskIdentifier)) {
            await BackgroundTranscriptionService.performTranscriptionRound(container: sharedModelContainer)
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
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: OffScriptMigrationPlan.self,
                    configurations: [cloudConfig]
                )
                AppSettings.cloudSyncRuntimeState = .cloudBacked
                return container
            } catch {
                AppSettings.cloudSyncRuntimeState = .fallbackFailed
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
        if !cloudKitEnabled {
            AppSettings.cloudSyncRuntimeState = .localOnly
        }
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

    /// Move the entire `OffScript/` subdirectory of Application Support to a
    /// timestamped `OffScript-corrupted-<unix-time>/` sibling, then create a
    /// fresh empty `OffScript/`. This sidesteps any SwiftData migration-
    /// metadata caches sitting next to the .store files — an issue we hit
    /// where deleting just .store/.shm/.wal wasn't enough for the second
    /// migration attempt to succeed.
    ///
    /// We rename rather than delete so the user can recover the prior store
    /// from Files.app if they need to.
    private static func quarantineStoreDirectory() throws {
        let fileManager = FileManager.default
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let storeDir = appSupport.appendingPathComponent("OffScript", isDirectory: true)

        if fileManager.fileExists(atPath: storeDir.path()) {
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantineDir = appSupport.appendingPathComponent(
                "OffScript-corrupted-\(stamp)",
                isDirectory: true
            )
            try fileManager.moveItem(at: storeDir, to: quarantineDir)
            logger.info("Moved corrupted store dir to \(quarantineDir.path(), privacy: .public)")
        }

        // Recreate empty store dir so makeModelContainer's persistentStoreURL
        // resolves to a writable path on the second attempt.
        try fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
    }
}
