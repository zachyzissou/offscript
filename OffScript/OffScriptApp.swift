//
//  OffScriptApp.swift
//  OffScript
//
//  Created by Zach Gonser on 3/16/26.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct OffScriptApp: App {
    init() {
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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
