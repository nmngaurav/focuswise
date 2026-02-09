import Foundation
import Combine

enum TimerStatus {
    case idle
    case running
    case paused
    case finished
}

@MainActor
class TimerManager: ObservableObject {
    @Published var remainingTime: TimeInterval = 25 * 60
    @Published var status: TimerStatus = .idle
    
    private var timer: AnyCancellable?
    
    func start() {
        guard status == .idle || status == .paused else { return }
        status = .running
        
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    func pause() {
        guard status == .running else { return }
        status = .paused
        timer?.cancel()
        timer = nil
    }
    
    func resume() {
        start()
    }
    
    func stop() {
        status = .idle
        remainingTime = 25 * 60
        timer?.cancel()
        timer = nil
    }
    
    private func tick() {
        if remainingTime > 0 {
            remainingTime -= 1
        } else {
            status = .finished
            timer?.cancel()
            timer = nil
        }
    }
}
