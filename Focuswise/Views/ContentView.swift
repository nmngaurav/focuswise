import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FocusViewModel()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Countdown Timer
                Text(timeString(from: viewModel.timerManager.remainingTime))
                    .font(.system(size: 80, weight: .light, design: .monospaced))
                    .foregroundColor(.white)
                
                if viewModel.showWarning {
                    Text("You seem away")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .transition(.opacity)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // Start/Stop Button
                Button(action: {
                    viewModel.toggleStartStop()
                }) {
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 140, height: 50)
                        .background(buttonColor)
                        .cornerRadius(25)
                }
                .padding(.bottom, 50)
            }
            
            if viewModel.cameraPermissionDenied {
                Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
                VStack {
                    Text("Camera Access Required")
                        .foregroundColor(.white)
                        .font(.title2)
                    Text("Focuswise needs the camera to detect your presence and help you stay focused.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private var buttonTitle: String {
        switch viewModel.timerManager.status {
        case .idle, .finished:
            return "Start"
        case .running, .paused:
            return "Stop"
        }
    }
    
    private var buttonColor: Color {
        switch viewModel.timerManager.status {
        case .idle, .finished:
            return .green
        case .running, .paused:
            return .red
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
