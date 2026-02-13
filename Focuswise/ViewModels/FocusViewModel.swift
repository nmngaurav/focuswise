import Foundation
import Combine
import AVFoundation
import CoreImage
import UIKit
import AudioToolbox
import Vision

@MainActor
class FocusViewModel: ObservableObject {
    @Published var timerManager = TimerManager()
    @Published var eyeTrackingService = EyeTrackingService()
    @Published var cameraService = CameraService()
    @Published var statsService = StatsService()
    
    // Settings
    @Published var isWarningModeEnabled = false
    @Published var isPremium = false
    @Published var customDuration: TimeInterval = 25 * 60
    
    @Published var showWarning = false
    @Published var cameraPermissionDenied = false
    @Published var isAutoPaused = false
    @Published var calibrationCountdown: Int? = nil
    
    private var absenceTimer: Timer?
    private var absenceStartTime: Date?
    private var resumeDebounceTimer: Timer?
    private var calibrationTimer: Timer?
    private var currentSessionInterruptions = 0
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAudioSession()
        setupBindings()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupBindings() {
        cameraService.onFrameGenerated = { [weak self] pixelBuffer in
            self?.eyeTrackingService.processFrame(pixelBuffer)
        }
        
        eyeTrackingService.$areEyesDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in
                self?.handleEyeDetectionChange(detected: detected)
            }
            .store(in: &cancellables)
            
        timerManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .finished {
                    self?.finalizeSession()
                    SensoryManager.shared.triggerHaptic(type: .success)
                }
                UIApplication.shared.isIdleTimerDisabled = (status == .running)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBackgrounding()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppBackgrounding() {
        if timerManager.status == .running {
            performAutoPause()
        }
    }
    
    func toggleStartStop() {
        if timerManager.status == .running || timerManager.status == .paused || calibrationCountdown != nil {
            stopSession()
        } else {
            startSession()
        }
    }
    
    private func startSession() {
        let duration = isPremium ? customDuration : 25 * 60
        timerManager.setDuration(duration)
        
        cameraService.checkPermission { [weak self] granted in
            Task { @MainActor in
                guard let self = self else { return }
                if granted {
                    self.startCalibration()
                } else {
                    self.cameraPermissionDenied = true
                }
            }
        }
    }
    
    private func startCalibration() {
        calibrationCountdown = 3
        SensoryManager.shared.triggerHaptic(type: .impact)
        
        calibrationTimer?.invalidate()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { return }
                if let count = self.calibrationCountdown, count > 1 {
                    self.calibrationCountdown = count - 1
                    SensoryManager.shared.triggerHaptic(type: .impact)
                } else {
                    timer.invalidate()
                    self.calibrationTimer = nil
                    self.calibrationCountdown = nil
                    self.beginActualFocus()
                }
            }
        }
    }
    
    private func beginActualFocus() {
        currentSessionInterruptions = 0
        cameraService.start()
        timerManager.start()
        SensoryManager.shared.playSound(named: "start")
        SensoryManager.shared.triggerHaptic(type: .success)
    }
    
    private func stopSession() {
        finalizeSession()
    }
    
    private func finalizeSession() {
        let totalDuration = isPremium ? customDuration : 25 * 60
        let remaining = timerManager.remainingTime
        let durationSpent = totalDuration - remaining
        
        // Record only if meaningful focus occurred (> 10s)
        if durationSpent > 10 {
            statsService.recordSession(duration: durationSpent, interruptions: currentSessionInterruptions, totalPossible: durationSpent)
        }
        
        timerManager.stop()
        cameraService.stop()
        resetAbsenceTracking()
        resumeDebounceTimer?.invalidate()
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        calibrationCountdown = nil
        showWarning = false
        isAutoPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func handleEyeDetectionChange(detected: Bool) {
        guard timerManager.status == .running || (timerManager.status == .paused && isAutoPaused) else { return }
        
        if detected {
            resetAbsenceTracking()
            startResumeDebounce()
        } else {
            resumeDebounceTimer?.invalidate()
            if absenceStartTime == nil {
                absenceStartTime = Date()
                if !isWarningModeEnabled {
                    performAutoPause()
                } else {
                    startAbsenceTimer()
                }
            }
        }
    }
    
    private func startResumeDebounce() {
        resumeDebounceTimer?.invalidate()
        resumeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.eyeTrackingService.areEyesDetected && self.isAutoPaused {
                    self.timerManager.resume()
                    self.isAutoPaused = false
                    self.showWarning = false
                    SensoryManager.shared.playSound(named: "resume")
                    SensoryManager.shared.triggerHaptic(type: .success)
                }
            }
        }
    }
    
    private func startAbsenceTimer() {
        absenceTimer?.invalidate()
        absenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAbsenceDuration()
            }
        }
    }
    
    private func checkAbsenceDuration() {
        guard let startTime = absenceStartTime, timerManager.status == .running else { return }
        let duration = Date().timeIntervalSince(startTime)
        
        if duration >= 5.0 {
            performAutoPause()
        } else if duration >= 1.0 {
            if !showWarning {
                showWarning = true
                SensoryManager.shared.playSound(named: "warning")
                SensoryManager.shared.triggerHaptic(type: .warning)
            }
        }
    }
    
    private func performAutoPause() {
        if timerManager.status == .running {
            timerManager.pause()
            currentSessionInterruptions += 1
            isAutoPaused = true
            showWarning = true
            SensoryManager.shared.playSound(named: "pause")
            SensoryManager.shared.triggerHaptic(type: .warning)
        }
    }
    
    private func resetAbsenceTracking() {
        absenceStartTime = nil
        absenceTimer?.invalidate()
        absenceTimer = nil
    }
}

// MARK: - Consolidated Services to ensure Scope Visibility

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
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .denied, .restricted:
            permissionDenied = true
            completion(false)
        @unknown default: completion(false)
        }
    }
    
    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera) else { return }
            if self.captureSession.canAddInput(input) { self.captureSession.addInput(input) }
            do {
                try camera.lockForConfiguration()
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
                camera.unlockForConfiguration()
            } catch { print("Frame rate error: \(error)") }
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.captureSession.canAddOutput(self.videoOutput) { self.captureSession.addOutput(self.videoOutput) }
        }
    }
    
    func start() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async { self.isCameraRunning = true }
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                DispatchQueue.main.async { self.isCameraRunning = false }
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

enum TimerStatus { case idle, running, paused, finished }

class TimerManager: ObservableObject {
    @Published var remainingTime: TimeInterval = 25 * 60
    @Published var status: TimerStatus = .idle
    private var timer: AnyCancellable?
    private var lastStartTime: Date?
    private var accumulatedSeconds: TimeInterval = 0
    private var totalDuration: TimeInterval = 25 * 60
    
    func start() {
        guard status == .idle || status == .paused else { return }
        lastStartTime = Date()
        status = .running
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.updateTime() }
    }
    
    func pause() {
        guard status == .running, let startTime = lastStartTime else { return }
        accumulatedSeconds += Date().timeIntervalSince(startTime)
        lastStartTime = nil
        status = .paused
        timer?.cancel()
        timer = nil
    }
    
    func resume() { start() }
    func stop() {
        status = .idle
        accumulatedSeconds = 0
        lastStartTime = nil
        remainingTime = totalDuration
        timer?.cancel()
        timer = nil
    }
    
    func setDuration(_ duration: TimeInterval) {
        totalDuration = duration
        if status == .idle { remainingTime = duration }
    }
    
    private func updateTime() {
        guard let startTime = lastStartTime else { return }
        let totalElapsed = accumulatedSeconds + Date().timeIntervalSince(startTime)
        let newRemaining = max(0, totalDuration - totalElapsed)
        if newRemaining != remainingTime { remainingTime = newRemaining }
        if remainingTime <= 0 {
            status = .finished
            timer?.cancel()
            timer = nil
        }
    }
}

class EyeTrackingService: ObservableObject {
    @Published var areEyesDetected: Bool = true
    
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private var lastEyesDetectedTime = Date()
    private let blinkThreshold: TimeInterval = 0.5
    
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        do {
            try sequenceHandler.perform([faceLandmarksRequest], on: pixelBuffer, orientation: .leftMirrored)
            if let results = faceLandmarksRequest.results {
                let foundEyes = results.contains { face in
                    return face.landmarks?.leftEye != nil && face.landmarks?.rightEye != nil
                }
                DispatchQueue.main.async { self.handleDetectionResult(foundEyes) }
            } else {
                DispatchQueue.main.async { self.handleDetectionResult(false) }
            }
        } catch {
            print("Vision Eye Landmarks error: \(error)")
        }
    }
    
    private func handleDetectionResult(_ detected: Bool) {
        let now = Date()
        if detected {
            lastEyesDetectedTime = now
            if !areEyesDetected { areEyesDetected = true }
        } else {
            if now.timeIntervalSince(lastEyesDetectedTime) > blinkThreshold {
                if areEyesDetected { areEyesDetected = false }
            }
        }
    }
}

struct SessionStats: Codable {
    var date: Date
    var duration: TimeInterval
    var interruptions: Int
    var focusScore: Int
}

class StatsService: ObservableObject {
    @Published var totalFocusTimeToday: TimeInterval = 0
    @Published var interruptionCountToday: Int = 0
    private var sessions: [SessionStats] = []
    
    func recordSession(duration: TimeInterval, interruptions: Int, totalPossible: TimeInterval) {
        let score = calculateScore(duration: duration, interruptions: interruptions)
        let session = SessionStats(date: Date(), duration: duration, interruptions: interruptions, focusScore: score)
        sessions.append(session)
        totalFocusTimeToday += duration
        interruptionCountToday += interruptions
    }
    
    private func calculateScore(duration: TimeInterval, interruptions: Int) -> Int {
        guard duration > 30 else { return 100 } // Don't penalize ultra-short starts
        
        // Nuanced Scoring: 
        // 1. Time-based efficiency (Base 100)
        // 2. Linear penalty for interruptions (5% per interruption)
        // 3. Minimum floor of 0
        
        let interruptionPenalty = Double(interruptions) * 5.0
        let score = max(0, 100.0 - interruptionPenalty)
        
        return Int(score)
    }
    
    var focusScoreToday: Int {
        guard !sessions.isEmpty else { return 0 }
        let totalScore = sessions.reduce(0) { $0 + $1.focusScore }
        return totalScore / sessions.count
    }
}

class SensoryManager {
    static let shared = SensoryManager()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    func triggerHaptic(type: HapticType) {
        switch type {
        case .success: notificationGenerator.notificationOccurred(.success)
        case .warning: notificationGenerator.notificationOccurred(.warning)
        case .error: notificationGenerator.notificationOccurred(.error)
        case .impact: impactGenerator.impactOccurred()
        }
    }
    
    func playSound(named name: String) {
        let systemSoundID: SystemSoundID
        switch name {
        case "start": systemSoundID = 1007 
        case "pause": systemSoundID = 1001 
        case "resume": systemSoundID = 1000 
        case "warning": systemSoundID = 1011 
        default: return
        }
        AudioServicesPlaySystemSound(systemSoundID)
    }
}

enum HapticType {
    case success, warning, error, impact
}
