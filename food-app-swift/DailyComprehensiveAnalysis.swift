import Foundation

// MARK: - Evidence & Plan

/// One abnormal metric row for the detail sheet.
struct DailyMetricEvidence: Codable, Equatable, Identifiable {
    let id: String
    let metric: String
    let status: String
    let currentValue: String
    let advice: String?

    enum CodingKeys: String, CodingKey {
        case id, metric, status, advice
        case currentValue = "current_value"
    }

    init(id: String, metric: String, status: String, currentValue: String, advice: String?) {
        self.id = id
        self.metric = metric
        self.status = status
        self.currentValue = currentValue
        self.advice = advice
    }

    init(from context: AbnormalMetricContext) {
        self.init(
            id: context.id,
            metric: context.metric,
            status: context.status.replacingOccurrences(of: "_", with: " "),
            currentValue: context.currentValue,
            advice: context.advice
        )
    }

    var bulletLine: String {
        "\(metric) — \(status) — \(currentValue)"
    }
}

/// Rule-detected cluster label shown when multiple cardio-metabolic markers align.
enum MetabolicPattern: String, Codable {
    case threeHighs
    case metabolicPair
    case multipleMetrics
    case singleFocus
    case generalWellness

    var title: String? {
        switch self {
        case .threeHighs:
            return "Metabolic risk cluster (often called \"three highs\")"
        case .metabolicPair:
            return "Combined metabolic risk"
        case .multipleMetrics:
            return "Multiple areas need attention"
        case .singleFocus, .generalWellness:
            return nil
        }
    }
}

/// AI-generated per-metric plan (optional; rule engine may omit).
struct DailyPerMetricPlan: Codable, Equatable, Identifiable {
    let id: String
    let metric: String
    let summary: String
    let dietSteps: [String]
    let lifestyleSteps: [String]

    enum CodingKeys: String, CodingKey {
        case id, metric, summary
        case dietSteps = "diet_steps"
        case lifestyleSteps = "lifestyle_steps"
    }
}

/// Structured comprehensive guidance for Tell me more.
struct DailyComprehensivePlan: Codable, Equatable {
    let abnormalEvidence: [DailyMetricEvidence]
    let pattern: MetabolicPattern
    let associationSummary: String
    let dietSteps: [String]
    let lifestyleSteps: [String]
    let reportSummary: String?
    let perMetricPlans: [DailyPerMetricPlan]

    enum CodingKeys: String, CodingKey {
        case pattern
        case abnormalEvidence = "abnormal_evidence"
        case associationSummary = "association_summary"
        case dietSteps = "diet_steps"
        case lifestyleSteps = "lifestyle_steps"
        case reportSummary = "report_summary"
        case perMetricPlans = "per_metric_plans"
    }

    init(
        abnormalEvidence: [DailyMetricEvidence],
        pattern: MetabolicPattern,
        associationSummary: String,
        dietSteps: [String],
        lifestyleSteps: [String],
        reportSummary: String?,
        perMetricPlans: [DailyPerMetricPlan] = []
    ) {
        self.abnormalEvidence = abnormalEvidence
        self.pattern = pattern
        self.associationSummary = associationSummary
        self.dietSteps = dietSteps
        self.lifestyleSteps = lifestyleSteps
        self.reportSummary = reportSummary
        self.perMetricPlans = perMetricPlans
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        abnormalEvidence = try container.decode([DailyMetricEvidence].self, forKey: .abnormalEvidence)
        pattern = try container.decode(MetabolicPattern.self, forKey: .pattern)
        associationSummary = try container.decode(String.self, forKey: .associationSummary)
        dietSteps = try container.decode([String].self, forKey: .dietSteps)
        lifestyleSteps = try container.decode([String].self, forKey: .lifestyleSteps)
        reportSummary = try container.decodeIfPresent(String.self, forKey: .reportSummary)
        perMetricPlans = try container.decodeIfPresent([DailyPerMetricPlan].self, forKey: .perMetricPlans) ?? []
    }

    static let empty = DailyComprehensivePlan(
        abnormalEvidence: [],
        pattern: .generalWellness,
        associationSummary: "",
        dietSteps: [],
        lifestyleSteps: [],
        reportSummary: nil,
        perMetricPlans: []
    )

    func plan(for metric: DailyMetricEvidence) -> DailyPerMetricPlan? {
        perMetricPlans.first { $0.id == metric.id }
    }
}

// MARK: - Focus-aware copy

extension DailyTip {
    func focusedMetric(_ id: String?) -> DailyMetricEvidence? {
        guard let id else { return nil }
        return comprehensive.abnormalEvidence.first { $0.id == id }
    }

    /// Headline honoring the selected focus metric (detail sheet title).
    func headline(focus id: String?) -> String {
        guard let metric = focusedMetric(id) else { return shortText }
        return "Today's focus: \(metric.shortTabTitle)"
    }

    /// Body copy honoring the selected focus metric.
    func detailBody(focus id: String?) -> String {
        guard let metric = focusedMetric(id) else { return detailText }
        if let plan = comprehensive.plan(for: metric), !plan.summary.isEmpty {
            return plan.summary
        }
        if let advice = metric.advice, !advice.isEmpty { return advice }
        return detailText
    }

    /// Banner one-liner honoring the selected focus metric.
    func bannerText(focus id: String?) -> String {
        guard let metric = focusedMetric(id) else { return shortText }
        if let plan = comprehensive.plan(for: metric), !plan.summary.isEmpty {
            return plan.summary
        }
        if let advice = metric.advice, !advice.isEmpty { return advice }
        return shortText
    }
}

extension DailyComprehensivePlan {
    var hasAbnormalMetrics: Bool { !abnormalEvidence.isEmpty }

    /// One-line summary shown when analysis is collapsed — lists every flagged metric.
    var collapsedSummary: String {
        if abnormalEvidence.isEmpty {
            return "Reviewed your health profile"
        }
        let names = abnormalEvidence
            .map { "\($0.metric) (\($0.status))" }
            .joined(separator: " · ")
        if let title = pattern.title {
            return "\(names) · \(title)"
        }
        return names
    }

    var hasExpandableAnalysis: Bool {
        hasAbnormalMetrics
            || !associationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !dietSteps.isEmpty
            || !lifestyleSteps.isEmpty
            || reportSummary != nil
    }
}

extension DailyComprehensivePlan {
    /// Metric-specific diet guidance — prefers AI per-metric plan when present.
    func dietSteps(for metric: DailyMetricEvidence) -> [String] {
        if let plan = plan(for: metric), !plan.dietSteps.isEmpty {
            return plan.dietSteps
        }
        let name = metric.metric.lowercased()
        var focused: [String] = []

        if name.contains("blood pressure") || name.contains("systolic") || name.contains("diastolic") {
            focused.append("Reduce added salt and sauces — aim for a low-sodium main meal today.")
        }
        if name.contains("blood sugar") || name.contains("glucose") || name.contains("sugar") {
            focused.append("Pair carbohydrates with protein or fiber to avoid sharp glucose spikes.")
        }
        if name.contains("cholesterol") || name.contains("lipid") || name.contains("triglyceride") {
            focused.append("Choose soluble fiber (oats, beans, barley) and limit fried or processed fats.")
        }
        if name.contains("bmi") || name.contains("weight") {
            focused.append("Keep portions moderate and build meals around lean protein plus vegetables.")
        }

        if focused.isEmpty {
            return dietSteps.isEmpty ? ["Follow your overall plan for today's meals."] : Array(dietSteps.prefix(3))
        }
        return focused + Array(dietSteps.prefix(2))
    }

    func lifestyleSteps(for metric: DailyMetricEvidence) -> [String] {
        if let plan = plan(for: metric), !plan.lifestyleSteps.isEmpty {
            return plan.lifestyleSteps
        }
        let name = metric.metric.lowercased()
        if name.contains("blood pressure") || name.contains("systolic") {
            return [
                "Take a 10–15 minute walk after your largest meal.",
                "Limit alcohol and heavy late-night meals."
            ] + Array(lifestyleSteps.prefix(1))
        }
        if name.contains("blood sugar") || name.contains("glucose") {
            return [
                "Take a short walk after carb-heavy meals.",
                "Avoid large refined-carb snacks late in the evening."
            ] + Array(lifestyleSteps.prefix(1))
        }
        return lifestyleSteps.isEmpty
            ? ["Take a short walk today and stay hydrated."]
            : Array(lifestyleSteps.prefix(3))
    }
}


// MARK: - Builder

/// Builds cross-metric association copy and step-by-step plans from Health Report data.
enum DailyComprehensiveAnalysisBuilder {

    static func build(
        context: DailyTipContext,
        primary tip: DailyTip,
        reportSummary: String?,
        reportLifestyleTip: String?
    ) -> DailyComprehensivePlan {
        var evidence = context.abnormalMetrics.map(DailyMetricEvidence.init(from:))
        if evidence.isEmpty {
            evidence = profileDerivedEvidence(context: context)
        }
        let flags = MetabolicFlags(context: context)
        let pattern = detectPattern(flags: flags, abnormalCount: evidence.count)

        let association = associationSummary(
            pattern: pattern,
            flags: flags,
            evidence: evidence,
            tip: tip,
            context: context
        )
        let diet = dietSteps(pattern: pattern, flags: flags, tip: tip, context: context)
        let lifestyle = lifestyleSteps(
            pattern: pattern,
            flags: flags,
            reportLifestyleTip: reportLifestyleTip,
            context: context
        )
        let trimmedReport = reportSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = (trimmedReport?.isEmpty == false) ? trimmedReport : nil

        return DailyComprehensivePlan(
            abnormalEvidence: evidence,
            pattern: pattern,
            associationSummary: association,
            dietSteps: diet,
            lifestyleSteps: lifestyle,
            reportSummary: report
        )
    }
}

// MARK: - Metabolic Flags

private struct MetabolicFlags {
    let hasBloodPressure: Bool
    let hasBloodSugar: Bool
    let hasLipids: Bool
    let hasWeight: Bool

    init(context: DailyTipContext) {
        hasBloodPressure = context.matchesDomain(
            abnormal: ["blood pressure", "systolic", "diastolic", "bp"],
            goal: .lowerBloodPressure,
            profileCheck: { p in
                (p.systolicBP.map { $0 >= 130 } ?? false) || (p.diastolicBP.map { $0 >= 85 } ?? false)
            }
        )
        hasBloodSugar = context.matchesDomain(
            abnormal: ["blood sugar", "fasting sugar", "glucose"],
            goal: .controlBloodSugar,
            profileCheck: { ($0.fastingBloodSugar ?? 0) > 5.5 }
        )
        hasLipids = context.matchesDomain(
            abnormal: ["cholesterol", "triglyceride", "lipid"],
            goal: .lowerCholesterol,
            profileCheck: { ($0.totalCholesterol ?? 0) > 5.2 }
        )
        hasWeight = context.matchesDomain(
            abnormal: ["bmi", "weight"],
            goal: .loseWeight,
            profileCheck: { $0.bmi >= 25 }
        )
    }

    var metabolicCount: Int {
        [hasBloodPressure, hasBloodSugar, hasLipids].filter { $0 }.count
    }
}

private extension DailyTipContext {
    func matchesDomain(
        abnormal keywords: [String],
        goal: HealthGoal,
        profileCheck: (HealthProfile) -> Bool
    ) -> Bool {
        if abnormalMetrics.contains(where: { m in
            let name = m.metric.lowercased()
            return keywords.contains { name.contains($0.lowercased()) }
        }) { return true }
        if goals.contains(goal) { return true }
        if let profile, profileCheck(profile) { return true }
        return false
    }
}

// MARK: - Profile Evidence

private extension DailyComprehensiveAnalysisBuilder {

    static func profileDerivedEvidence(context: DailyTipContext) -> [DailyMetricEvidence] {
        guard let profile = context.profile else { return [] }
        var rows: [DailyMetricEvidence] = []

        if let systolic = profile.systolicBP, systolic >= 130 {
            rows.append(DailyMetricEvidence(
                id: "profile_systolic_bp",
                metric: "Systolic BP",
                status: "elevated",
                currentValue: "\(systolic) mmHg",
                advice: "From your health profile — confirm with your latest health report when available."
            ))
        }
        if let sugar = profile.fastingBloodSugar, sugar > 5.5 {
            rows.append(DailyMetricEvidence(
                id: "profile_fasting_sugar",
                metric: "Fasting Blood Sugar",
                status: sugar > 6.9 ? "high" : "borderline",
                currentValue: String(format: "%.1f mmol/L", sugar),
                advice: nil
            ))
        }
        if let cholesterol = profile.totalCholesterol, cholesterol > 5.2 {
            rows.append(DailyMetricEvidence(
                id: "profile_cholesterol",
                metric: "Total Cholesterol",
                status: "elevated",
                currentValue: String(format: "%.1f mmol/L", cholesterol),
                advice: nil
            ))
        }
        if profile.bmi >= 25 {
            rows.append(DailyMetricEvidence(
                id: "profile_bmi",
                metric: "BMI",
                status: profile.bmiCategory.lowercased(),
                currentValue: String(format: "%.1f", profile.bmi),
                advice: nil
            ))
        }
        return rows
    }
}

// MARK: - Pattern Detection

private extension DailyComprehensiveAnalysisBuilder {

    static func detectPattern(flags: MetabolicFlags, abnormalCount: Int) -> MetabolicPattern {
        if flags.metabolicCount >= 3 { return .threeHighs }
        if flags.metabolicCount == 2 { return .metabolicPair }
        if abnormalCount >= 2 { return .multipleMetrics }
        if abnormalCount == 1 { return .singleFocus }
        return .generalWellness
    }

    static func associationSummary(
        pattern: MetabolicPattern,
        flags: MetabolicFlags,
        evidence: [DailyMetricEvidence],
        tip: DailyTip,
        context: DailyTipContext
    ) -> String {
        switch pattern {
        case .threeHighs:
            return """
            Your blood pressure, blood sugar, and cholesterol-related markers are all outside the optimal range at the same time. In everyday language this pattern is often called the "three highs," and it overlaps with metabolic syndrome risk.

            These markers tend to respond to the same lifestyle drivers: sodium-heavy or processed foods, refined carbohydrates, low fiber, and low daily movement. Today's priority focuses on \(tip.categoryLabel.lowercased()), while the steps below address the full picture.
            """
        case .metabolicPair:
            let pair = metabolicPairDescription(flags: flags)
            return """
            \(pair) are both relevant for you right now. They often share dietary causes (salt, refined carbs, saturated fat) and improve together with consistent meal structure and activity.

            Use the steps below as a combined plan. Your banner highlights today's most practical first step: \(tip.shortText)
            """
        case .multipleMetrics:
            let names = evidence.map(\.metric).joined(separator: ", ")
            return """
            Several metrics need attention today (\(names)). They may not all share one label, but steady meals, fiber, lean protein, and regular walks support most of them.

            \(tip.whyThisMatters)
            """
        case .singleFocus:
            return tip.whyThisMatters
        case .generalWellness:
            if evidence.isEmpty {
                return tip.whyThisMatters
            }
            return tip.whyThisMatters
        }
    }

    static func metabolicPairDescription(flags: MetabolicFlags) -> String {
        var parts: [String] = []
        if flags.hasBloodPressure { parts.append("blood pressure") }
        if flags.hasBloodSugar { parts.append("blood sugar") }
        if flags.hasLipids { parts.append("cholesterol / lipids") }
        if parts.count >= 2 {
            return parts[0].capitalized + " and " + parts[1]
        }
        return "Multiple metabolic markers"
    }

    static func dietSteps(
        pattern: MetabolicPattern,
        flags: MetabolicFlags,
        tip: DailyTip,
        context: DailyTipContext
    ) -> [String] {
        switch pattern {
        case .threeHighs, .metabolicPair:
            var steps = [
                "Keep added salt and sauces low today — favor herbs, lemon, and pepper for flavor.",
                "Build each main meal with lean protein, two vegetables, and a modest portion of whole grains or starchy carbs.",
                "Choose soluble fiber daily (oats, beans, lentils, barley) to support cholesterol and blood sugar stability.",
                "Limit fried foods, processed meats, sugary drinks, and large refined-carb portions (white bread, pastries, sweet cereals)."
            ]
            if flags.hasBloodPressure {
                steps.append("If eating out, ask for sauces on the side and skip extra salty sides.")
            }
            steps.append("Align with today's focus: \(tip.detailText)")
            return steps
        case .multipleMetrics, .singleFocus:
            return [
                tip.detailText,
                "Log your next main meal so you can review portions and balance over the week.",
                "Aim for at least one vegetable or fruit serving at each meal today."
            ]
        case .generalWellness:
            return [
                tip.detailText,
                "Keep meals balanced: protein + fiber + colorful produce at \(TimeSlotLabel.from(date: context.date))."
            ]
        }
    }

    static func lifestyleSteps(
        pattern: MetabolicPattern,
        flags: MetabolicFlags,
        reportLifestyleTip: String?,
        context: DailyTipContext
    ) -> [String] {
        var steps: [String] = []

        switch pattern {
        case .threeHighs, .metabolicPair:
            steps = [
                "Take a 10–15 minute walk after your largest meal today.",
                "Prioritize 7–8 hours of sleep — poor sleep can affect blood pressure and glucose control.",
                "If you drink alcohol, keep it modest and not close to bedtime.",
                "Check blood pressure or glucose per your care plan if you usually track at home."
            ]
        case .multipleMetrics, .singleFocus:
            steps = [
                "Take a short walk after at least one meal today.",
                "Drink water steadily through the day instead of large amounts late at night."
            ]
        case .generalWellness:
            steps = [
                "Take a 10-minute walk after a meal if you can.",
                "Drink a glass of water before your next coffee or snack."
            ]
        }

        if let report = reportLifestyleTip?.trimmingCharacters(in: .whitespacesAndNewlines),
           !report.isEmpty {
            steps.append("From your health report: \(report)")
        }

        if let goal = context.goals.first {
            steps.append("Your active goal reminder: focus on \(goal.displayName.lowercased()) this week.")
        }

        return steps
    }
}

private enum TimeSlotLabel {
    static func from(date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<12: return "breakfast"
        case 12..<17: return "lunch"
        default: return "dinner"
        }
    }
}
