import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FocusViewModel()
    @State private var showingSettings = false
    @State private var showingStats = false
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3.bold())
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                            .background(Circle().fill(.white.opacity(0.05)))
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: { showingStats = true }) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title3.bold())
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                            .background(Circle().fill(.white.opacity(0.05)))
                    }
                    .padding()
                }
                
                Spacer()
                
                // Focus Ring and Timer
                ZStack {
                    FocusRingView(
                        progress: progressValue,
                        color: statusColor,
                        isPaused: viewModel.isAutoPaused
                    )
                    .frame(width: 280, height: 280)
                    
                    if let countdown = viewModel.calibrationCountdown {
                        Text("\(countdown)")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        VStack(spacing: 8) {
                            Text(timeString(from: viewModel.timerManager.remainingTime))
                                .font(.system(size: 64, weight: .light, design: .monospaced))
                                .foregroundColor(.white)
                            
                            if viewModel.isAutoPaused {
                                Text("PAUSED")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.red.opacity(0.2)))
                            }
                        }
                    }
                }
                
                if viewModel.showWarning && viewModel.calibrationCountdown == nil {
                    Text("Focus lost! eyes missing...")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.top, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Start/Stop Button
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.toggleStartStop()
                    }
                }) {
                    Text(buttonTitle)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white) // Use white for better visibility
                        .frame(width: 160, height: 56)
                        .background(buttonColor)
                        .cornerRadius(28)
                        .shadow(color: buttonColor.opacity(0.4), radius: 10, y: 5)
                }
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Camera Permission Overlay (Premium Glass Style)
            if viewModel.cameraPermissionDenied {
                ZStack {
                    Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
                    BlurView(style: .systemUltraThinMaterialDark)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Camera Access Required")
                            .foregroundColor(.white)
                            .font(.system(.title2, design: .rounded).bold())
                        
                        Text("Focuswise needs the camera for eye-tracking to help you stay focused.")
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Open Settings")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.1))
                                .cornerRadius(25)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingStats) {
            StatsView(statsService: viewModel.statsService)
        }
        .preferredColorScheme(.dark)
    }
    
    private var progressValue: Double {
        let total = viewModel.isPremium ? viewModel.customDuration : 25 * 60
        return 1.0 - (viewModel.timerManager.remainingTime / total)
    }
    
    private var statusColor: Color {
        if viewModel.isAutoPaused { return .red }
        if viewModel.showWarning { return .orange }
        return .green
    }
    
    private var buttonTitle: String {
        if viewModel.calibrationCountdown != nil {
            return "Cancel"
        }
        switch viewModel.timerManager.status {
        case .idle, .finished:
            return "Start Session"
        case .running, .paused:
            return "Stop Session"
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

// Glassmorphism Blur Helper
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct SettingsView: View {
    @ObservedObject var viewModel: FocusViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(white: 0.05)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Text("Settings")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(25)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Eye Tracking Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("EYE TRACKING")
                                .font(.system(.caption, design: .rounded).bold())
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Warning Mode")
                                        .foregroundColor(.white)
                                    Text("5s grace period before pause")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                Toggle("", isOn: $viewModel.isWarningModeEnabled)
                                    .tint(.green)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1)))
                        }
                        
                        // Premium Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("MONETIZATION")
                                .font(.system(.caption, design: .rounded).bold())
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1)
                            
                            VStack(spacing: 1) {
                                HStack {
                                    Text("Focuswise Pro")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Toggle("", isOn: $viewModel.isPremium)
                                        .tint(.green)
                                }
                                .padding()
                                
                                if viewModel.isPremium {
                                    Divider().background(.white.opacity(0.1)).padding(.horizontal)
                                    HStack {
                                        Text("Session Duration")
                                            .foregroundColor(.white)
                                        Spacer()
                                        
                                        HStack(spacing: 20) {
                                            Button(action: {
                                                if viewModel.customDuration > 60 {
                                                    viewModel.customDuration -= 60
                                                }
                                            }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                            }
                                            
                                            Text("\(Int(viewModel.customDuration / 60)) min")
                                                .font(.system(.body, design: .rounded).monospacedDigit())
                                                .foregroundColor(.white)
                                                .frame(width: 60)
                                            
                                            Button(action: {
                                                if viewModel.customDuration < 7200 {
                                                    viewModel.customDuration += 60
                                                }
                                            }) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .padding()
                                } else {
                                    Divider().background(.white.opacity(0.1)).padding(.horizontal)
                                    HStack {
                                        Text("Standard Duration")
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("25 min").foregroundColor(.white.opacity(0.6))
                                    }
                                    .padding()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 25)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
struct StatsView: View {
    @ObservedObject var statsService: StatsService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(white: 0.05)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Text("Performance")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(25)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // High-level Stats
                        HStack(spacing: 16) {
                            StatCard(title: "Focused", value: formatTime(statsService.totalFocusTimeToday), icon: "crown.fill", color: .yellow)
                            StatCard(title: "Pauses", value: "\(statsService.interruptionCountToday)", icon: "pause.fill", color: .red)
                        }
                        
                        // Focus Score Card
                        VStack(spacing: 12) {
                            Text("Focus Quality Score")
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("\(statsService.focusScoreToday)")
                                .font(.system(size: 80, weight: .bold, design: .rounded))
                                .foregroundColor(scoreColor)
                            
                            Text("OUT OF 100")
                                .font(.system(.caption, design: .rounded).bold())
                                .foregroundColor(.white.opacity(0.7))
                                .tracking(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(RoundedRectangle(cornerRadius: 30).fill(.white.opacity(0.1)))
                        
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 25)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
    
    private var scoreColor: Color {
        let score = statsService.focusScoreToday
        if score > 80 { return .green }
        if score > 50 { return .orange }
        return .red
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.1)))
    }
}

struct FocusRingView: View {
    let progress: Double // 0.0 to 1.0
    let color: Color
    let isPaused: Bool
    
    var body: some View {
        ZStack {
            // Background Track
            Circle()
                .stroke(lineWidth: 12)
                .opacity(0.1)
                .foregroundColor(.white)
            
            // Progress Ring
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            if isPaused {
                Circle()
                    .stroke(lineWidth: 2)
                    .scaleEffect(1.1)
                    .opacity(0.3)
                    .foregroundColor(color)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPaused)
            }
        }
    }
}
