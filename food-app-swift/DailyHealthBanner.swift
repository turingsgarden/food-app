import SwiftUI

struct DailyHealthBanner: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var session = SessionManager.shared

    var coachName: String = "Your Health Coach"
    var shortTip: String = "Try oatmeal this morning. It can help support healthy cholesterol levels."

    var onAcknowledge: (() -> Void)? = nil
    var onLearnMore: (() -> Void)? = nil

    var nowOverride: Date? = nil

    private var now: Date { nowOverride ?? Date() }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 0..<12:  return "👋"
        case 12..<17: return "🌤"
        default:      return "🌙"
        }
    }

    private var personalGreeting: String {
        let name = session.userName.isEmpty ? "there" : session.userName
        return "\(greetingPrefix), \(name) \(greetingEmoji)"
    }

    private var cardBackground: Color {
        themeManager.current.isDark ? Color.white.opacity(0.05) : .white
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            Text(personalGreeting)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)

            // Keep homepage message short and scannable.
            Text(shortTip)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText.opacity(0.95))
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: { onAcknowledge?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Got it")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                }
                .buttonStyle(.plain)

                Button(action: { onLearnMore?() }) {
                    Text("Tell me more")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.isDark ? .white : .orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule()
                                .stroke(themeManager.current.isDark ? Color.white.opacity(0.25) : Color.orange.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            ZStack {
                cardBackground
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.current.isDark ? Color.white.opacity(0.02) : Color.orange.opacity(0.05))
            }
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.current.isDark ? Color.white.opacity(0.12) : Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            coachAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(coachName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                Text(formattedDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
            }
            Spacer(minLength: 0)
            Text("Daily Tip")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(themeManager.current.isDark ? .white.opacity(0.8) : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        themeManager.current.isDark ? Color.white.opacity(0.08) : Color.orange.opacity(0.10)
                    )
                )
        }
    }

    private var coachAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct DailyTipDetailSheetView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let analysisText: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today’s tip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(themeManager.current.isDark ? .white.opacity(0.8) : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                themeManager.current.isDark ? Color.white.opacity(0.08) : Color.orange.opacity(0.10)
                            )
                        )

                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)

                    Text(analysisText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(themeManager.current.primaryText.opacity(0.9))
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(themeManager.current.background.ignoresSafeArea())
            .navigationTitle("Tip details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private func previewDate(hour: Int) -> Date {
    var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    c.hour = hour
    c.minute = 0
    return Calendar.current.date(from: c) ?? Date()
}

#Preview("Morning (Light)") {
    VStack {
        DailyHealthBanner(
            shortTip: "Morning Bella! Try oatmeal — it helps support healthy cholesterol.",
            nowOverride: previewDate(hour: 8)
        )
            .padding()
        Spacer()
    }
    .background(AppTheme.light.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Afternoon (Light)") {
    VStack {
        DailyHealthBanner(
            shortTip: "Keep lunch simple today: one lean protein + one green vegetable.",
            nowOverride: previewDate(hour: 14)
        )
        .padding()
        Spacer()
    }
    .background(AppTheme.light.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Evening (Dark)") {
    VStack {
        DailyHealthBanner(
            shortTip: "Try a light dinner tonight and keep sodium lower than yesterday.",
            nowOverride: previewDate(hour: 19)
        )
        .padding()
        Spacer()
    }
    .background(AppTheme.dark.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.dark)
}

#Preview("Long message") {
    VStack {
        DailyHealthBanner(
            shortTip: "Small change today: swap one processed snack for fruit.",
            nowOverride: previewDate(hour: 9)
        )
        .padding()
        Spacer()
    }
    .background(AppTheme.light.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.light)
}
