import SwiftUI

struct DailyHealthBanner: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var session = SessionManager.shared

    var coachName: String = "Your Health Coach"
    let tip: DailyTip
    @Binding var selectedMetricID: String?

    var onAcknowledge: (() -> Void)? = nil
    var onLearnMore: (() -> Void)? = nil

    var nowOverride: Date? = nil

    @State private var showMetricRing = false

    init(
        tip: DailyTip,
        selectedMetricID: Binding<String?> = .constant(nil),
        coachName: String = "Your Health Coach",
        onAcknowledge: (() -> Void)? = nil,
        onLearnMore: (() -> Void)? = nil,
        nowOverride: Date? = nil
    ) {
        self.tip = tip
        self._selectedMetricID = selectedMetricID
        self.coachName = coachName
        self.onAcknowledge = onAcknowledge
        self.onLearnMore = onLearnMore
        self.nowOverride = nowOverride
    }

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

    private var slotAccentGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: now)
        let colors: [Color]
        switch hour {
        case 0..<12:
            colors = [Color.orange.opacity(0.95), Color.yellow.opacity(0.85)]
        case 12..<17:
            colors = [Color.orange.opacity(0.9), Color.orange.opacity(0.7)]
        default:
            colors = [Color.orange.opacity(0.9), Color.orange.opacity(0.65)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private var metricEvidence: [DailyMetricEvidence] {
        tip.comprehensive.abnormalEvidence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            Text(personalGreeting)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)

            // Keep homepage message short and scannable.
            Text(tip.shortText)
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

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: tip.iconSystemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(themeManager.current.isDark ? Color.white.opacity(0.68) : themeManager.current.secondaryText)
                    .padding(.top, 2)
                Text("Based on \(tip.basedOnDisplayText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(themeManager.current.isDark ? Color.white.opacity(0.68) : themeManager.current.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            ZStack {
                cardBackground
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.current.isDark ? Color.orange.opacity(0.08) : Color.orange.opacity(0.05))
            }
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.current.isDark ? Color.orange.opacity(0.38) : Color.orange.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(slotAccentGradient)
                .frame(height: 3)
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            coachAvatar
            Text(coachName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
            Spacer(minLength: 0)
            MetricRingPopover(
                evidence: metricEvidence,
                selectedMetricID: $selectedMetricID,
                isPresented: $showMetricRing
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
    @Environment(\.dismiss) private var dismiss
    let tip: DailyTip
    var screenTitle: String = "Today's health plan"
    var onOpenHistory: (() -> Void)? = nil
    var expandChatOnAppear: Bool = false
    var initialMetricID: String? = nil

    @State private var isAnalysisExpanded = false
    @State private var isChatExpanded = false
    @State private var selectedMetricID: String?
    @State private var showMetricRing = false

    private var metricEvidence: [DailyMetricEvidence] {
        tip.comprehensive.abnormalEvidence
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    priorityCard

                    if tip.comprehensive.hasExpandableAnalysis {
                        collapsibleAnalysisSection
                    }

                    DailyTipChatSection(
                        tip: tip,
                        dateKey: tip.dateKey,
                        isExpanded: $isChatExpanded
                    )

                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Got it")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.82)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(themeManager.current.background.ignoresSafeArea())
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onOpenHistory {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenHistory) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel("Tip history")
                    }
                }
            }
            .onAppear {
                selectedMetricID = initialMetricID
                if expandChatOnAppear {
                    isChatExpanded = true
                }
            }
        }
    }

    private var collapsibleAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isAnalysisExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analysis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(themeManager.current.primaryText)
                        if !isAnalysisExpanded {
                            Text(tip.comprehensive.collapsedSummary)
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.current.secondaryText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isAnalysisExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.current.isDark ? Color.white.opacity(0.06) : Color.gray.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            if isAnalysisExpanded {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(themeManager.current.isDark ? Color.white.opacity(0.22) : Color.gray.opacity(0.35))
                        .frame(width: 2)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 16) {
                        analysisTabBar

                        if selectedMetricID == nil {
                            overallAnalysisContent
                        } else if let metric = metricEvidence.first(where: { $0.id == selectedMetricID }) {
                            metricAnalysisContent(metric)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.current.secondaryText)
                            Text("Analysis complete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                MetricRingPopover(
                    evidence: metricEvidence,
                    selectedMetricID: $selectedMetricID,
                    isPresented: $showMetricRing
                )
            }

            Text(tip.shortText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(tip.detailText)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(sectionBodyColor)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.current.isDark ? Color.orange.opacity(0.12) : Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(themeManager.current.isDark ? Color.orange.opacity(0.28) : Color.clear, lineWidth: 1)
                )
        )
        .onChange(of: selectedMetricID) { _, newValue in
            if newValue != nil {
                isAnalysisExpanded = true
            }
        }
    }

    private var analysisTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                analysisTabButton(title: "Overall", metricID: nil)
                ForEach(metricEvidence) { item in
                    analysisTabButton(title: item.shortTabTitle, metricID: item.id)
                }
            }
        }
    }

    private func analysisTabButton(title: String, metricID: String?) -> some View {
        let isSelected = selectedMetricID == metricID
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMetricID = metricID
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : (themeManager.current.isDark ? .white.opacity(0.85) : .orange))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.orange : Color.orange.opacity(themeManager.current.isDark ? 0.18 : 0.1))
                )
        }
        .buttonStyle(.plain)
    }

    private var overallAnalysisContent: some View {
        Group {
            if tip.comprehensive.hasAbnormalMetrics {
                metricsSection
            }

            if let patternTitle = tip.comprehensive.pattern.title {
                section(title: patternTitle, body: tip.comprehensive.associationSummary)
            } else if !tip.comprehensive.associationSummary.isEmpty {
                section(title: "How this fits together", body: tip.comprehensive.associationSummary)
            }

            if !tip.comprehensive.dietSteps.isEmpty {
                numberedSection(title: "Diet — step by step", steps: tip.comprehensive.dietSteps)
            }

            if !tip.comprehensive.lifestyleSteps.isEmpty {
                numberedSection(title: "Lifestyle — step by step", steps: tip.comprehensive.lifestyleSteps)
            }

            if let reportSummary = tip.comprehensive.reportSummary {
                section(title: "From your health report", body: reportSummary)
            }
        }
    }

    @ViewBuilder
    private func metricAnalysisContent(_ metric: DailyMetricEvidence) -> some View {
        let aiPlan = tip.comprehensive.plan(for: metric)
        Group {
            section(
                title: metric.shortTabTitle,
                body: aiPlan?.summary ?? metric.bulletLine
            )

            if let advice = metric.advice, !advice.isEmpty {
                section(title: "What this means", body: advice)
            } else if aiPlan?.summary == nil, !tip.comprehensive.associationSummary.isEmpty {
                section(title: "Context", body: tip.comprehensive.associationSummary)
            }

            numberedSection(
                title: "Diet — focused on \(metric.shortTabTitle)",
                steps: tip.comprehensive.dietSteps(for: metric)
            )

            numberedSection(
                title: "Lifestyle — focused on \(metric.shortTabTitle)",
                steps: tip.comprehensive.lifestyleSteps(for: metric)
            )
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your metrics today")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(sectionTitleColor)

            ForEach(tip.comprehensive.abnormalEvidence) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item.bulletLine)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(sectionBodyColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let advice = item.advice, !advice.isEmpty {
                        Text(advice)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.secondaryText)
                            .lineSpacing(3)
                            .padding(.leading, 14)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(sectionTitleColor)
            Text(body)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(sectionBodyColor)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberedSection(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(sectionTitleColor)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.orange))
                    Text(step)
                        .font(.system(size: 15))
                        .foregroundColor(sectionBodyColor)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sectionTitleColor: Color {
        themeManager.current.isDark ? Color.white.opacity(0.72) : themeManager.current.secondaryText
    }

    private var sectionBodyColor: Color {
        themeManager.current.isDark ? Color.white.opacity(0.9) : themeManager.current.primaryText.opacity(0.92)
    }
}

// MARK: - History

struct DailyTipHistoryListView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tipManager: DailyTipManager

    @State private var selectedEntry: DailyTipHistoryEntry?

    var body: some View {
        NavigationStack {
            Group {
                if tipManager.historyEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                        Text("No saved tips yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.current.primaryText)
                        Text("Open the dashboard and refresh your health data. Each day’s tip is saved automatically.")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.current.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(tipManager.historyEntries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            Text(entry.displayDate)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(themeManager.current.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(themeManager.current.background.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                DailyTipDetailSheetView(
                    tip: entry.tip,
                    screenTitle: entry.displayDate,
                    initialMetricID: nil
                )
                .environmentObject(themeManager)
            }
            .onAppear { tipManager.reloadHistory() }
        }
    }
}

private func previewDate(hour: Int) -> Date {
    var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    c.hour = hour
    c.minute = 0
    return Calendar.current.date(from: c) ?? Date()
}

private func previewTip(
    category: DailyTipCategory = .general,
    label: String = "Daily Tip",
    short: String,
    detail: String = "Detailed suggestion goes here.",
    icon: String = "sparkles"
) -> DailyTip {
    DailyTip(
        id: "preview_\(category.rawValue)",
        category: category,
        categoryLabel: label,
        shortText: short,
        detailText: detail,
        whyThisMatters: "Preview reason",
        suggestedAction: nil,
        iconSystemName: icon,
        comprehensive: .empty
    )
}

#Preview("Morning (Light)") {
    VStack {
        DailyHealthBanner(
            tip: previewTip(
                category: .cholesterol,
                label: "Cholesterol",
                short: "Morning Bella! Try oatmeal — it helps support healthy cholesterol.",
                icon: "waveform.path.ecg"
            ),
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
            tip: previewTip(
                category: .weight,
                label: "Weight Goal",
                short: "Keep lunch simple today: one lean protein + one green vegetable.",
                icon: "scalemass.fill"
            ),
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
            tip: previewTip(
                category: .sodium,
                label: "Low Sodium",
                short: "Try a light dinner tonight and keep sodium lower than yesterday.",
                icon: "heart.fill"
            ),
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
            tip: previewTip(
                category: .general,
                label: "Daily Tip",
                short: "Small change today: swap one processed snack for fruit."
            ),
            nowOverride: previewDate(hour: 9)
        )
        .padding()
        Spacer()
    }
    .background(AppTheme.light.background)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.light)
}
