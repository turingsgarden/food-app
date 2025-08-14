import SwiftUI

// MARK: - Loading Overlay with Message
struct LoadingOverlay: View {
    let message: String
    var showProgress: Bool = true
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if showProgress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Cold Start Loading View
struct ColdStartLoadingView: View {
    @State private var dots = 0
    @State private var showTip = false
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Animated icon
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .orange.opacity(0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(Double(dots) * 120))
                        .animation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false),
                            value: dots
                        )
                    
                    Image(systemName: "cloud.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 12) {
                    Text(message)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if showTip {
                        VStack(spacing: 8) {
                            Text("First request of the day?")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text("Free servers need a moment to wake up")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            dots = 3
            
            // Show tip after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(.spring()) {
                    showTip = true
                }
            }
        }
    }
}

// MARK: - Inline Error View with Retry
struct InlineErrorView: View {
    let error: ErrorType
    let retry: () -> Void
    
    enum ErrorType {
        case network
        case server
        case timeout
        case custom(String)
        
        var icon: String {
            switch self {
            case .network: return "wifi.exclamationmark"
            case .server: return "exclamationmark.icloud.fill"
            case .timeout: return "clock.arrow.circlepath"
            case .custom: return "exclamationmark.triangle.fill"
            }
        }
        
        var title: String {
            switch self {
            case .network: return "Network Error"
            case .server: return "Server Error"
            case .timeout: return "Request Timeout"
            case .custom: return "Error"
            }
        }
        
        var message: String {
            switch self {
            case .network: return "Check your internet connection"
            case .server: return "Our servers are having issues"
            case .timeout: return "The request took too long"
            case .custom(let msg): return msg
            }
        }
        
        var color: Color {
            switch self {
            case .network: return .orange
            case .server: return .red
            case .timeout: return .yellow
            case .custom: return .red
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: error.icon)
                .font(.system(size: 50))
                .foregroundColor(error.color.opacity(0.8))
            
            VStack(spacing: 8) {
                Text(error.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(error.message)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: retry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [error.color, error.color.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - Loading State Card
struct LoadingStateCard: View {
    let title: String
    let subtitle: String?
    
    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
