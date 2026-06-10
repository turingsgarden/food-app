import Foundation

// MARK: - Public Types

/// Category of a generated daily tip. Drives the chip color and icon in the UI.
enum DailyTipCategory: String, Codable {
    case sodium
    case cholesterol
    case bloodSugar
    case weight
    case fiber
    case hydration
    case general
}

/// Final tip object consumed by the Banner and the detail sheet.
struct DailyTip: Identifiable, Codable {
    /// Stable id of the form "yyyy-MM-dd_<category>". Allows day-based persistence.
    let id: String
    let category: DailyTipCategory
    let categoryLabel: String
    /// Homepage banner: one scannable priority action for today.
    let shortText: String
    let detailText: String
    let whyThisMatters: String
    let suggestedAction: String?
    let iconSystemName: String
    /// Optional opening line for Health Coach Chat (from AI backend).
    let chatSeed: String?
    /// Tell me more: all abnormal metrics, cross-metric association, and step plans.
    let comprehensive: DailyComprehensivePlan

    enum CodingKeys: String, CodingKey {
        case id, category, comprehensive
        case categoryLabel = "category_label"
        case shortText = "short_text"
        case detailText = "detail_text"
        case whyThisMatters = "why_this_matters"
        case suggestedAction = "suggested_action"
        case iconSystemName = "icon_system_name"
        case chatSeed = "chat_seed"
    }

    init(
        id: String,
        category: DailyTipCategory,
        categoryLabel: String,
        shortText: String,
        detailText: String,
        whyThisMatters: String,
        suggestedAction: String?,
        iconSystemName: String,
        comprehensive: DailyComprehensivePlan,
        chatSeed: String? = nil
    ) {
        self.id = id
        self.category = category
        self.categoryLabel = categoryLabel
        self.shortText = shortText
        self.detailText = detailText
        self.whyThisMatters = whyThisMatters
        self.suggestedAction = suggestedAction
        self.iconSystemName = iconSystemName
        self.chatSeed = chatSeed
        self.comprehensive = comprehensive
    }
}

/// Inputs required to compute today's tip. Kept as a value type so the engine
/// stays a pure function and can be unit-tested or swapped for an LLM provider.
struct DailyTipContext {
    let profile: HealthProfile?
    let goals: [HealthGoal]
    let abnormalMetrics: [AbnormalMetricContext]
    let date: Date
    let healthSummary: String?
    let reportLifestyleTip: String?

    init(
        profile: HealthProfile?,
        goals: [HealthGoal] = [],
        abnormalMetrics: [AbnormalMetricContext] = [],
        date: Date = Date(),
        healthSummary: String? = nil,
        reportLifestyleTip: String? = nil
    ) {
        self.profile = profile
        self.goals = goals
        self.abnormalMetrics = abnormalMetrics
        self.date = date
        self.healthSummary = healthSummary
        self.reportLifestyleTip = reportLifestyleTip
    }
}

// MARK: - Engine

/// Rule-based daily tip generator.
///
/// Priority is intentionally fixed so the output is deterministic:
/// blood pressure -> cholesterol -> blood sugar -> weight -> digestion ->
/// energy -> general fallback.
///
/// Phase 3 may replace this with a remote LLM provider; the public API should
/// stay the same so the UI does not need to change.
enum DailyTipEngine {

    /// Returns the tip to show for the given context.
    /// Safe to call with a nil profile — falls back to a general time-of-day tip.
    static func recommend(for context: DailyTipContext) -> DailyTip {
        let slot = TimeSlot.from(date: context.date)
        let dateKey = Self.dateKey(from: context.date)

        let base: DailyTip
        if shouldFocusOnSodium(context) {
            base = makeSodiumTip(slot: slot, dateKey: dateKey, context: context)
        } else if shouldFocusOnCholesterol(context) {
            base = makeCholesterolTip(slot: slot, dateKey: dateKey, context: context)
        } else if shouldFocusOnBloodSugar(context) {
            base = makeBloodSugarTip(slot: slot, dateKey: dateKey, context: context)
        } else if shouldFocusOnWeight(context) {
            base = makeWeightTip(slot: slot, dateKey: dateKey, context: context)
        } else if context.goals.contains(.improveDigestion) {
            base = makeFiberTip(slot: slot, dateKey: dateKey)
        } else if context.goals.contains(.boostEnergy) {
            base = makeHydrationTip(slot: slot, dateKey: dateKey)
        } else {
            base = makeGeneralTip(slot: slot, dateKey: dateKey)
        }

        return base.withComprehensive(
            DailyComprehensiveAnalysisBuilder.build(
                context: context,
                primary: base,
                reportSummary: context.healthSummary,
                reportLifestyleTip: context.reportLifestyleTip
            )
        )
    }
}

// MARK: - Comprehensive Attachment

private extension DailyTip {
    func withComprehensive(_ plan: DailyComprehensivePlan) -> DailyTip {
        DailyTip(
            id: id,
            category: category,
            categoryLabel: categoryLabel,
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: whyThisMatters,
            suggestedAction: suggestedAction,
            iconSystemName: iconSystemName,
            comprehensive: plan,
            chatSeed: chatSeed
        )
    }
}

// MARK: - Time-of-day

private enum TimeSlot {
    case morning, afternoon, evening

    static func from(date: Date) -> TimeSlot {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<12:  return .morning
        case 12..<17: return .afternoon
        default:      return .evening
        }
    }

    /// Used inside copy strings to make the tip context-aware.
    var mealName: String {
        switch self {
        case .morning:   return "breakfast"
        case .afternoon: return "lunch"
        case .evening:   return "dinner"
        }
    }
}

// MARK: - Date Key

private extension DailyTipEngine {
    /// Local-time day key, used both for the tip id and for "dismissed today" logic.
    static func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func makeId(dateKey: String, category: DailyTipCategory) -> String {
        "\(dateKey)_\(category.rawValue)"
    }
}

// MARK: - Abnormal Metric Matching

private extension DailyTipContext {
    func hasAbnormalMetric(matching keywords: [String]) -> Bool {
        firstAbnormalMetric(matching: keywords) != nil
    }

    func firstAbnormalMetric(matching keywords: [String]) -> AbnormalMetricContext? {
        abnormalMetrics.first { metric in
            let normalizedMetric = metric.metric.lowercased()
            return keywords.contains { normalizedMetric.contains($0.lowercased()) }
        }
    }
}

// MARK: - Rule Predicates

private extension DailyTipEngine {

    static func shouldFocusOnSodium(_ context: DailyTipContext) -> Bool {
        if context.hasAbnormalMetric(matching: ["blood pressure", "systolic", "diastolic", "bp"]) { return true }
        if context.goals.contains(.lowerBloodPressure) { return true }
        if let systolic = context.profile?.systolicBP, systolic >= 130 { return true }
        if let diastolic = context.profile?.diastolicBP, diastolic >= 85 { return true }
        return false
    }

    static func shouldFocusOnCholesterol(_ context: DailyTipContext) -> Bool {
        if context.hasAbnormalMetric(matching: ["cholesterol", "triglyceride", "lipid"]) { return true }
        if context.goals.contains(.lowerCholesterol) { return true }
        if let total = context.profile?.totalCholesterol, total > 5.2 { return true }
        return false
    }

    static func shouldFocusOnBloodSugar(_ context: DailyTipContext) -> Bool {
        if context.hasAbnormalMetric(matching: ["blood sugar", "fasting sugar", "glucose"]) { return true }
        if context.goals.contains(.controlBloodSugar) { return true }
        if let sugar = context.profile?.fastingBloodSugar, sugar > 5.5 { return true }
        return false
    }

    static func shouldFocusOnWeight(_ context: DailyTipContext) -> Bool {
        if context.hasAbnormalMetric(matching: ["bmi", "weight"]) { return true }
        if context.goals.contains(.loseWeight) { return true }
        if let profile = context.profile, profile.bmi >= 25 { return true }
        return false
    }
}

// MARK: - Tip Builders

private extension DailyTipEngine {

    static func makeSodiumTip(slot: TimeSlot, dateKey: String, context: DailyTipContext) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Keep sodium under 2,000 mg today — start with a low-salt breakfast."
            detailText = "Choose oatmeal, fresh fruit, or eggs without added salt. Avoid bacon, sausages, and most pre-packaged cereals which can be surprisingly high in sodium."
        case .afternoon:
            shortText = "Lunch tip: lean protein plus vegetables, easy on the sauce."
            detailText = "Soy sauce, salad dressings, and processed deli meats are common sodium sources. A grilled chicken bowl with steamed vegetables and a squeeze of lemon is a safe option."
        case .evening:
            shortText = "Lighter dinner tonight — aim to keep sodium below 700 mg."
            detailText = "Try home-cooked protein with two vegetables. If eating out, ask for sauces on the side and skip the salty sides like fries or kimchi."
        }
        let why = whyForBloodPressure(profile: context.profile, metric: context.firstAbnormalMetric(matching: ["blood pressure", "systolic", "diastolic", "bp"]))
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .sodium),
            category: .sodium,
            categoryLabel: "Low Sodium",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: why,
            suggestedAction: "Track sodium on your next meal log.",
            iconSystemName: "heart.fill",
            comprehensive: .empty
        )
    }

    static func makeCholesterolTip(slot: TimeSlot, dateKey: String, context: DailyTipContext) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Try oats this morning — soluble fiber supports healthy cholesterol."
            detailText = "Oatmeal, beans, and barley contain beta-glucan, a soluble fiber that has been shown to help lower LDL cholesterol when eaten regularly. Pair with berries for extra antioxidants."
        case .afternoon:
            shortText = "Add beans, lentils, or nuts to lunch for cholesterol support."
            detailText = "Replacing red or processed meat with plant proteins a few times a week is one of the most consistent dietary changes linked to better cholesterol numbers."
        case .evening:
            shortText = "Dinner idea: fish or tofu with a fiber-rich side."
            detailText = "Fatty fish (salmon, sardines) provides omega-3s, while a side of beans, lentils, or whole grains adds soluble fiber. Both are linked to improved lipid profiles."
        }
        let why = whyForCholesterol(profile: context.profile, metric: context.firstAbnormalMetric(matching: ["cholesterol", "triglyceride", "lipid"]))
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .cholesterol),
            category: .cholesterol,
            categoryLabel: "Cholesterol",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: why,
            suggestedAction: "Plan one fiber-rich meal today.",
            iconSystemName: "waveform.path.ecg",
            comprehensive: .empty
        )
    }

    static func makeBloodSugarTip(slot: TimeSlot, dateKey: String, context: DailyTipContext) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Breakfast tip: pair carbs with protein to steady your blood sugar."
            detailText = "Plain toast or sweet cereal alone can spike blood sugar quickly. Add eggs, Greek yogurt, or peanut butter so the meal releases energy more slowly."
        case .afternoon:
            shortText = "Lunch tip: half the plate vegetables, the rest split between protein and whole grains."
            detailText = "Eating vegetables and protein before starchy carbs (rice, noodles) can blunt the post-meal blood sugar rise. A short walk afterward helps too."
        case .evening:
            shortText = "Tonight: lighter portions of carbs, more vegetables and protein."
            detailText = "Late, carb-heavy dinners are often linked to higher fasting glucose the next morning. A salad with grilled protein is a safer pattern."
        }
        let why = whyForBloodSugar(profile: context.profile, metric: context.firstAbnormalMetric(matching: ["blood sugar", "fasting sugar", "glucose"]))
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .bloodSugar),
            category: .bloodSugar,
            categoryLabel: "Blood Sugar",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: why,
            suggestedAction: "Log your next carb-heavy meal for review.",
            iconSystemName: "drop.fill",
            comprehensive: .empty
        )
    }

    static func makeWeightTip(slot: TimeSlot, dateKey: String, context: DailyTipContext) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Protein-led breakfast keeps you full longer."
            detailText = "Eggs, Greek yogurt, or a tofu scramble can reduce mid-morning snacking. Aim for around 20–30g of protein in the first meal of the day."
        case .afternoon:
            shortText = "Build lunch around lean protein and vegetables, keep starches moderate."
            detailText = "A bowl with chicken or tofu, two vegetables, and a small portion of rice or quinoa is a sustainable lunch pattern for weight goals."
        case .evening:
            shortText = "Keep dinner light: vegetables, protein, easy on the carbs."
            detailText = "Lighter evening meals are generally easier to digest and tend to support more consistent weight progress, especially combined with a short post-dinner walk."
        }
        let why = whyForWeight(profile: context.profile, metric: context.firstAbnormalMetric(matching: ["bmi", "weight"]))
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .weight),
            category: .weight,
            categoryLabel: "Weight Goal",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: why,
            suggestedAction: "Log today’s main meals for a quick review.",
            iconSystemName: "scalemass.fill",
            comprehensive: .empty
        )
    }

    static func makeFiberTip(slot: TimeSlot, dateKey: String) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Add one extra vegetable or fruit to breakfast today."
            detailText = "Most adults eat less than the recommended 25g of fiber per day. Adding berries to oatmeal or tomato/spinach to eggs is an easy way to start."
        case .afternoon:
            shortText = "Lunch: aim for at least one fiber-rich side."
            detailText = "Beans, lentils, whole grains, and leafy greens all count. A simple side salad is a low-effort way to boost daily fiber."
        case .evening:
            shortText = "Dinner: include a vegetable that makes up at least a quarter of the plate."
            detailText = "Steamed broccoli, roasted carrots, or a quick stir-fried green vegetable adds fiber without adding much prep time."
        }
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .fiber),
            category: .fiber,
            categoryLabel: "Daily Fiber",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: "Adequate fiber supports digestion, gut health, and steadier energy levels throughout the day.",
            suggestedAction: "Add one fiber-rich item to your next meal log.",
            iconSystemName: "leaf.fill",
            comprehensive: .empty
        )
    }

    static func makeHydrationTip(slot: TimeSlot, dateKey: String) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Start the day with a full glass of water before coffee."
            detailText = "Most people wake up mildly dehydrated. Drinking water before caffeine can reduce the mid-morning energy dip and headache risk."
        case .afternoon:
            shortText = "Refill your water bottle before lunch."
            detailText = "Thirst is often misread as fatigue or hunger. A consistent water intake during the day can support attention and reduce unnecessary snacking."
        case .evening:
            shortText = "Aim for one more glass of water with dinner — but avoid heavy drinks late."
            detailText = "Adequate hydration during dinner supports digestion. Try to stop large amounts of fluid 1–2 hours before bed for better sleep quality."
        }
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .hydration),
            category: .hydration,
            categoryLabel: "Hydration",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: "Even mild dehydration can affect energy, focus, and how hungry you feel during the day.",
            suggestedAction: "Log your next water intake to track your trend.",
            iconSystemName: "drop.halffull",
            comprehensive: .empty
        )
    }

    static func makeGeneralTip(slot: TimeSlot, dateKey: String) -> DailyTip {
        let shortText: String
        let detailText: String
        switch slot {
        case .morning:
            shortText = "Good morning! Try a balanced breakfast with protein and fiber."
            detailText = "Eggs with whole-grain toast, or Greek yogurt with fruit and nuts are simple options. Balanced breakfasts tend to support steadier energy through the morning."
        case .afternoon:
            shortText = "Afternoon check-in: keep lunch simple — lean protein plus vegetables."
            detailText = "Pre-built meals or skipped lunches often lead to bigger, less healthy dinners. Even a quick bowl with protein and vegetables helps."
        case .evening:
            shortText = "Evening tip: lighter dinner and a short walk after eating."
            detailText = "A 10–15 minute walk after dinner can support digestion and overnight metabolic recovery. Keep portions reasonable to sleep better."
        }
        return DailyTip(
            id: makeId(dateKey: dateKey, category: .general),
            category: .general,
            categoryLabel: "Daily Tip",
            shortText: shortText,
            detailText: detailText,
            whyThisMatters: "Small, consistent choices around \(slot.mealName) usually have a bigger impact than occasional perfect days.",
            suggestedAction: nil,
            iconSystemName: "sparkles",
            comprehensive: .empty
        )
    }
}

// MARK: - "Why this matters" Builders

private extension DailyTipEngine {

    static func whyForBloodPressure(profile: HealthProfile?, metric: AbnormalMetricContext?) -> String {
        if let metric {
            return abnormalMetricExplanation(metric)
        }
        if let systolic = profile?.systolicBP {
            let range = BloodRange.systolicBP
            return rangeExplanation(
                value: Double(systolic),
                unit: range.unit,
                metricName: "systolic blood pressure",
                normal: range.normal,
                warning: range.warning
            )
        }
        return "Lowering sodium is one of the most consistent ways to support healthy blood pressure long-term."
    }

    static func whyForCholesterol(profile: HealthProfile?, metric: AbnormalMetricContext?) -> String {
        if let metric {
            return abnormalMetricExplanation(metric)
        }
        if let total = profile?.totalCholesterol {
            let range = BloodRange.cholesterol
            return rangeExplanation(
                value: total,
                unit: range.unit,
                metricName: "total cholesterol",
                normal: range.normal,
                warning: range.warning
            )
        }
        return "A diet richer in soluble fiber and plant proteins is one of the most reliable dietary patterns for healthier cholesterol levels."
    }

    static func whyForBloodSugar(profile: HealthProfile?, metric: AbnormalMetricContext?) -> String {
        if let metric {
            return abnormalMetricExplanation(metric)
        }
        if let sugar = profile?.fastingBloodSugar {
            let range = BloodRange.bloodSugar
            return rangeExplanation(
                value: sugar,
                unit: range.unit,
                metricName: "fasting blood sugar",
                normal: range.normal,
                warning: range.warning
            )
        }
        return "Pairing carbohydrates with protein, fiber, or healthy fats helps slow how quickly blood sugar rises after meals."
    }

    static func whyForWeight(profile: HealthProfile?, metric: AbnormalMetricContext?) -> String {
        if let metric {
            return abnormalMetricExplanation(metric)
        }
        if let profile = profile {
            let bmiText = String(format: "%.1f", profile.bmi)
            return "Your current BMI is around \(bmiText) (\(profile.bmiCategory)). Small daily adjustments tend to be more sustainable than aggressive short-term restrictions."
        }
        return "Sustainable weight changes usually come from small daily adjustments to portion sizes and meal composition rather than short-term cuts."
    }

    static func abnormalMetricExplanation(_ metric: AbnormalMetricContext) -> String {
        let statusText = metric.status.replacingOccurrences(of: "_", with: " ")
        let base = "Your \(metric.metric) is marked as \(statusText) with a current value of \(metric.currentValue)."
        if let advice = metric.advice, !advice.isEmpty {
            return "\(base) \(advice)"
        }
        return "\(base) Today's tip focuses on a practical step related to this metric."
    }

    /// Formats a metric value against its normal/warning ranges into a friendly explanation.
    static func rangeExplanation(
        value: Double,
        unit: String,
        metricName: String,
        normal: ClosedRange<Double>,
        warning: ClosedRange<Double>
    ) -> String {
        let valueText = formatMetric(value)
        let normalText = "\(formatMetric(normal.lowerBound))–\(formatMetric(normal.upperBound)) \(unit)"
        if normal.contains(value) {
            return "Your \(metricName) of \(valueText) \(unit) is within the typical range (\(normalText)). Today's tip helps you stay there."
        }
        if warning.contains(value) {
            return "Your \(metricName) of \(valueText) \(unit) is slightly above the typical range (\(normalText)). Small daily changes can help bring it back."
        }
        if value < normal.lowerBound {
            return "Your \(metricName) of \(valueText) \(unit) is below the typical range (\(normalText)). Today's tip favors balanced, nutrient-dense choices."
        }
        return "Your \(metricName) of \(valueText) \(unit) is above the typical range (\(normalText)). Consistent small choices today can help."
    }

    /// Drops trailing zeros so values like 5.0 render as "5".
    static func formatMetric(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
