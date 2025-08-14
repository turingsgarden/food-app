// ErrorHandling.swift
import SwiftUI

// MARK: - Unified Error Types
enum AppError: LocalizedError, Identifiable {
    case network(NetworkError)
    case server(ServerError)
    case validation(String)
    case unknown(String)
    
    enum NetworkError {
        case noInternet
        case timeout
        case connectionLost
        case coldStart
    }
    
    enum ServerError {
        case unauthorized
        case serverError(code: Int)
        case notFound
        case badRequest(message: String)
    }
    
    var id: String {
        switch self {
        case .network(let error): return "network_\(error)"
        case .server(let error): return "server_\(error)"
        case .validation(let msg): return "validation_\(msg)"
        case .unknown(let msg): return "unknown_\(msg)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            switch error {
            case .noInternet: return "No internet connection"
            case .timeout: return "Request timed out"
            case .connectionLost: return "Connection lost"
            case .coldStart: return "Server is starting up"
            }
        case .server(let error):
            switch error {
            case .unauthorized: return "Please log in again"
            case .serverError(let code): return "Server error (\(code))"
            case .notFound: return "Resource not found"
            case .badRequest(let message): return message
            }
        case .validation(let message): return message
        case .unknown(let message): return message
        }
    }
    
    var title: String {
        switch self {
        case .network(.noInternet): return "Offline"
        case .network(.coldStart): return "Starting Up"
        case .network: return "Connection Error"
        case .server(.unauthorized): return "Session Expired"
        case .server: return "Server Error"
        case .validation: return "Invalid Input"
        case .unknown: return "Error"
        }
    }
    
    var icon: String {
        switch self {
        case .network(.noInternet): return "wifi.exclamationmark"
        case .network(.coldStart): return "clock.arrow.circlepath"
        case .network: return "exclamationmark.icloud"
        case .server(.unauthorized): return "lock.fill"
        case .server: return "exclamationmark.triangle"
        case .validation: return "exclamationmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .network: return true
        case .server(.serverError): return true
        case .server(.unauthorized): return false
        case .validation: return false
        default: return true
        }
    }
}

// MARK: - Consistent Error View Component
struct AppErrorView: View {  // <-- Renamed to avoid conflict
    let error: AppError
    let retry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: error.icon)
                .font(.system(size: 50))
                .foregroundColor(iconColor)
            
            VStack(spacing: 8) {
                Text(error.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let description = error.errorDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
            }
            
            if error.isRetryable, let retry = retry {
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
                            gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding()
    }
    
    private var iconColor: Color {
        switch error {
        case .network(.coldStart): return .orange
        case .network: return .red
        case .server(.unauthorized): return .orange
        case .server: return .red
        case .validation: return .yellow
        case .unknown: return .gray
        }
    }
}

// MARK: - Server Cold Start Loading View (renamed)
struct ServerWarmupView: View {  // <-- Renamed to avoid conflict
    @State private var dots = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Animated Icon
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
                    
                    Image(systemName: "server.rack")
                        .font(.title)
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 12) {
                    Text("Waking up server...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("This happens after periods of inactivity.\nIt should only take a moment.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    // Progress indicator
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(index <= dots % 3 ? Color.orange : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            dots = 3
        }
    }
}

// MARK: - Error Toast Component
struct ErrorToast: View {
    let error: AppError
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack {
                Spacer()
                
                HStack {
                    Image(systemName: error.icon)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        
                        if let description = error.errorDescription {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { isShowing = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                }
                .padding()
                .background(
                    Capsule()
                        .fill(backgroundColor)
                        .shadow(color: shadowColor, radius: 10)
                )
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
    
    private var backgroundColor: Color {
        switch error {
        case .network(.coldStart): return .orange
        case .network, .server: return .red
        case .validation: return .yellow
        case .unknown: return .gray
        }
    }
    
    private var shadowColor: Color {
        backgroundColor.opacity(0.3)
    }
}
