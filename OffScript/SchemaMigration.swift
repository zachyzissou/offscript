import Foundation
import SwiftData

// MARK: - Schema V1 (baseline)
// Captures the original set of persisted model types shipped before on-device
// transcription was added. Do NOT add new model types here — add a SchemaVN
// and a corresponding MigrationStage in OffScriptMigrationPlan instead.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Podcast.self,
            Episode.self,
            QueueItem.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            EpisodeProfile.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
        ]
    }
}

// MARK: - Schema V2
// Adds EpisodeTranscriptCache (new table — additive, lightweight migration).
// Existing V1 stores gain the new table automatically; no data transformation
// is needed, so a .lightweight stage is sufficient. Keep the nested
// EpisodeTranscriptCache model frozen to the 2.4.x store shape; later releases
// add fields in SchemaV3.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Podcast.self,
            Episode.self,
            QueueItem.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            EpisodeProfile.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
            SchemaV2.EpisodeTranscriptCache.self,
        ]
    }
}

extension SchemaV2 {
    @Model
    final class EpisodeTranscriptCache {
        @Attribute(.unique) var episodeID: UUID = UUID()
        var text: String = ""
        var generatedAt: Date = Date()
        var source: String = "speech"
        var coverageSeconds: TimeInterval?

        init(
            episodeID: UUID,
            text: String,
            generatedAt: Date = .now,
            source: String = "speech",
            coverageSeconds: TimeInterval? = nil
        ) {
            self.episodeID = episodeID
            self.text = text
            self.generatedAt = generatedAt
            self.source = source
            self.coverageSeconds = coverageSeconds
        }
    }
}

// MARK: - Schema V3
// 2.5.0 expanded EpisodeTranscriptCache for published/timed transcripts
// (`language`, JSON cue storage) and EpisodeChapter's Codable payload shape.
// EpisodeChapter is persisted inside Episode.chaptersStorage as JSON, so the
// store-level schema change here is the transcript-cache table. V3 freezes that
// new shape and lets 2.4.x stores migrate in place instead of being quarantined.

enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Podcast.self,
            Episode.self,
            QueueItem.self,
            PlaybackEvent.self,
            PreferenceSignal.self,
            EpisodeProfile.self,
            UserTasteProfile.self,
            TelemetryEvent.self,
            EpisodeTranscriptCache.self,
        ]
    }
}

// MARK: - Migration Plan

enum OffScriptMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// Lightweight migration: adds the EpisodeTranscriptCache table.
    /// No data transformation required — SwiftData creates the new store
    /// table automatically.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    /// Lightweight migration: adds EpisodeTranscriptCache.language (optional)
    /// + cue storage (String with empty default). Pure additive columns;
    /// SwiftData fills defaults / nulls for existing rows automatically.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}
