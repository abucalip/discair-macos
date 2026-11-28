import DiscairAudio
import DiscairCore
import DiscairLibrarian
import DiscairNavidrome
import Foundation
import Testing
@testable import DiscairUI

private func mixFixture() throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../Fixtures/radio_mix_discovery.json").standardized
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private actor MixTransport: HTTPTransport {
    private(set) var requests: [String] = []
    private(set) var bodies: [Data?] = []
    private var payload: [String: Any]
    private var status = 200
    private var downloadResult = #"{"ok":true,"status":"requested","artist":"Band","job_album":"Two (song on Resolved)"}"#
    private var hold = false
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var waiting = false
    private var requireLogin: Bool

    init(requireLogin: Bool = false) throws { payload = try mixFixture(); self.requireLogin = requireLogin }
    func setState(_ state: String, owned: Int? = 2, kind: String = "discovery") {
        payload["state"] = state; payload["owned_count"] = owned.map { $0 as Any } ?? NSNull(); payload["kind"] = kind
    }
    func fail(_ status: Int) { self.status = status }
    func outcome(_ body: String) { downloadResult = body }
    func holdNext() { hold = true }
    func waitUntilHeld() async { if !waiting { await withCheckedContinuation { started = $0 } } }
    func release() { held?.resume(); held = nil; waiting = false }
    func confirmOwned() {
        var tracks = payload["tracks"] as! [[String: Any]]
        tracks[1]["match_state"] = "owned"; tracks[1]["song_id"] = "two"
        payload["tracks"] = tracks; payload["owned_count"] = 3
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        requests.append("\(request.httpMethod ?? "") \(url.path)")
        bodies.append(request.httpBody)
        let body: Data
        let code: Int
        if requireLogin {
            requireLogin = false; code = 401; body = Data()
        } else if url.path == "/api/auth/login" {
            code = 200; body = Data()
        } else {
            code = status
            if status != 200 { body = Data(#"{"detail":"Mix temporarily unavailable."}"#.utf8) }
            else if url.path.hasSuffix("/download") { body = Data(downloadResult.utf8) }
            else { body = try JSONSerialization.data(withJSONObject: payload) }
            if hold {
                hold = false; waiting = true
                await withCheckedContinuation { continuation in
                    held = continuation; started?.resume(); started = nil
                }
            }
        }
        return (body, try #require(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)))
    }

    nonisolated func client() throws -> LibrarianClient {
        try LibrarianClient(baseURL: URL(string: "https://lib.example.ts.net")!,
                            credential: Credential(username: "owner", password: "fixture"), transport: self)
    }
}

@MainActor struct RadioMixTests {
    private let request = RadioMixRequest(kind: .discovery, tag: "jazz", mode: "hard")

    private func loaded(_ transport: MixTransport) async throws -> RadioMixModel {
        let model = RadioMixModel()
        model.configure(librarian: try transport.client())
        model.open(request)
        await model.generate(request)
        return model
    }

    @Test func authenticatedPreviewAndStoredDownloadNeverSendEditableMetadata() async throws {
        let transport = try MixTransport(requireLogin: true)
        let model = try await loaded(transport)
        let mix = try #require(model.mix)
        #expect(mix.tracks.map(\.position) == [0, 1, 2, 3, 4])
        #expect(RadioMixModel.playbackItems(mix).map(\.songID) == ["one", "one"])
        #expect(RadioMixModel.playbackItems(mix).first?.duration == 180)
        await model.download(position: 1, jobs: [])
        let paths = await transport.requests
        #expect(paths == ["POST /api/radio-mixes/preview", "POST /api/auth/login", "POST /api/radio-mixes/preview",
                          "POST /api/radio-mixes/\(String(repeating: "a", count: 32))/tracks/1/download",
                          "GET /api/radio-mixes/\(String(repeating: "a", count: 32))"])
        let bodies = await transport.bodies
        let encoded = try #require(bodies[0])
        let body = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(body["kind"] as? String == "discovery")
        #expect(body["tag"] as? String == "jazz")
        #expect(body["mode"] as? String == "hard")
        #expect(body["artist_mbid"] == nil)
        #expect(bodies[3] == nil)
        await model.download(position: 1, jobs: [])
        #expect(await transport.requests == paths)
    }

    @Test(arguments: ["empty", "unconfigured", "index_unavailable", "ready"])
    func unavailableOwnershipAndEmptyResultsPreserveQueue(_ state: String) async throws {
        let transport = try MixTransport()
        await transport.setState(state, owned: state == "ready" ? nil : 0, kind: "artist")
        let model = RadioMixModel()
        model.configure(librarian: try transport.client())
        let request = RadioMixRequest(kind: .artist, artistMBID: "51fba9f6-40b4-4be9-8ea1-251b6db085a4")
        model.open(request)
        let player = PlayerModel(output: FakeOutput(), defaults: UserDefaults(suiteName: "discair-lb21-\(UUID().uuidString)")!)
        player.playInOrder([QueueItem(songID: "existing", title: "Existing", artist: "Band")])
        player.toggleShuffle()
        await model.generate(request, player: player)
        #expect(player.queue.items.map(\.songID) == ["existing"])
        #expect(player.queue.shuffle)
        #expect(model.notice != nil)
    }

    @Test func artistSuccessStartsOrderedQueueAndHTTPFailurePreservesIt() async throws {
        let transport = try MixTransport()
        await transport.setState("ready", kind: "artist")
        let model = RadioMixModel()
        model.configure(librarian: try transport.client())
        let request = RadioMixRequest(kind: .artist, artistMBID: "51fba9f6-40b4-4be9-8ea1-251b6db085a4", familiarity: "deep_cuts")
        model.open(request)
        let player = PlayerModel(output: FakeOutput(), defaults: UserDefaults(suiteName: "discair-lb21-\(UUID().uuidString)")!)
        await model.generate(request, player: player)
        #expect(player.queue.items.map(\.songID) == ["one", "one"])
        #expect(!player.queue.shuffle)
        await transport.fail(503)
        await model.generate(request, player: player)
        #expect(player.queue.items.map(\.songID) == ["one", "one"])
        #expect(model.notice != nil)
        #expect(!model.loading)
    }

    @Test func onlyMissingRowsDownloadAndImportedWaitsForIndex() async throws {
        let transport = try MixTransport()
        let model = try await loaded(transport)
        let baseline = await transport.requests.count
        for position in [0, 2, 3, 4, 99] { await model.download(position: position, jobs: []) }
        #expect(await transport.requests.count == baseline)
        await transport.outcome(#"{"ok":false,"status":"imported","artist":"Band","job_album":"Two (song on Resolved)"}"#)
        await model.download(position: 1, jobs: [])
        let row = try #require(model.mix?.tracks[1])
        #expect(model.downloadState(row, jobs: []) == .requested("Imported · waiting for library scan"))
        let beforeScan = try #require(model.mix)
        #expect(RadioMixModel.playbackItems(beforeScan).map(\.songID) == ["one", "one"])
        await transport.confirmOwned()
        await model.refresh()
        let afterScan = try #require(model.mix)
        #expect(RadioMixModel.playbackItems(afterScan).map(\.songID) == ["one", "two", "one"])
    }

    @Test func serverRefusalCanRetryAndRefreshFailureRetainsRows() async throws {
        let transport = try MixTransport()
        let model = try await loaded(transport)
        await transport.fail(409)
        await model.download(position: 1, jobs: [])
        let row = try #require(model.mix?.tracks[1])
        guard case .failed = model.downloadState(row, jobs: []) else { Issue.record("Refusal hidden"); return }
        await model.refresh()
        #expect(model.mix?.tracks.count == 5)
        #expect(model.notice != nil)
        await transport.fail(200)
        await model.download(position: 1, jobs: [])
        guard case .requested = model.downloadState(row, jobs: []) else { Issue.record("Retry did not succeed"); return }
    }

    @Test func profileChangeDropsLatePreviewWithoutPlaying() async throws {
        let transport = try MixTransport()
        let model = RadioMixModel()
        let request = RadioMixRequest(kind: .artist, artistMBID: "51fba9f6-40b4-4be9-8ea1-251b6db085a4")
        model.configure(librarian: try transport.client()); model.open(request)
        let player = PlayerModel(output: FakeOutput(), defaults: UserDefaults(suiteName: "discair-lb21-\(UUID().uuidString)")!)
        await transport.holdNext()
        let pending = Task { await model.generate(request, player: player) }
        await transport.waitUntilHeld()
        model.configure(librarian: nil)
        await transport.release(); await pending.value
        #expect(model.mix == nil)
        #expect(!model.isPresented)
        #expect(!model.loading)
        #expect(player.queue.items.isEmpty)
    }

    @Test func duplicateDownloadsCoalesceAndCloseDropsLateResult() async throws {
        let transport = try MixTransport()
        let model = try await loaded(transport)
        await transport.holdNext()
        let pending = Task { await model.download(position: 1, jobs: []) }
        await transport.waitUntilHeld()
        let count = await transport.requests.count
        await model.download(position: 1, jobs: [])
        #expect(await transport.requests.count == count)
        model.close()
        await transport.release(); await pending.value
        #expect(model.downloads.isEmpty)
        #expect(model.mix == nil)
    }

    @Test func artistSeedRetainsNavidromeMusicBrainzIdentity() {
        let library = LibraryModel()
        let mbid = "51fba9f6-40b4-4be9-8ea1-251b6db085a4"
        library.apply(newest: [], first: [], artists: [
            NavidromeArtist(id: "artist-1", name: "Band", albumCount: 1, coverArt: nil, musicBrainzId: mbid),
        ], picks: [])
        #expect(library.artist(named: "Band")?.musicBrainzID == mbid)
    }

    @Test func malformedSongIDsNeverEnterPlayback() throws {
        var payload = try mixFixture()
        var rows = try #require(payload["tracks"] as? [[String: Any]])
        rows[0]["song_id"] = "../unsafe"
        rows[2]["song_id"] = ""
        payload["tracks"] = rows
        let mix = try JSONDecoder().decode(RadioMix.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(RadioMixModel.playbackItems(mix).isEmpty)
    }

    @Test func regenerationDiscardsAnOlderSuccessfulResponse() async throws {
        let transport = try MixTransport()
        let model = RadioMixModel()
        model.configure(librarian: try transport.client()); model.open(request)
        await transport.holdNext()
        let old = Task { await model.generate(request) }
        await transport.waitUntilHeld()
        await transport.setState("empty", owned: 0)
        await model.generate(.init(kind: .discovery, tag: "ambient"))
        await transport.release(); await old.value
        #expect(model.mix?.state == "empty")
        #expect(model.request?.tag == "ambient")
    }

    @Test func sharedProgressUsesServerJobIdentityAndAllowsFailedJobRetry() async throws {
        let transport = try MixTransport()
        let model = try await loaded(transport)
        await model.download(position: 1, jobs: [])
        let row = try #require(model.mix?.tracks[1])
        func job(_ status: String, album: String = "Two (song on Resolved)") throws -> Acquisition {
            let data = try JSONSerialization.data(withJSONObject: [
                "artist": "Band", "album": album, "status": status,
                "details": ["live_progress": ["available": true, "percent": 42]],
            ])
            return try JSONDecoder().decode(Acquisition.self, from: data)
        }
        #expect(model.downloadState(row, jobs: [try job("downloading")]) == .requested("Downloading 42%"))
        #expect(model.downloadState(row, jobs: [try job("imported")]) == .requested("Imported · waiting for library scan"))
        #expect(model.downloadState(row, jobs: [try job("downloading", album: "Unrelated")]) == .requested("Requested"))
        let failed = try job("no_matches")
        guard case .failed = model.downloadState(row, jobs: [failed]) else { Issue.record("Failure hidden"); return }
        let before = await transport.requests.count
        await model.download(position: 1, jobs: [failed])
        #expect(await transport.requests.count == before + 2)
    }

    @Test func rendersDiscoveryMixAndDiscoverShelf() async throws {
        let transport = try MixTransport()
        let state = AppState(screen: .discover, output: FakeOutput())
        state.radioMix.configure(librarian: try transport.client())
        state.radioMix.open(request)
        await state.radioMix.generate(request)
        let renderer = CupertinoPagesRenderTests()
        try renderer.render("radio-mix", width: 700, height: 600, CupertinoRadioMix(state: state)) { _ in }
        try renderer.render("radio-mix-shelf", width: 700, height: 300, CupertinoMixShelf(state: state)) { _ in }
    }
}
