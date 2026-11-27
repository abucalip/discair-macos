# Discair for Mac — Agent Instructions

This repository (`abucalip/discair-macos`) holds the native macOS client for Discair.

## Contracts & shared references

- Client contract: [`docs/contracts/MACOS_CLIENT_CONTRACT.md`](docs/contracts/MACOS_CLIENT_CONTRACT.md)
- Design notes: [`DESIGN.md`](DESIGN.md)
- Shared server API contracts (`SERVER_V2_CONTRACT.md`, `PLAYLIST_INBOX_CONTRACT.md`, `RADIO_PLAYBACK_CONTRACT.md`, `SEARCH_CONTRACT.md`) live in [`abucalip/navi-librarian`](https://github.com/abucalip/navi-librarian/tree/main/docs/contracts).
- Vendored server fixtures live under `Tests/Fixtures/`. Keep DTOs aligned with recorded fixtures; do not invent endpoints or fields.

## Hard rules

- Call the person directing the project **"the owner"** in docs, commits, PRs, and comments. Never use their name or handle.
- Never print, log, or commit credentials, tokens, or salts.
- Keep domain logic server-side; the macOS UI only presents it.
- **No continuous or looping SwiftUI motion:** do not use `TimelineView(.animation)`, `.repeatForever`, or repeating symbol effects. Use Core Animation / AppKit when continuous motion is required, and measure CPU with `scripts/perf/macos_cheap.sh`.

## Testing (SwiftPM)

- **Never run the full test suite.** Run only tests for code you changed:
  - Choose targets with `scripts/select-tests.sh`
  - Run focused suites with `swift test --filter <TargetOrSuite>`
  - Set `DISCAIR_SKIP_KEYCHAIN_TESTS=1` when no unlocked login keychain is available.
- Report exactly what ran and what did not. Never claim a pass that was not run.

## Change cycle

- Branch from current `main`, make the smallest reviewable change with regression tests, and open a focused PR.
- End the task after pushing and creating/updating the PR; do not wait for or poll CI unless asked.
