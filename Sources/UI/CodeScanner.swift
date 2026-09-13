import AVFoundation
import SwiftUI

/// The camera, reading barcodes and QR codes. It reports every code it
/// sees; the caller decides whether it is the one that counts.
struct CodeScanner: UIViewRepresentable {
    let onScan: @MainActor (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = context.coordinator.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Camera) {
        coordinator.stop()
    }

    func makeCoordinator() -> Camera { Camera(onScan: onScan) }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    /// Owns the capture session. Configuration and running happen on its
    /// own queue, because starting a session blocks; codes come back on
    /// the main queue.
    final class Camera: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        @MainActor var onScan: @MainActor (String) -> Void
        private let queue = DispatchQueue(label: "no.espenbye.entrain.scanner")
        private var configured = false

        @MainActor
        init(onScan: @escaping @MainActor (String) -> Void) {
            self.onScan = onScan
        }

        func start() {
            queue.async { [self] in
                if !configured { configure() }
                if !session.isRunning { session.startRunning() }
            }
        }

        func stop() {
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
            }
        }

        private func configure() {
            configured = true
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = output.availableMetadataObjectTypes
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            guard let code = codes.first else { return }
            MainActor.assumeIsolated { onScan(code) }
        }
    }
}

extension CodeScanner {
    /// Asks for the camera the first time, and says whether it is ours.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}
