import SwiftUI

struct CircularCountdownView: View {
    let remainingSeconds: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(remainingSeconds)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 24, height: 24)
        .padding(2)
        .accessibilityLabel("Codes refresh in \(remainingSeconds) seconds")
    }
}
