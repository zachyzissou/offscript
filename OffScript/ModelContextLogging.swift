import OSLog
import SwiftData

private let saveLogger = Logger(subsystem: "com.offscript", category: "Save")

extension ModelContext {
    /// Save the context and log any failure via OSLog instead of letting
    /// it disappear into the void of `try?`. Pass `category` so the log
    /// line tells us where the failure happened — without that, every
    /// failure looked the same in Console and was untraceable.
    ///
    /// Use this anywhere you'd otherwise write `try? context.save()`.
    /// CLAUDE.md forbids bare `try?` for exactly this reason: silent
    /// failure is the worst kind of failure to debug.
    func saveOrLog(_ category: StaticString) {
        do {
            try save()
        } catch {
            saveLogger.error("Save failed [\(category, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
        }
    }
}
