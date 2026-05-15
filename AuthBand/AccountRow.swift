import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AccountRow: View {
    let account: OTPAccount
    let date: Date
    let onCopied: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private let generator = TOTPGenerator()

    var body: some View {
        let code = generator.code(for: account, at: date)

        Button {
            copy(code)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.issuer)
                        .font(.headline)
                        .lineLimit(1)

                    if !account.name.isEmpty {
                        Text(account.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                codeView(for: code, digits: account.digits)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func codeView(for code: String, digits: Int) -> some View {
        let codeFont = Font.system(.title, design: .monospaced).weight(.semibold)

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

    private func copy(_ code: String) {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: account.period)
        let expiresAt = date.addingTimeInterval(account.period - elapsed)

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: code]],
            options: [.expirationDate: expiresAt]
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCopied()
    }
}
