import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var currentPage = 0
    @State private var navigateToLogin = false

    let features = [
        OnboardingFeature(icon: "camera.fill", title: "Snap Your Meals",
                          description: "Take a photo and instantly identify ingredients and nutrition", color: .orange),
        OnboardingFeature(icon: "chart.line.uptrend.xyaxis", title: "Track Progress",
                          description: "Monitor your daily calories and nutritional intake", color: .orange),
        OnboardingFeature(icon: "sparkles", title: "AI-Powered Analysis",
                          description: "Get detailed insights about hidden ingredients and nutrition", color: .orange)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                GeometryReader { geometry in
                    ForEach(0..<15) { index in
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: CGFloat.random(in: 20...80))
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: CGFloat.random(in: 0...geometry.size.height)
                            )
                            .blur(radius: 10)
                            .animation(
                                Animation.easeInOut(duration: Double.random(in: 10...20))
                                    .repeatForever(autoreverses: true),
                                value: currentPage
                            )
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip") { navigateToLogin = true }
                            .foregroundColor(themeManager.current.secondaryText).padding()
                    }

                    Spacer()

                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.7)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .orange.opacity(0.3), radius: 20)
                        .scaleEffect(currentPage == 0 ? 1.0 : 0.8)
                        .animation(.spring(), value: currentPage)

                    Text("NutriSnap")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                        .padding(.top, 20)

                    TabView(selection: $currentPage) {
                        ForEach(0..<features.count, id: \.self) { index in
                            OnboardingPage(feature: features[index])
                                .environmentObject(themeManager)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .frame(height: 300)

                    HStack(spacing: 12) {
                        ForEach(0..<features.count, id: \.self) { index in
                            Capsule()
                                .fill(currentPage == index ? Color.orange : Color.gray.opacity(0.4))
                                .frame(width: currentPage == index ? 24 : 8, height: 8)
                                .animation(.spring(), value: currentPage)
                        }
                    }
                    .padding(.vertical, 30)

                    Button(action: {
                        if currentPage < features.count - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            navigateToLogin = true
                        }
                    }) {
                        HStack {
                            Text(currentPage < features.count - 1 ? "Next" : "Get Started").fontWeight(.semibold)
                            Image(systemName: currentPage < features.count - 1 ? "arrow.right" : "arrow.right.circle.fill")
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(12).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 40).padding(.bottom, 50)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationDestination(isPresented: $navigateToLogin) {
                LoginView()
                    .navigationBarBackButtonHidden(true)
                    .environmentObject(themeManager) 
            }
        }
    }
}

struct OnboardingFeature {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingPage: View {
    @EnvironmentObject var themeManager: ThemeManager
    let feature: OnboardingFeature

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(feature.color.opacity(0.2)).frame(width: 120, height: 120)
                Image(systemName: feature.icon).font(.system(size: 50)).foregroundColor(feature.color)
            }
            VStack(spacing: 12) {
                Text(feature.title).font(.title2.bold())
                    .foregroundColor(themeManager.current.primaryText)
                Text(feature.description).font(.body)
                    .foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .padding(.vertical, 20)
    }
}
