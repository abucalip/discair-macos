# Architecture

Paths are relative to the repository root.

## App and Core

| Area | Start here |
| --- | --- |
| App entry point and Sparkle updater | `Sources/DiscairApp/DiscairApp.swift`, `Sources/DiscairApp/Updater.swift` |
| Core networking, profiles, secrets, and errors | `Sources/DiscairCore/` |
| Navidrome / Subsonic client and models | `Sources/DiscairNavidrome/` |
| Librarian API client, discovery, paths, radio, and Playlist Inbox | `Sources/DiscairLibrarian/` |
| Audio playback, queue, cache, EQ, and scrobbling | `Sources/DiscairAudio/` |
| Desktop widget | `Sources/DiscairWidget/` |

## UI

| Area | Start here |
| --- | --- |
| Root shell and render modes | `Sources/DiscairUI/RootView.swift`, `Sources/DiscairUI/RenderMode.swift` |
| Window chrome, navigation, and player bar | `Sources/DiscairUI/Chrome/` |
| View models and state | `Sources/DiscairUI/Model/` |
| Themes and Cupertino presentation | `Sources/DiscairUI/Themes/` |

## Tooling and Contracts

| Area | Start here |
| --- | --- |
| Tests and vendored server fixtures | `Tests/`, `Tests/Fixtures/` |
| Test selection and performance probes | `scripts/select-tests.sh`, `scripts/perf/macos_cheap.sh` |
| Packaging, signing, and release scripts | `Packaging/`, `scripts/bundle.sh`, `scripts/appcast.sh`, `scripts/make-signing-identity.sh` |
| Audio spike and checks executables | `Sources/AudioSpike/`, `Sources/DiscairChecks/` |
| Client contract and design notes | `docs/contracts/MACOS_CLIENT_CONTRACT.md`, `DESIGN.md` (shared server contracts live in [`abucalip/navi-librarian`](https://github.com/abucalip/navi-librarian/tree/main/docs/contracts)) |
