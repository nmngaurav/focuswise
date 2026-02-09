import AVFoundation
import Vision

/*
 PRIVACY INTENT:
 This service manages the front camera for the sole purpose of real-time on-device face detection.
 - Camera frames are processed exactly when received and immediately discarded.
 - No images or videos are stored locally or transmitted over any network.
 - The camera is ACTIVE only when the user has started the focus timer.
*/

class CameraService: NSObject, ObservableObject {
    @Published var isCameraRunning = false
    @Published var permissionDenied = false
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.focuswise.cameraSessionQueue")
    
    var onFrameGenerated: ((CVPixelBuffer) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            permissionDenied = true
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            defer {
                self.captureSession.commitConfiguration()
            }
            
            // Front camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                print("Failed to get front camera or create input")
                return
            }
            
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }
            
            // Frame rate optimization for battery usage (Target: 5 FPS)
            do {
                try camera.lockForConfiguration()
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
                camera.unlockForConfiguration()
            } catch {
                print("Failed to set frame rate: \(error)")
            }
            
            // Video data output
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
        }
    }
    
    func start() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isCameraRunning = true
                }
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                DispatchQueue.main.async {
                    self.isCameraRunning = false
                }
            }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrameGenerated?(pixelBuffer)
    }
}
