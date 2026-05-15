import LocalAuthentication
import SwiftUI
import UIKit

@main
struct AuthBandApp: App {
    @StateObject private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSceneObscured = false
    @State private var didAttemptAuthThisForeground = false

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appLock.isUnlocked {
                    ContentView(appLock: appLock)
                        .overlay {
                            if isSceneObscured {
                                PrivacyOverlay()
                            }
                        }
                } else {
                    AppLockOverlay(appLock: appLock)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                isSceneObscured = false
                if !appLock.isUnlocked && !didAttemptAuthThisForeground {
                    didAttemptAuthThisForeground = true
                    appLock.authenticate()
                }
            case .background:
                appLock.lock()
                didAttemptAuthThisForeground = false
                isSceneObscured = true
            case .inactive:
                isSceneObscured = true
            @unknown default:
                break
            }
        }
    }
}

@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var isUnlocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastError: String?

    static let requireLockKey = "requireBiometricLock"

    static var isLockEnabled: Bool {
        UserDefaults.standard.object(forKey: requireLockKey) as? Bool ?? true
    }

    init() {
        isUnlocked = !AppLockManager.isLockEnabled
    }

    func authenticate() {
        guard AppLockManager.isLockEnabled else {
            isUnlocked = true
            lastError = nil
            return
        }

        guard !isAuthenticating, !isUnlocked else {
            return
        }

        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            lastError = (policyError as? LAError).map { AppLockManager.message(for: $0) }
                ?? "Set a device passcode to use AuthBand — accounts stay locked until then"
            return
        }

        isAuthenticating = true

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock AuthBand"
        ) { [weak self] success, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isAuthenticating = false

                if success {
                    self.isUnlocked = true
                    self.lastError = nil
                } else {
                    self.lastError = (error as? LAError).map { AppLockManager.message(for: $0) } ?? error?.localizedDescription
                }
            }
        }
    }

    func lock() {
        guard AppLockManager.isLockEnabled else {
            isUnlocked = true
            return
        }
        isUnlocked = false
    }

    func applyLockPreferenceChange() {
        if !AppLockManager.isLockEnabled {
            isUnlocked = true
            lastError = nil
        }
    }

    private static func message(for error: LAError) -> String {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Authentication cancelled"
        case .userFallback:
            return "Use Face ID, Touch ID, or your passcode to unlock"
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "Biometric authentication is not set up on this device"
        case .biometryLockout:
            return "Biometric authentication is locked — unlock with your passcode"
        case .passcodeNotSet:
            return "Set a device passcode to enable the lock screen"
        case .authenticationFailed:
            return "Authentication failed — try again"
        default:
            return error.localizedDescription
        }
    }
}

private struct LockChrome<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary)

                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, geo.size.height * 0.28)
            }
        }
    }
}

private struct AppLockOverlay: View {
    @ObservedObject var appLock: AppLockManager

    var body: some View {
        LockChrome {
            Text("AuthBand is locked")
                .font(.headline)

            if let lastError = appLock.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                appLock.authenticate()
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appLock.isAuthenticating)
        }
    }
}

private struct PrivacyOverlay: View {
    var body: some View {
        LockChrome {
            EmptyView()
        }
    }
}
