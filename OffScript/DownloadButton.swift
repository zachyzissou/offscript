import SwiftUI

struct DownloadButton: View {
    @ObservedObject private var downloadService = DownloadService.shared
    let episode: Episode

    var body: some View {
        Menu {
            switch episode.downloadState {
            case .notDownloaded, .failed:
                Button("Download") {
                    downloadService.startDownload(for: episode)
                }
            case .downloading, .queued:
                Button("Cancel Download", role: .destructive) {
                    downloadService.cancelDownload(for: episode)
                }
            case .downloaded:
                Button("Remove Download", role: .destructive) {
                    downloadService.deleteDownload(for: episode)
                }
            }
        } label: {
            Label {
                Text(downloadLabel)
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: downloadIcon)
                    .symbolEffect(.variableColor.iterative.reversing, options: episode.downloadState == .downloading ? .repeating : .nonRepeating)
                    .symbolEffect(.bounce, value: episode.downloadState == .downloaded)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(SecondaryPillButtonStyle())
        .accessibilityLabel(downloadAccessibilityLabel)
    }

    private var downloadLabel: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "Download"
        case .queued:
            return "Queued"
        case .downloading:
            return "\(Int((episode.downloadProgress * 100).rounded()))%"
        case .downloaded:
            return "Offline"
        case .failed:
            return "Retry"
        }
    }

    private var downloadIcon: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "arrow.down.circle"
        case .queued:
            return "clock.arrow.circlepath"
        case .downloading:
            return "arrow.down.circle.fill"
        case .downloaded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.arrow.trianglehead.2.clockwise"
        }
    }

    private var downloadAccessibilityLabel: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "Download \(episode.title)"
        case .queued:
            return "\(episode.title) is queued for download"
        case .downloading:
            return "Downloading \(episode.title)"
        case .downloaded:
            return "\(episode.title) is downloaded"
        case .failed:
            return "Retry download for \(episode.title)"
        }
    }
}
