import SwiftUI

struct WatchAccountRow: View {
    let account: OTPAccount
    let date: Date

    private let generator = TOTPGenerator()

    var body: some View {
        let code = generator.code(for: account, at: date)
        let progress = countdownProgress(for: date, period: account.period)

        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(account.issuer)
                    .font(.caption)
                    .lineLimit(1)

                if !account.name.isEmpty {
                    Text(account.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            codeView(for: code, digits: account.digits)

            ThinProgressBar(value: progress)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func codeView(for code: String, digits: Int) -> some View {
        let codeFont = Font.system(size: 28, weight: .semibold, design: .monospaced)

        if digits == 6, code.count == 6 {
            let splitIndex = code.index(code.startIndex, offsetBy: 3)
            HStack(spacing: 6) {
                Text(String(code[..<splitIndex]))
                    .font(codeFont)
                Text(String(code[splitIndex...]))
                    .font(codeFont)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(code)
                .font(codeFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func countdownProgress(for date: Date, period: TimeInterval) -> Double {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return 1 - (elapsed / period)
    }
}

private struct ThinProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.25))

                Capsule()
                    .fill(.green)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 2)
    }
}
