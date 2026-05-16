import SwiftUI

@main
struct AuthBandWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isObscured = false

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .overlay {
                    if isObscured {
                        WatchPrivacyOverlay()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    isObscured = newPhase != .active
                }
        }
    }
}

private struct WatchPrivacyOverlay: View {
    var body: some View {
        ZStack {
            Color(.black)
                .ignoresSafeArea()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
        }
    }
}
