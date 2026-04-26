import SwiftData

// MARK: - Current schema
//
// SwiftData uses the schema's *content* to compute a checksum that identifies
// it on disk. When V1 and V2 share the same model class set with only an
// added entity, both schemas can hash to the same checksum and trigger
// "Duplicate version checksums detected." For lightweight, additive changes
// (new entity, new optional property), SwiftData will silently migrate the
// existing store as long as we present the **single current schema** without
// an explicit migration plan. We do that here.
//
// When a future change is *not* lightweight (renaming, removing, or
// transforming columns), introduce a new VersionedSchema with a clearly
// different checksum (e.g. add an `@Attribute(originalName:)` on a renamed
// property) and reintroduce a `SchemaMigrationPlan` with explicit stages.

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
            Bookmark.self,
        ]
    }
}
