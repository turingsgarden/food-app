// NetworkMonitor.swift
import Foundation
import Network
import SwiftUI

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var connectionType = ConnectionType.unknown
    @Published var isExpensive = false
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                
                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .ethernet
                } else {
                    self?.connectionType = .unknown
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// Offline Banner Component
struct OfflineBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    @State private var showBanner = false
    
    var body: some View {
        VStack {
            if !networkMonitor.isConnected && showBanner {
                HStack {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundColor(.white)
                    
                    Text("No Internet Connection")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if networkMonitor.connectionType == .cellular && networkMonitor.isExpensive {
                        Text("Limited")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: showBanner)
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            withAnimation {
                showBanner = !isConnected
            }
        }
        .onAppear {
            showBanner = !networkMonitor.isConnected
        }
    }
}
