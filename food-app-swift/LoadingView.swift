//import SwiftUI
import SwiftUI

struct LoadingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            themeManager.current.background
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                
                VStack(spacing: 8) {
                    Text("NutriSnap").font(.title.bold()).foregroundColor(themeManager.current.primaryText)
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        Text("Loading...").font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                    }
                }
            }
        }
        .onAppear { isAnimating = true }
    }
}
