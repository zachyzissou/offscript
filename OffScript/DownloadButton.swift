import SwiftUI

struct DownloadButton: View {
    @ObservedObject private var downloadService = DownloadService.shared
    @State private var isRemoveArmed = false
    let episode: Episode

    var body: some View {
        // Tuner-direction download key — sharp hairline rectangle with mono
        // status text. Function-coded color (signal yellow for actionable
        // states, mode-green when downloaded, record-red on failure).
        Button {
            performPrimaryDownloadAction()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: downloadIcon)
                    .font(.system(size: 11, weight: .semibold))
                TunerLabel(text: downloadLabel.uppercased(), color: downloadColor, size: 10)
            }
            .foregroundStyle(downloadColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(Rectangle().stroke(downloadColor.opacity(0.7), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tunerPress)
        .accessibilityLabel(downloadAccessibilityLabel)
        .accessibilityHint(downloadAccessibilityHint)
    }

    private func performPrimaryDownloadAction() {
        switch episode.downloadState {
        case .notDownloaded, .failed:
            isRemoveArmed = false
            downloadService.startDownload(for: episode)
        case .downloading, .queued:
            isRemoveArmed = false
            downloadService.cancelDownload(for: episode)
        case .downloaded:
            if isRemoveArmed {
                downloadService.deleteDownload(for: episode)
                isRemoveArmed = false
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isRemoveArmed = true
                }
            }
        }
    }

    private var downloadColor: Color {
        switch episode.downloadState {
        case .notDownloaded:
            return .offscriptPaperWhite
        case .queued, .downloading:
            return .offscriptSignalYellow
        case .downloaded:
            if isRemoveArmed { return .offscriptFnRecord }
            return .offscriptFnMode
        case .failed:
            return .offscriptFnRecord
        }
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
            if isRemoveArmed { return "Remove?" }
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
            if isRemoveArmed { return "trash" }
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

    private var downloadAccessibilityHint: String {
        switch episode.downloadState {
        case .notDownloaded:
            return "Double-tap to download this episode."
        case .queued:
            return "Double-tap to cancel the queued download."
        case .downloading:
            return "Double-tap to cancel the download."
        case .downloaded:
            return isRemoveArmed
                ? "Double-tap again to remove the downloaded file."
                : "Double-tap to arm removal of the downloaded file."
        case .failed:
            return "Double-tap to retry the download."
        }
    }
}
