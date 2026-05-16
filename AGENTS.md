# AGENTS.md

Context for AI agents working in this repository.

## What this is

AuthBand is a watch-first TOTP authenticator app for Apple Watch with an iPhone companion. Source code is on GitHub at https://github.com/antonlukin/auth-band. Currently a proof of concept, not yet shipped.

- **Min targets:** iOS 17.0, watchOS 11.6
- **Stack:** Swift, SwiftUI, native Apple frameworks only (CryptoKit, WatchConnectivity, LocalAuthentication, AVFoundation, PhotosUI, CoreImage). No third-party dependencies.
- **Storage:** Keychain (`kSecClassGenericPassword`, service `com.antonlukin.authband.accounts`, `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`). Single JSON blob with all accounts.
- **Sync:** WatchConnectivity (`updateApplicationContext` + opportunistic `sendMessage`), payload is a versioned `SyncEnvelope` with `maxAccounts=200` cap.
- **No networking, no analytics, no cloud, no third-party SDKs.**

## Repo layout

```
AuthBand/                         # repo root, contains the Xcode project
├── AuthBand.xcodeproj            # the project
├── AuthBand/                     # iPhone target (primary)
│   ├── AuthBandApp.swift         # @main; AppLockManager (LocalAuthentication gate)
│   ├── ContentView.swift         # root list of accounts + search + toolbar
│   ├── AccountRow.swift          # row UI (issuer, name, code, tap-to-copy)
│   ├── AddAccountView.swift      # manual entry + scan QR + photo import
│   ├── EditAccountView.swift     # rename issuer/account
│   ├── SettingsView.swift        # lock toggle, sync button, delete-all, about
│   ├── QRCodeScannerView.swift   # live camera scanner (AVFoundation)
│   ├── QRImageDecoder.swift      # CIDetector wrapper for QR-in-image
│   ├── OTPImport.swift           # OTPQRCodeParser, OTPAuthURLParser,
│   │                             #   GoogleAuthenticatorMigrationParser,
│   │                             #   OTPImportError
│   ├── ProtobufReader.swift      # hand-rolled protobuf reader (migration QR)
│   ├── CircularCountdownView.swift
│   ├── Assets.xcassets/          # AppIcon, AccentColor
│   └── Localizable.xcstrings     # String Catalog (iOS strings)
├── AuthBandWatch/                # Apple Watch target (satellite)
│   ├── AuthBandWatchApp.swift    # @main; WatchPrivacyOverlay on scenePhase
│   ├── WatchContentView.swift    # NavigationStack + List(accounts)
│   ├── WatchAccountRow.swift     # row UI (compact)
│   ├── OTPAccount.swift          # shared model
│   ├── TOTPGenerator.swift       # shared HMAC-SHA1 generator + Base32
│   ├── AccountSyncStore.swift    # @MainActor store, Keychain, WCSession
│   ├── Assets.xcassets/          # AppIcon, AccentColor
│   └── Localizable.xcstrings     # String Catalog (Watch strings)
├── AuthBandTests/                # Swift Testing test target (hosted in iOS app)
│   ├── TOTPGeneratorTests.swift              # RFC 6238 vectors
│   ├── OTPAuthURLParserTests.swift           # parser + dispatch + errors
│   ├── ProtobufReaderTests.swift             # low-level wire format
│   ├── GoogleAuthenticatorMigrationParserTests.swift  # migration end-to-end
│   └── QRImageDecoderTests.swift             # encode/decode roundtrip
├── AGENTS.md
└── README.md
```

**Quirk to know:** `OTPAccount.swift`, `TOTPGenerator.swift`, `AccountSyncStore.swift` physically live in `AuthBandWatch/` but the iPhone target compiles them too — both targets share the same `PBXFileReference` entries. Don't be surprised when iOS uses a file from the Watch folder; that's intentional.

## Build & test

Use absolute paths in `-project` because shell `cwd` can drift across renames or stashes.

iPhone build:
```
xcodebuild -project /Users/lukin/Work/watch-auth/AuthBand/AuthBand.xcodeproj -scheme AuthBand -configuration Debug -sdk iphoneos -derivedDataPath /Users/lukin/Work/watch-auth/AuthBand/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Watch build:
```
xcodebuild -project /Users/lukin/Work/watch-auth/AuthBand/AuthBand.xcodeproj -scheme AuthBandWatch -configuration Debug -sdk watchos -derivedDataPath /Users/lukin/Work/watch-auth/AuthBand/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Tests (iPhone 17 simulator):
```
xcodebuild -project /Users/lukin/Work/watch-auth/AuthBand/AuthBand.xcodeproj -scheme AuthBand -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /Users/lukin/Work/watch-auth/AuthBand/DerivedData CODE_SIGNING_ALLOWED=NO test
```

CoreSimulator warnings in CLI output are normal. Trust `BUILD SUCCEEDED` / `TEST SUCCEEDED`.

## Conventions

### Code style
- Small iterations. Each change should be reviewable and testable on its own.
- No premature abstraction. Don't add protocols / managers / coordinators before there are two concrete callers.
- Prefer editing existing files over creating new ones.
- Default to writing no comments. Only add when the *why* is non-obvious.

### Watch UI is sensitive
- Don't touch the watchOS UI without explicit user request. iPhone UI changes are fair game.

### Localization
- All user-facing strings go through `String(localized: "...", comment: "...")` or SwiftUI `Text("literal")` (which uses `LocalizedStringKey` automatically).
- Both targets have `Localizable.xcstrings`. The Swift compiler extracts strings into `.stringsdata`; opening the catalog in Xcode IDE syncs them. Plurals are configured in the catalog UI, not in code.

### Git workflow
- Branch: `main`. Remote: `git@github.com:antonlukin/auth-band.git`.
- Commits are made by the operator; do not push without explicit permission.
- Force-pushes need especially explicit authorization (history was rewritten once already).
- `.claude/` is gitignored (Claude Code session files should never be committed).

### pbxproj
- UUID prefixes: `1A...` Watch target, `2B...` iPhone target, `3C...` test target.
- Asset catalogs (`Assets.xcassets`) and string catalogs (`Localizable.xcstrings`) go into the Resources build phase. Swift files go into Sources.
- Need both `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor` for icon + accent color extraction.

## Security model (summary)

- TOTP secrets in Keychain, `WhenPasscodeSetThisDeviceOnly`. Loss of device passcode purges the keychain item.
- LocalAuthentication (`deviceOwnerAuthentication`) gates app on launch / foreground return. Lock screen stays up if device has no passcode at all.
- Clipboard `UIPasteboard.setItems(.expirationDate:)` capped at `min(period - elapsed, 30s)` so OTP codes don't linger.
- QR input validated: `digits ∈ {6,7,8}`, `period ∈ 15...300`, algorithm must be SHA1, secret must be valid Base32. Pathological inputs throw `OTPImportError`.
- Privacy overlays (lock screen + scene-phase shield) cover content when app is inactive or backgrounded.
- WatchConnectivity payload is wrapped in `SyncEnvelope { version, sentAt, accounts }`. Watch rejects unknown versions or >200 accounts.
- No network calls anywhere. No analytics. No third-party SDKs. No data leaves the device pair.

A full security audit was performed in May 2026; results and addressed findings are in the git history.

## What to look at first

- `AuthBand/ContentView.swift` — entry point for iPhone UI logic
- `AuthBandWatch/AccountSyncStore.swift` — single source of state, shared between targets, `@MainActor`-isolated
- `AuthBand/OTPImport.swift` + `ProtobufReader.swift` — untrusted-input parsing, well tested
- `AuthBandTests/` — every change to parsers / generator should keep these green
