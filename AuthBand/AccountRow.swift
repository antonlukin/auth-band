import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AccountRow: View {
    let account: OTPAccount
    let date: Date
    let onCopied: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @AppStorage("hideCodes") private var hideCodes = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let generator = TOTPGenerator()

    var body: some View {
        let code = generator.code(for: account, at: date)

        Button {
            copy(code)
        } label: {
            rowContent(for: code)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .accessibilityLabel(Text(accessibilityDescription(for: code)))
        .accessibilityHint(Text("Copy code"))
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
    private func rowContent(for code: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                infoColumn
                codeView(for: code, digits: account.digits)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                infoColumn
                Spacer(minLength: 12)
                codeView(for: code, digits: account.digits)
            }
        }
    }

    private var infoColumn: some View {
        let lineLimit: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 1
        return VStack(alignment: .leading, spacing: 4) {
            Text(account.issuer)
                .font(.headline)
                .lineLimit(lineLimit)

            if !account.name.isEmpty {
                Text(account.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
            }
        }
    }

    @ViewBuilder
    private func codeView(for code: String, digits: Int) -> some View {
        let codeFont = Font.system(.title, design: .monospaced).weight(.semibold)

        if hideCodes {
            Text(Self.maskedCode(digits: digits))
                .font(codeFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else if digits == 6, code.count == 6 {
            let splitIndex = code.index(code.startIndex, offsetBy: 3)
            HStack(spacing: 6) {
                Text(String(code[..<splitIndex]))
                    .font(codeFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(String(code[splitIndex...]))
                    .font(codeFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        } else {
            Text(code)
                .font(codeFont)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private static func maskedCode(digits: Int) -> String {
        guard digits == 6 else {
            return String(repeating: "•", count: digits)
        }
        return "••• •••"
    }

    private func accessibilityDescription(for code: String) -> String {
        let spokenCode: String
        if hideCodes {
            spokenCode = String(localized: "Code hidden", comment: "VoiceOver: code masked because Hide Codes is on")
        } else {
            spokenCode = code.map(String.init).joined(separator: " ")
        }
        let parts = [account.issuer, account.name, spokenCode].filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    private func copy(_ code: String) {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: account.period)
        let timeUntilWindowEnd = account.period - elapsed
        let expiresAt = date.addingTimeInterval(min(timeUntilWindowEnd, 30))

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: code]],
            options: [.expirationDate: expiresAt]
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCopied()
    }
}
