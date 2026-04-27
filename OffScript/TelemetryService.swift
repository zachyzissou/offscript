import Foundation
import SwiftData

enum TelemetryService {
    @MainActor
    static func track(_ name: String, metadata: [String: String] = [:], in context: ModelContext?) {
        guard let context else { return }
        let compactMetadata = metadata.reduce(into: [String: String]()) { partialResult, item in
            let trimmedValue = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { return }
            partialResult[item.key] = trimmedValue
        }

        context.insert(TelemetryEvent(name: name, metadata: compactMetadata))
        context.saveOrLog("Telemetry")
    }
}
