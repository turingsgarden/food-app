import SwiftUI

// MARK: - Concern Labels

extension DailyComprehensivePlan {
    /// Short metric names for chips (e.g. "Systolic BP").
    var concernChipLabels: [String] {
        abnormalEvidence.map(\.metric)
    }

    /// Full line for footer / collapsed analysis (e.g. "Systolic BP (high) · Fasting Blood Sugar (high)").
    var concernSummaryLine: String {
        guard !abnormalEvidence.isEmpty else { return "" }
        return abnormalEvidence
            .map { "\($0.metric) (\($0.status))" }
            .joined(separator: " · ")
    }

    var hasConcernLabels: Bool { !concernChipLabels.isEmpty }
}

extension DailyTip {
    var basedOnDisplayText: String {
        let line = comprehensive.concernSummaryLine
        return line.isEmpty ? categoryLabel : line
    }

    var displayChipLabels: [String] {
        comprehensive.hasConcernLabels ? comprehensive.concernChipLabels : [categoryLabel]
    }
}

// MARK: - Shared Chips

struct DailyTipConcernChipsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let labels: [String]
    var fontSize: CGFloat = 11

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(themeManager.current.isDark ? .white : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                themeManager.current.isDark
                                    ? Color.orange.opacity(0.22)
                                    : Color.orange.opacity(0.12)
                            )
                        )
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Chat

struct DailyTipChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case coach, user }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct DailyTipChatSection: View {
    @EnvironmentObject var themeManager: ThemeManager
    let tip: DailyTip
    let dateKey: String
    let userId: String
    @Binding var isExpanded: Bool

    @State private var messages: [DailyTipChatMessage] = []
    @State private var draftText = ""
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool

    private let healthAPI = HealthAPIManager.shared

    init(
        tip: DailyTip,
        dateKey: String? = nil,
        userId: String? = nil,
        isExpanded: Binding<Bool>
    ) {
        self.tip = tip
        self.dateKey = dateKey ?? tip.dateKey
        self.userId = userId ?? SessionManager.shared.userID
        self._isExpanded = isExpanded
    }

    private let quickActions = [
        "Why these metrics?",
        "What should I eat tonight?",
        "Lifestyle tips"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !messages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                messageBubble(message)
                            }
                        }
                    }

                    quickActionRow

                    inputBar

                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.85)
                            Text("Coach is thinking…")
                                .font(.system(size: 11))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear(perform: loadMessages)
    }

    private func loadMessages() {
        guard !userId.isEmpty else {
            seedLocalMessagesIfNeeded()
            return
        }

        healthAPI.getDailyTipChatHistory(dateKey: dateKey) { remote, _ in
            if let remote, !remote.isEmpty {
                messages = remote
                persistMessages()
                return
            }

            let saved = DailyTipChatStore.load(userId: userId, dateKey: dateKey)
            if saved.isEmpty {
                seedLocalMessagesIfNeeded()
            } else {
                messages = saved
            }
        }
    }

    private func seedLocalMessagesIfNeeded() {
        messages = [DailyTipChatMessage(role: .coach, text: seededCoachMessage)]
        persistMessages()
    }

    private func persistMessages() {
        DailyTipChatStore.save(messages: messages, userId: userId, dateKey: dateKey)
    }

    private var headerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health Coach Chat")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    if !isExpanded {
                        Text("Ask about your plan")
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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
    }

    private func messageBubble(_ message: DailyTipChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 14))
                .foregroundColor(message.role == .coach ? sectionBodyColor : .white)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(message.role == .coach
                              ? (themeManager.current.isDark ? Color.white.opacity(0.08) : Color.gray.opacity(0.1))
                              : Color.orange)
                )
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .coach { Spacer(minLength: 40) }
        }
    }

    private var quickActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickActions, id: \.self) { action in
                    Button {
                        sendQuickAction(action)
                    } label: {
                        Text(action)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeManager.current.isDark ? .white : .orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().stroke(
                                    themeManager.current.isDark ? Color.white.opacity(0.25) : Color.orange.opacity(0.45),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your health plan…", text: $draftText, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.current.inputBackground)
                )
                .focused($isInputFocused)
                .disabled(isSending)

            Button(action: sendDraftMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.orange.opacity(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.35 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }

    private var seededCoachMessage: String {
        if let seed = tip.chatSeed?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
            return seed
        }
        let concerns = tip.comprehensive.concernSummaryLine
        if concerns.isEmpty {
            return "Hi! Today's priority: \(tip.shortText) Ask me anything about your plan."
        }
        return "I reviewed \(concerns). Today's priority: \(tip.shortText) Tap a quick question below or type your own."
    }

    private func sendQuickAction(_ action: String) {
        appendUserMessage(action)
        requestCoachReply(fallback: localReply(for: action))
    }

    private func sendDraftMessage() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendUserMessage(text)
        draftText = ""
        isInputFocused = false
        requestCoachReply(fallback: localReply(for: text))
    }

    private func appendUserMessage(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(DailyTipChatMessage(role: .user, text: text))
        }
        persistMessages()
    }

    private func appendCoachMessage(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(DailyTipChatMessage(role: .coach, text: text))
        }
        persistMessages()
    }

    private func requestCoachReply(fallback: String) {
        guard !userId.isEmpty else {
            appendCoachMessage(fallback)
            return
        }

        isSending = true
        let payload = messages.map { (role: $0.role.rawValue, text: $0.text) }

        healthAPI.dailyTipChat(
            messages: payload,
            dateKey: dateKey,
            tipSnapshot: tip
        ) { reply, error in
            isSending = false
            if let reply, !reply.isEmpty {
                appendCoachMessage(reply)
            } else {
                appendCoachMessage(fallback)
                _ = error
            }
        }
    }

    private func localReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        let plan = tip.comprehensive

        if lower.contains("why") || lower.contains("metric") {
            if !plan.associationSummary.isEmpty { return plan.associationSummary }
            return tip.whyThisMatters
        }
        if lower.contains("eat") || lower.contains("dinner") || lower.contains("diet") || lower.contains("food") {
            if !plan.dietSteps.isEmpty {
                return plan.dietSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            }
            return tip.detailText
        }
        if lower.contains("lifestyle") || lower.contains("walk") || lower.contains("sleep") {
            if !plan.lifestyleSteps.isEmpty {
                return plan.lifestyleSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            }
            return "Take a short walk after a meal and stay hydrated through the day."
        }
        return "Based on your plan today: \(tip.shortText)"
    }

    private var sectionBodyColor: Color {
        themeManager.current.isDark ? Color.white.opacity(0.9) : themeManager.current.primaryText.opacity(0.92)
    }
}
