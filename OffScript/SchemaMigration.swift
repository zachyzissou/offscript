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

// MARK: - Schema V3
// 2.5.0 added two scoring fields to EpisodeProfile (`confidenceScore`,
// `freshnessBucket`) — see Models.swift around line 358. Both have default
// or nullable types so the migration is additive + lightweight. The
// missing-V3 was the cause of the 2.5.0 ship bug where existing-user
// libraries quarantined: SwiftData saw a fingerprint mismatch against
// the V2-shaped on-disk store, failed migration, and the three-tier
// recovery in OffScriptApp.swift fell through to the rename-and-fresh
// quarantine path. 2.5.1 ships V3 + the migration stage so existing
// libraries upgrade in place.

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

    /// Lightweight migration: adds EpisodeProfile.confidenceScore (Double
    /// with default 0.0) + EpisodeProfile.freshnessBucket (optional String).
    /// Pure additive columns; SwiftData fills defaults / nulls for
    /// existing rows automatically.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}
