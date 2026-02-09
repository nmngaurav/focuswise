import Foundation
import Combine
import SwiftUI

@MainActor
class FocusViewModel: ObservableObject {
    @Published var timerManager = TimerManager()
    @Published var presenceDetector = PresenceDetector()
    @Published var cameraService = CameraService()
    
    @Published var showWarning = false
    @Published var cameraPermissionDenied = false
    
    private var absenceTimer: Timer?
    private var absenceStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Feed camera frames to presence detector
        cameraService.onFrameGenerated = { [weak self] pixelBuffer in
            // Process Vision on the background queue (where frames are generated)
            // PresenceDetector already handles internal dispatch to main for @Published
            self?.presenceDetector.processFrame(pixelBuffer)
        }
        
        // React to presence changes
        presenceDetector.$isFaceDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in
                self?.handlePresenceChange(detected: detected)
            }
            .store(in: &cancellables)
            
        // Stop camera if timer finishes naturally
        timerManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .finished {
                    self?.stopSession()
                }
                
                // Keep screen ON only while timer is running
                UIApplication.shared.isIdleTimerDisabled = (status == .running)
            }
            .store(in: &cancellables)
            
        // Handle App Lifecycle transitions
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBackgrounding()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppBackgrounding() {
        // If the timer is running, we should pause it because we lose the camera in background
        if timerManager.status == .running {
            timerManager.pause()
            cameraService.stop()
            resetAbsenceTracking()
            showWarning = true 
        }
    }
    
    func toggleStartStop() {
        if timerManager.status == .running || timerManager.status == .paused {
            stopSession()
        } else {
            startSession()
        }
    }
    
    private func startSession() {
        cameraService.checkPermission { [weak self] granted in
            Task { @MainActor in
                guard let self = self else { return }
                if granted {
                    self.cameraService.start()
                    self.timerManager.start()
                    self.cameraPermissionDenied = false
                } else {
                    self.cameraPermissionDenied = true
                }
            }
        }
    }
    
    private func stopSession() {
        timerManager.stop()
        cameraService.stop()
        resetAbsenceTracking()
        showWarning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func handlePresenceChange(detected: Bool) {
        guard timerManager.status == .running || timerManager.status == .paused else { return }
        
        if detected {
            resetAbsenceTracking()
            
            // Auto-resume if we were paused by absence logic
            if timerManager.status == .paused {
                timerManager.resume()
            }
            
            showWarning = false
        } else {
            if absenceStartTime == nil {
                absenceStartTime = Date()
                startAbsenceTimer()
            }
        }
    }
    
    private func startAbsenceTimer() {
        absenceTimer?.invalidate()
        absenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAbsenceDuration()
            }
        }
    }
    
    private func checkAbsenceDuration() {
        guard let startTime = absenceStartTime, timerManager.status == .running else { return }
        let duration = Date().timeIntervalSince(startTime)
        
        if duration >= 30 {
            timerManager.pause()
            showWarning = true
        } else if duration >= 10 {
            showWarning = true
        }
    }
    
    private func resetAbsenceTracking() {
        absenceStartTime = nil
        absenceTimer?.invalidate()
        absenceTimer = nil
    }
}
