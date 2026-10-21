# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

macOS cleaner app ("Cleaner", provisional name), SwiftUI, macOS 13+, pt-BR base with en. Distributed outside the Mac App Store (no App Sandbox, Hardened Runtime). Not signed or published yet.

## Commands

- Core tests (fast, no Xcode needed): `swift test`
- Single test: `swift test --filter RestorerTests/testConflictSuffixKeepsBoth`
- App build: `cd App && xcodegen generate && xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath ../.build/xcode build`
- `App/Cleaner.xcodeproj` is generated from `App/project.yml` (xcodegen) and gitignored. Edit the yml, not the project.
- `scripts/release.sh --dry-run` validates the signing/notarization flow; real runs need `DEVELOPER_ID_APP`, `TEAM_ID`, `NOTARY_PROFILE` (see `RELEASE.md`). Do not run it for real unless asked.

## Architecture

Two parts: `Sources/CleanerCore` (SwiftPM library, all logic, all tests) and `App/Sources` (thin SwiftUI layer over it).

Layers in Core: `Rules` (PathPolicy) → `Quarantine` (QuarantineService) → `Sessions` (manifest + store) → `Restore` / `Expiry`; `Modules` produce candidates; `Engine` wires everything.

Invariants that span several files:

- **Only `QuarantineService` moves files; only `ExpiryService` deletes.** Modules (`CleanupModule`: `scan()`, `clean(items:)`) only produce `CleanItem`s. Never add `rm`/`removeItem` elsewhere.
- **Every path decision goes through `PathPolicy.check(url, module:)`**: per-module allowlist, global denylist (denylist wins), parent resolved with realpath, symlinks must stay in scope, `deepNameCheck` blocks folders containing WhatsApp databases. Restore re-checks `originalPath` with the same policy.
- **Manifest is written atomically before any move**, status updated after each move (`pending` → `moved`/`failed`). Crash-safe: a `pending` item whose quarantine copy exists is still restorable.
- **`ManifestValidator` distrusts the manifest on disk**: `quarantinePath` must be exactly `<quarantine root>/<sessionID>/<itemID>`, and `originalPath` must pass the policy. Tampered entries are rejected, never restored or deleted.
- **Moves use `renamex_np(RENAME_EXCL)` only**: same volume, no copy fallback, never overwrites. Quarantine is per volume (`~/Library/Application Support/Cleaner/Quarentena/` on the home volume, `<volume>/.Cleaner-Quarentena/` on external disks). Hence no free-space check.
- "Replace" on restore conflict quarantines the current item into a new session instead of deleting it. "Delete permanently" is quarantine with zero retention followed by immediate expiry.
- Use `FS.normalize`, not `URL.standardizedFileURL`: the latter strips `/private` only when the path exists, which breaks path comparisons after an item is moved.
- Name, bundle ID and folder names live in `AppConfig`; `App/project.yml` repeats the bundle ID and must be changed together. `AppConfig.whatsAppRoot` is configurable (stored in UserDefaults by the app, applied on next launch via `AppSettings.engine`).

## Testing

Tests never touch the real home. `Tests/CleanerCoreTests/TestEnv.swift` (`Env`) builds a fake home in a temp dir and an `Engine` over it; tests that need other volumes inject a fake `VolumeResolver`, and `beforeMove` hooks into `Engine` to observe state mid-operation. Never run a real cleanup on the developer's machine when testing manually; use dry run or fake folders.

## App layer

Each sidebar section is a View + ViewModel pair sharing one `AppSettings.engine`. `ContentView` owns the ViewModels, the Full Disk Access onboarding sheet and the warning banner (`FullDiskAccess.isGranted()` probes `TCC.db`). Strings are SwiftUI literals / `String(localized:)` backed by `App/Sources/Localizable.xcstrings`; new UI text needs an `en` entry there. Messages coming from Core (skip reasons, errors) are still pt-BR only.
