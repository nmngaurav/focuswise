import Vision
import CoreImage

class PresenceDetector: ObservableObject {
    @Published var isFaceDetected: Bool = true
    
    private let faceDetectionRequest = VNDetectFaceRectanglesRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        do {
            try sequenceHandler.perform([faceDetectionRequest], on: pixelBuffer, orientation: .leftMirrored)
            
            if let results = faceDetectionRequest.results {
                let foundFace = !results.isEmpty
                DispatchQueue.main.async {
                    self.isFaceDetected = foundFace
                }
            }
        } catch {
            print("Vision error: \(error)")
        }
    }
}
