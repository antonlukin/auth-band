import CoreImage
import Foundation
import Testing
import UIKit

@testable import AuthBand

struct QRImageDecoderTests {
    @Test("Roundtrip: encode otpauth:// URL into QR image, decode back to the same string")
    func roundtripSingleURL() throws {
        let url = "otpauth://totp/Test:alice?secret=JBSWY3DPEHPK3PXP&issuer=Test"
        let image = try Self.makeQRImage(from: url)

        let codes = QRImageDecoder.decode(image)

        #expect(codes == [url])
    }

    @Test("Image without any QR code returns an empty array")
    func noQRReturnsEmpty() {
        let image = Self.makeBlankImage(size: CGSize(width: 200, height: 200))

        let codes = QRImageDecoder.decode(image)

        #expect(codes.isEmpty)
    }

    @Test("Image containing two QR codes returns both decoded strings")
    func multipleQRCodesReturnsAll() throws {
        let urlA = "otpauth://totp/A:alice?secret=JBSWY3DPEHPK3PXP&issuer=A"
        let urlB = "otpauth://totp/B:bob?secret=KRSXG5DPNZSXG6BB&issuer=B"
        let image = try Self.makeImage(combining: [urlA, urlB])

        let codes = QRImageDecoder.decode(image).sorted()

        #expect(codes == [urlA, urlB].sorted())
    }

    @Test("Long opaque payload (Google Authenticator migration URL shape) roundtrips")
    func roundtripMigrationStyleURL() throws {
        // Realistic-ish migration URL with a base64url payload
        let url = "otpauth-migration://offline?data=CiQKCkhlbGxvV29ybGQSBVRlc3QxGgVUZXN0MSABKAEwAhgBIAAoAA%3D%3D"
        let image = try Self.makeQRImage(from: url)

        let codes = QRImageDecoder.decode(image)

        #expect(codes == [url])
    }

    // MARK: - Helpers

    private static func makeQRImage(from string: String) throws -> UIImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QRTestError.filterUnavailable
        }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        // High error correction so even small/scaled images decode reliably
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            throw QRTestError.encodeFailed
        }

        // Scale up — CIQRCodeGenerator produces tiny output (one pixel per module)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw QRTestError.rasterizeFailed
        }
        return UIImage(cgImage: cgImage)
    }

    private static func makeBlankImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func makeImage(combining strings: [String]) throws -> UIImage {
        let qrImages = try strings.map { try makeQRImage(from: $0) }
        // Lay them out side by side with a small white gutter between them
        let gutter: CGFloat = 40
        let totalWidth = qrImages.reduce(0) { $0 + $1.size.width } + gutter * CGFloat(max(qrImages.count - 1, 0))
        let maxHeight = qrImages.map(\.size.height).max() ?? 0
        let canvas = CGSize(width: totalWidth, height: maxHeight)

        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            var x: CGFloat = 0
            for image in qrImages {
                image.draw(at: CGPoint(x: x, y: 0))
                x += image.size.width + gutter
            }
        }
    }

    private enum QRTestError: Error {
        case filterUnavailable
        case encodeFailed
        case rasterizeFailed
    }
}
