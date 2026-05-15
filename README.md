# AuthBand

Minimal watchOS + iOS SwiftUI app for showing TOTP codes with live 30-second countdowns. Codes live on the watch; the iPhone is the companion that adds and edits accounts.

Current implementation:

- stores OTP accounts in Keychain;
- supports manual account entry in the iOS companion app;
- supports `otpauth://` QR codes and Google Authenticator migration QR codes;
- syncs accounts from iPhone to Apple Watch with `WatchConnectivity`;
- generates TOTP codes locally on the watch;
- Face ID / Touch ID gate on the iPhone.

Not yet: iCloud sync, backup/restore, App Store polish.

## Run

1. Open `AuthBand.xcodeproj` in Xcode.
2. Select the `AuthBand` scheme for iPhone or `AuthBandWatch` for Apple Watch.
3. Select a watchOS Simulator, paired Apple Watch, iOS Simulator, or iPhone.
4. Run.

For a real Apple Watch, use a unique bundle identifier owned by you and select your development team in Signing & Capabilities.
