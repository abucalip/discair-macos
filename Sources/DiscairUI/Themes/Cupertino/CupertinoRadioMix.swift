import DiscairLibrarian
import SwiftUI

struct CupertinoMixShelf: View {
    let state: AppState
    @State private var tag = ""
    @State private var seedNotice: String?
    @State private var mode = "easy"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discover a mix").font(CU.title(22)).accessibilityAddTraits(.isHeader)
            Text("Explore ListenBrainz recommendations. Play owned tracks and download missing recordings.")
                .foregroundStyle(CU.textSecondary)
            ArtistPickerField(state: state, style: .cupertino, prompt: "Choose a library artist") { artist in
                if let mbid = artist.musicBrainzID, UUID(uuidString: mbid) != nil {
                    seedNotice = nil
                    state.radioMix.open(.init(kind: .discovery, artistMBID: mbid, mode: mode))
                } else {
                    seedNotice = "This artist has no MusicBrainz ID. Enter a tag to discover a mix."
                }
            }
            HStack {
                TextField("Tag, for example jazz", text: $tag)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Discovery mix tag")
                    .onSubmit { openTag() }
                Picker("Mode", selection: $mode) {
                    Text("Easy").tag("easy")
                    Text("Medium").tag("medium")
                    Text("Hard").tag("hard")
                }.fixedSize()
                Button("Discover a mix") { openTag() }
                    .buttonStyle(CapsuleButtonStyle(small: true))
                    .disabled(!state.radioMix.isConnected || tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let seedNotice { Text(seedNotice).foregroundStyle(CU.textSecondary) }
            if !state.radioMix.isConnected {
                Text("Connect to Librarian to generate a mix.").foregroundStyle(CU.textSecondary)
            }
        }
    }

    private func openTag() {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, state.radioMix.isConnected else { return }
        state.radioMix.open(.init(kind: .discovery, tag: value, mode: mode))
    }
}

struct CupertinoRadioMix: View {
    let state: AppState
    private var model: RadioMixModel { state.radioMix }
    @State private var familiarity = "familiar"
    @State private var mode = "easy"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.request?.kind == .artist ? "Artist Radio" : "Discovery Mix")
                    .font(CU.title(26)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { model.close() }.keyboardShortcut(.cancelAction)
            }
            Text("ListenBrainz · Library playback and discovery").foregroundStyle(CU.textSecondary)
            controls
            if model.loading {
                HStack { ProgressView().controlSize(.small); Text("Generating mix…") }
            }
            if let notice = model.notice { Text(notice).foregroundStyle(CU.textSecondary) }
            if let mix = model.mix {
                let songs = RadioMixModel.playbackItems(mix)
                HStack {
                    Text(mix.ownedCount.map { "\($0) of \(mix.totalCount ?? mix.tracks.count) owned" } ?? "Ownership unavailable")
                        .foregroundStyle(CU.textSecondary)
                    Spacer()
                    Button("Play owned tracks") { state.player.playInOrder(songs) }
                        .disabled(songs.isEmpty)
                    Button("Refresh status") {
                        Task { await state.acquisition.refresh(); await model.refresh() }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(mix.tracks) { row in track(row, discovery: mix.kind == "discovery") }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24).frame(minWidth: 600, idealWidth: 700, minHeight: 480, idealHeight: 600)
        .background(CU.content)
        .task {
            if let request = model.request {
                familiarity = request.familiarity; mode = request.mode
                await model.generate(request, player: state.player)
                await model.refresh()
            }
        }
        .onChange(of: state.acquisition.jobs) { _, _ in Task { await model.refresh() } }
    }

    private var controls: some View {
        HStack {
            if model.request?.kind == .artist {
                Picker("Familiarity", selection: $familiarity) {
                    Text("Familiar").tag("familiar")
                    Text("Explore").tag("explore")
                    Text("Deep cuts").tag("deep_cuts")
                }
            } else {
                Picker("Mode", selection: $mode) {
                    Text("Easy").tag("easy")
                    Text("Medium").tag("medium")
                    Text("Hard").tag("hard")
                }
            }
            Button(model.request?.kind == .artist ? "Start Artist Radio" : "Generate mix") {
                guard let request = model.request else { return }
                Task {
                    await model.generate(.init(kind: request.kind, artistMBID: request.artistMBID,
                                               tag: request.tag, familiarity: familiarity, mode: mode), player: state.player)
                    await model.refresh()
                }
            }
            .disabled(model.loading || !model.isConnected)
        }
    }

    private func track(_ row: PlaylistInboxTrack, discovery: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(row.position + 1)").monospacedDigit().foregroundStyle(CU.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayTitle).fontWeight(.medium)
                Text([row.artist, row.album].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(CU.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ownership(row)).font(.callout).foregroundStyle(CU.textSecondary)
                if discovery, row.matchState == "missing" { download(row) }
            }
        }
        .padding(10).background(CU.bgPanel, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func ownership(_ row: PlaylistInboxTrack) -> String {
        switch row.matchState {
        case "owned": "Owned"
        case "missing": "Missing"
        case "ambiguous": "Ambiguous match · download unavailable"
        default: "Ownership unavailable"
        }
    }

    @ViewBuilder private func download(_ row: PlaylistInboxTrack) -> some View {
        switch model.downloadState(row, jobs: state.acquisition.jobs) {
        case .idle: downloadButton("Download", row)
        case .pending: Text("Requesting…").font(.callout)
        case .requested(let message): Text(message).font(.callout)
        case .failed(let message):
            Text(message).font(.callout)
            downloadButton("Retry", row)
        }
    }

    private func downloadButton(_ title: String, _ row: PlaylistInboxTrack) -> some View {
        Button(title) {
            Task {
                await model.download(position: row.position, jobs: state.acquisition.jobs)
                await state.acquisition.refresh()
            }
        }
        .disabled(!model.isConnected)
        .accessibilityLabel("\(title) \(row.displayTitle), track \(row.position + 1)")
    }
}
