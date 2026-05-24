//
//  DailyHealthBanner.swift
//  food-app-swift
//
//  "Health Coach" style daily banner shown on the Dashboard.
//  Designed to feel like a personal message from a health agent,
//  in line with the project direction of evolving from a passive
//  food tracker into a proactive health agent.
//
//  Phase 1: static persona-driven copy + compact CTAs.
//  Phase 2 (next): drive `message` from rule-based logic on the
//                  user's HealthProfile (BP, blood sugar, BMI...).
//  Phase 3 (later): replace with LLM-generated suggestion from backend.
//

import SwiftUI

struct DailyHealthBanner: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var session = SessionManager.shared

    var coachName: String = "Your Health Coach"
    var message: String = "I noticed your sodium intake yesterday was a bit high. Let's start today with a low-sodium breakfast — maybe oatmeal with berries instead of bacon and eggs?"

    var onAcknowledge: (() -> Void)? = nil
    var onLearnMore: (() -> Void)? = nil

    // Lets previews override the clock so we can showcase morning / afternoon / evening variants.
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

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            Text(personalGreeting)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)

            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(themeManager.current.primaryText.opacity(0.85))
                .lineSpacing(3)
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
                                colors: [Color.teal, Color.blue.opacity(0.85)],
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
                        .foregroundColor(themeManager.current.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule()
                                .stroke(themeManager.current.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            ZStack {
                themeManager.current.cardBackground
                LinearGradient(
                    colors: [
                        Color.teal.opacity(themeManager.current.isDark ? 0.18 : 0.10),
                        Color.blue.opacity(themeManager.current.isDark ? 0.10 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.current.cardBorder, lineWidth: 1)
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
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.teal.opacity(0.8))
        }
    }

    private var coachAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.teal, Color.blue.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
            Image(systemName: "stethoscope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(x: 14, y: 14)
        }
    }
}

// MARK: - Previews

private func previewDate(hour: Int) -> Date {
    var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    c.hour = hour
    c.minute = 0
    return Calendar.current.date(from: c) ?? Date()
}

#Preview("Morning (Light)") {
    VStack {
        DailyHealthBanner(nowOverride: previewDate(hour: 8))
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
            message: "Nice work on hitting your protein goal yesterday. For lunch today, try adding a side of leafy greens to balance your micronutrients.",
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
            message: "Your blood pressure trend this week is slightly elevated. A 20-minute walk after dinner could really help — want to log one tonight?",
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
            message: "I've been tracking your meals this week and noticed your average sodium intake is around 2,800mg — a bit above the 2,300mg recommended for adults. Since your last reading showed slightly elevated blood pressure, let's aim lower today. Try swapping processed snacks for fresh fruit, and go easy on soy sauce at dinner.",
            nowOverride: previewDate(hour: 9)
        )
        .padding()
        Spacer()
    }
    .background(AppTheme.light.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.light)
}
