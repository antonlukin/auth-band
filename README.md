# AuthBand

A TOTP authenticator for Apple Watch with an iPhone companion. Add accounts on the phone; codes live on your wrist.

iOS 17.0+ / watchOS 11.6+. Built with SwiftUI and native Apple frameworks only.

## What it does

- Stores TOTP secrets in the Keychain
- Manual account entry, single-account `otpauth://` QR scan, Google Authenticator migration QR (`otpauth-migration://offline?...`), and bulk import from screenshots in the photo library
- Generates RFC 6238 TOTP codes locally on both iPhone and Apple Watch (HMAC-SHA1, verified against RFC test vectors)
- Syncs the account list to a paired Apple Watch over `WatchConnectivity`
- Face ID / Touch ID / passcode gate on the iPhone, plus a privacy shield when the app is sent to the background

## Security & privacy

The whole point of an authenticator is custody of secrets, so this matters.

**No network. No cloud. No telemetry.** AuthBand makes zero network requests of any kind. There is no backend, no analytics, no crash reporting SDK, no remote feature flags. Nothing about your accounts ever leaves your devices. The only data leaving the iPhone is the encrypted WatchConnectivity payload that the OS delivers to your own paired Apple Watch — directly, peer-to-peer.

**No third-party dependencies.** Only Apple frameworks (CryptoKit, WatchConnectivity, LocalAuthentication, AVFoundation, PhotosUI, CoreImage). No SwiftPM packages, no CocoaPods, no Carthage. The full source you're looking at is the full source that ships in the binary.

**Secrets at rest.** TOTP seeds go into the Keychain (`kSecClassGenericPassword`) with the strictest reasonable accessibility class — `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. Concretely this means: the seeds are bound to your device passcode, never leave the device, are not included in iCloud Keychain sync, and are automatically purged by iOS if you ever remove your device passcode. The Watch keeps an independent local copy with the same protection.

**App-level lock.** Even when the device is unlocked, opening AuthBand requires Face ID / Touch ID / passcode (configurable, default on). If the device has no passcode set at all, the app stays locked — it won't grant access just because biometric auth is unavailable.

**Clipboard hygiene.** When you tap a row to copy a code, the clipboard entry is set with an expiration date no later than 30 seconds in the future — typically the end of the current TOTP window. Codes don't linger in the pasteboard beyond their validity.

**Privacy shield.** As soon as the iPhone scene goes inactive (App Switcher, control center, incoming call), the content is covered by an opaque overlay so the codes don't show up in screenshots or the App Switcher preview. The Apple Watch behaves the same way.

**Input validation.** QR codes and `otpauth://` URLs are parsed defensively: only TOTP/SHA-1 is accepted, `digits` are constrained to {6, 7, 8}, `period` to 15–300 seconds, secrets are validated as Base32. The Google Authenticator migration protobuf reader has been fuzz-style tested for truncated and malformed inputs.

**Sync payload safety.** The WatchConnectivity payload is wrapped in a versioned envelope and capped at 200 accounts. The Watch rejects payloads with an unknown version or that exceed the cap.

**Audited.** A full third-party security audit was conducted in May 2026 covering Keychain configuration, authentication, untrusted-input parsing, IPC, clipboard, cryptography, and shipping hygiene. The findings were reviewed; P1/P2 issues are fixed in the repository (see git history). The audit report itself isn't redistributed but the code changes that addressed it are open.

**AI-assisted review.** The codebase has also been reviewed with ChatGPT 5.5, including Deep Research, and Claude Opus 4.7.

## Build

1. Open `AuthBand.xcodeproj` in Xcode 17 or later.
2. Select the `AuthBand` scheme for iPhone or `AuthBandWatch` for Apple Watch.
3. Pick a simulator or paired device and Run.

For a physical Apple Watch, set your own bundle identifier and development team in Signing & Capabilities.

## Tests

```
xcodebuild -project AuthBand.xcodeproj -scheme AuthBand \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

Covers TOTP RFC 6238 vectors, `otpauth://` URL parsing (happy paths + every error case), the hand-rolled protobuf reader, Google Authenticator migration parsing, and QR-image-decoding roundtrips.

## Status

Proof of concept. Working and tested across iPhone SE through 17 Pro Max and Apple Watch SE 3 through Ultra 3. Not yet on the App Store. No iCloud sync, no encrypted export — by design for now (those are surface area to scrutinize before adding).

## License

MIT — see [LICENSE](LICENSE).
