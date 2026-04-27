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
// is needed, so a .lightweight stage is sufficient.

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
            EpisodeTranscriptCache.self,
        ]
    }
}

// MARK: - Migration Plan

enum OffScriptMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Lightweight migration: adds the EpisodeTranscriptCache table.
    /// No data transformation required — SwiftData creates the new store
    /// table automatically.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
