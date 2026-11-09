import AVFoundation
import SwiftUI
import UIKit

/// A full-screen QR scanner for the pairing code on the computer. Calls `onCode` once per distinct code.
/// Without camera permission it explains why and offers the Settings app instead.
struct QRScannerView: View {
    let onCode: (String) -> Void
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                CameraPreview(onCode: onCode)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("mirrorScannerPreview")
            case .notDetermined:
                Color.clear.task {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    status = granted ? .authorized : .denied
                }
            default:
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.inkSecondary)
                    Text("Camera access is off")
                        .font(.headline)
                    Text("Allow the camera to scan the pairing code, or paste the pairing link instead.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = context.coordinator.session
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
            }
        }
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let running = session
        DispatchQueue.global(qos: .userInitiated).async { running.startRunning() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private var lastCode: String?

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, code != lastCode else { return }
            lastCode = code
            onCode(code)
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
