import CoreImage
import UIKit

enum QRImageDecoder {
    static func decode(_ image: UIImage) -> [String] {
        guard let ciImage = CIImage(image: image) else {
            return []
        }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
