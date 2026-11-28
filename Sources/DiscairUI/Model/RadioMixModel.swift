import DiscairAudio
import DiscairCore
import DiscairLibrarian
import DiscairNavidrome
import Foundation
import Observation

@MainActor @Observable
final class RadioMixModel {
    private(set) var isPresented = false
    private(set) var request: RadioMixRequest?
    private(set) var mix: RadioMix?
    private(set) var loading = false
    private(set) var notice: String?
    private(set) var downloads: [Int: GetState] = [:]
    private var keys: [Int: PlaylistInboxAcquisitionKey] = [:]
    private var librarian: LibrarianClient?
    private var scope = UUID()
    private var refreshID = UUID()
    var isConnected: Bool { librarian != nil }

    func configure(librarian: LibrarianClient?) {
        self.librarian = librarian
        close()
    }

    func open(_ request: RadioMixRequest) {
        close()
        self.request = request
        isPresented = true
    }

    func close() {
        scope = UUID(); refreshID = UUID()
        isPresented = false; request = nil; mix = nil; loading = false; notice = nil
        downloads = [:]; keys = [:]
    }

    func generate(_ request: RadioMixRequest, player: PlayerModel? = nil) async {
        guard let librarian, isPresented else { return }
        scope = UUID(); refreshID = UUID()
        let scope = scope
        self.request = request
        mix = nil; downloads = [:]; keys = [:]; notice = nil; loading = true
        do {
            let result = try await librarian.previewRadioMix(request)
            guard self.scope == scope, !Task.isCancelled else { return }
            mix = result
            loading = false
            notice = Self.explanation(result)
            if request.kind == .artist { player?.playInOrder(Self.playbackItems(result)) }
        } catch {
            guard self.scope == scope, !Task.isCancelled else { return }
            loading = false
            notice = ErrorMapping.map(error).summary
        }
    }

    func refresh() async {
        guard let librarian, let id = mix?.previewID, !loading else { return }
        let scope = scope, refresh = UUID()
        refreshID = refresh
        do {
            let result = try await librarian.radioMix(id: id)
            guard self.scope == scope, refreshID == refresh, !Task.isCancelled else { return }
            mix = result
            notice = Self.explanation(result)
        } catch {
            guard self.scope == scope, refreshID == refresh, !Task.isCancelled else { return }
            notice = ErrorMapping.map(error).summary
        }
    }

    func downloadState(_ track: PlaylistInboxTrack, jobs: [Acquisition]) -> GetState {
        if track.matchState == "owned" { return .requested("Owned") }
        if let attempt = downloads[track.position] {
            switch attempt {
            case .pending, .failed: return attempt
            default: break
            }
        }
        if let key = keys[track.position] ?? track.acquisitionKey,
           let job = jobs.first(where: { $0.artist == key.artist && $0.album == key.jobAlbum }) {
            if job.status == "imported" { return .requested("Imported · waiting for library scan") }
            if Self.retryable(job.status) { return .failed(AcquisitionModel.statusText(job)) }
            return AcquisitionModel.describe(job)
        }
        if let status = track.acquisitionStatus {
            if status == "imported" { return .requested("Imported · waiting for library scan") }
            return Self.retryable(status) ? .failed(status.replacingOccurrences(of: "_", with: " ")) : .requested(status)
        }
        return downloads[track.position] ?? .idle
    }

    func download(position: Int, jobs: [Acquisition]) async {
        guard let librarian, let mix, mix.state == "ready", mix.ownedCount != nil,
              mix.kind == "discovery", let id = mix.previewID,
              let row = mix.tracks.first(where: { $0.position == position }), row.matchState == "missing" else { return }
        switch downloadState(row, jobs: jobs) {
        case .pending, .requested: return
        case .idle, .failed: break
        }
        let scope = scope
        downloads[position] = .pending
        do {
            let result = try await librarian.downloadRadioMixTrack(id: id, position: position)
            guard self.scope == scope, !Task.isCancelled else { return }
            if let artist = result.artist, let album = result.jobAlbum {
                keys[position] = PlaylistInboxAcquisitionKey(artist: artist, jobAlbum: album)
            }
            switch result.status {
            case "owned": downloads[position] = .requested("Refreshing ownership…")
            case "imported": downloads[position] = .requested("Imported · waiting for library scan")
            case "already_in_progress", "importing": downloads[position] = .requested(result.message ?? "Requested")
            default:
                downloads[position] = result.ok && result.status.map(Self.retryable) != true
                    ? .requested(result.message ?? "Requested") : .failed(result.message ?? "Download unavailable.")
            }
            await refresh()
        } catch {
            guard self.scope == scope, !Task.isCancelled else { return }
            downloads[position] = .failed(ErrorMapping.map(error).summary)
        }
    }

    static func playbackItems(_ mix: RadioMix) -> [QueueItem] {
        guard mix.state == "ready", let count = mix.ownedCount, count > 0 else { return [] }
        return mix.tracks.compactMap { track in
            guard track.matchState == "owned", let id = track.songID, isValidSongID(id) else { return nil }
            return QueueItem(songID: id, title: track.displayTitle, artist: track.artist ?? "",
                             album: track.album ?? "", duration: Double(max(0, track.durationMs ?? 0)) / 1000,
                             mbid: track.recordingMBID)
        }
    }

    private static func explanation(_ mix: RadioMix) -> String? {
        switch mix.state {
        case "unconfigured": "Connect ListenBrainz in Settings to generate mixes."
        case "index_unavailable": "Library ownership is unavailable. Try again after the library has indexed."
        case "empty": "No matching tracks were found. Try another seed or mode."
        case "ready": mix.ownedCount == nil ? "Ownership unavailable. Refresh status before playing or downloading." : nil
        default: "The mix is unavailable. Try again."
        }
    }

    private static func retryable(_ status: String) -> Bool {
        ["no_matches", "queue_failed", "settings_required", "slskd_error", "monitor_error", "monitor_timeout",
         "monitor_recovery_failed", "source_switch_failed", "recovery_unavailable", "download_failed",
         "download_complete_move_failed", "dismissed"].contains(status)
    }
}
