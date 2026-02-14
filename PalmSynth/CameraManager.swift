import Foundation
import AVFoundation
import Combine
import ImageIO

final class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var frameCount: Int = 0

    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation) -> Void)?

    private let outputQueue = DispatchQueue(label: "PalmSynth.CameraOutputQueue")
    private let sessionQueue = DispatchQueue(label: "PalmSynth.CameraSessionQueue")

    private var configured = false

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.configured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .vga640x480

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                mediaType: .video,
                position: .unspecified
            )

            guard let device = discovery.devices.first else {
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                self.session.commitConfiguration()
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: self.outputQueue)

            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }

            self.session.commitConfiguration()
            self.configured = true
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configured else { return }
            guard !self.session.isRunning else { return }

            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        DispatchQueue.main.async { self.frameCount += 1 }

        // macOS webcams + Vision are happiest with .right in many setups
        let orientation: CGImagePropertyOrientation = .right

        onFrame?(pixelBuffer, orientation)
    }
}
