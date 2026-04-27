import SwiftData

// MARK: - Schema V1 (baseline)
// Captures the current state of all persisted model types.
// Future schema changes should add a new SchemaVN enum and a corresponding
// MigrationStage in OffScriptMigrationPlan.stages.

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
            EpisodeTranscriptCache.self,
        ]
    }
}

// MARK: - Migration Plan

enum OffScriptMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No stages needed yet — SchemaV1 is the only version.
        []
    }
}
