import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(onCode: onCode, onError: onError)
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let onCode: (String) -> Void
    private let onError: (String) -> Void
    private var didReportResult = false

    init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onCode = onCode
        self.onError = onError
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        configureCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    granted ? self.configureSession() : self.reportError("Camera access is required to scan QR codes")
                }
            }
        case .denied, .restricted:
            reportError("Camera access is required to scan QR codes")
        @unknown default:
            reportError("Camera access status is unknown")
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            reportError("Camera is unavailable on this device")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureMetadataOutput()

            guard session.canAddInput(input), session.canAddOutput(output) else {
                reportError("QR scanner could not be configured")
                return
            }

            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
            startSession()
        } catch {
            reportError("Camera failed: \(error.localizedDescription)")
        }
    }

    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            guard !session.isRunning else {
                return
            }

            session.startRunning()
        }
    }

    private func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            guard session.isRunning else {
                return
            }

            session.stopRunning()
        }
    }

    private func reportError(_ message: String) {
        guard !didReportResult else {
            return
        }

        didReportResult = true
        onError(message)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didReportResult,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue
        else {
            return
        }

        didReportResult = true
        stopSession()
        onCode(code)
    }
}
