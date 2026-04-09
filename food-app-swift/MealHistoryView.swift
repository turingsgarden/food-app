import SwiftUI

struct MealHistoryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var meals: [Meal] = []
    @State private var totalCalories: Int = 0
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedMeal: Meal? = nil
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    @State private var lastRefreshTime = Date()

    let filters = ["All", "Breakfast", "Lunch", "Dinner", "Snacks"]

    var filteredMeals: [Meal] {
        meals.filter { meal in
            let matchesFilter = selectedFilter == "All" || meal.meal_type?.capitalized == selectedFilter
            let matchesSearch = searchText.isEmpty || meal.dish_prediction.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var groupedMeals: [(String, [Meal])] {
        let grouped = Dictionary(grouping: filteredMeals) { meal -> String in
            if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                return formatDateHeader(date)
            }
            return "Unknown Date"
        }
        return grouped.sorted { a, b in
            let dateA = a.value.compactMap { ISO8601DateFormatter().date(from: $0.saved_at ?? "") }.max() ?? .distantPast
            let dateB = b.value.compactMap { ISO8601DateFormatter().date(from: $0.saved_at ?? "") }.max() ?? .distantPast
            return dateA > dateB
        }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ──
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Meal History")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(themeManager.current.primaryText)
                            Text("\(meals.count) meals tracked")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("\(totalCalories)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(themeManager.current.primaryText)
                            Text("kcal")
                                .font(.system(size: 11))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(themeManager.current.cardBackground)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(themeManager.current.cardBorder, lineWidth: 1))
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)

                
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                        TextField("Search meals...", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(themeManager.current.primaryText)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(themeManager.current.inputBackground)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(themeManager.current.cardBorder, lineWidth: 1))
                    .padding(.horizontal, 20).padding(.bottom, 14)


                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                Button(action: { selectedFilter = filter }) {
                                    Text(filter)
                                        .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .regular))
                                        .foregroundColor(selectedFilter == filter
                                            ? (themeManager.current == .dark ? .black : .white)
                                            : themeManager.current.primaryText)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 20)
                                            .fill(selectedFilter == filter
                                                  ? (themeManager.current == .dark ? Color.white : Color.black)
                                                  : themeManager.current.inputBackground))
                                        .overlay(RoundedRectangle(cornerRadius: 20)
                                            .stroke(selectedFilter == filter
                                                    ? Color.clear
                                                    : themeManager.current.cardBorder, lineWidth: 1))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 16)

              
                    if isLoading {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                            Text("Loading meals...")
                                .font(.subheadline)
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        Spacer()
                    } else if !errorMessage.isEmpty {
                        Spacer()
                        ErrorStateView(message: errorMessage, retry: fetchMeals)
                        Spacer()
                    } else if meals.isEmpty {
                        Spacer()
                        EmptyHistoryState()
                        Spacer()
                    } else if filteredMeals.isEmpty {
                        Spacer()
                        NoResultsView()
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                                ForEach(Array(groupedMeals.enumerated()), id: \.offset) { _, group in
                                    let (date, groupMeals) = group
                                    Section {
                                        VStack(spacing: 10) {
                                            ForEach(groupMeals) { meal in
                                                Button(action: { selectedMeal = meal }) {
                                                    HistoryMealRow(meal: meal)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.bottom, 16)
                                    } header: {
                                        HStack {
                                            Text(date)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(themeManager.current.primaryText)
                                            Spacer()
                                            Text("\(groupMeals.count) meals")
                                                .font(.system(size: 12))
                                                .foregroundColor(themeManager.current.secondaryText)
                                        }
                                        .padding(.horizontal, 20).padding(.vertical, 10)
                                        .background(themeManager.current.background)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .onAppear { fetchMeals() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealSaved"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fetchMeals() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealUpdated"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fetchMeals() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealDeleted"))) { _ in fetchMeals() }
            .refreshable { await fetchMealsAsync() }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal).environmentObject(themeManager).onDisappear { fetchMeals() }
            }
        }
    }

    func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }


    func fetchMeals() {
        isLoading = true; errorMessage = ""; lastRefreshTime = Date()
        guard SessionManager.shared.isLoggedIn else {
            errorMessage = "Please log in to view meal history"; isLoading = false; return
        }
        NetworkManager.shared.getUserMeals { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let fetchedMeals):
                    var uniqueMeals: [Meal] = []; var seenIds: Set<String> = []
                    for meal in fetchedMeals {
                        if !seenIds.contains(meal._id) { seenIds.insert(meal._id); uniqueMeals.append(meal) }
                    }
                    self.meals = uniqueMeals.sorted {
                        guard let d1 = ISO8601DateFormatter().date(from: $0.saved_at ?? ""),
                              let d2 = ISO8601DateFormatter().date(from: $1.saved_at ?? "") else { return false }
                        return d1 > d2
                    }
                    self.totalCalories = self.meals.compactMap { extractCalories(from: $0.nutrition_info) }.reduce(0, +)
                case .failure(let error):
                    let code = (error as NSError).code
                    switch code {
                    case 401:
                        self.errorMessage = "Session expired. Please log in again."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SessionManager.shared.logout() }
                    case -1009: self.errorMessage = "No internet connection"
                    case -1001: self.errorMessage = "Request timed out"
                    case -1005: self.errorMessage = "Network connection lost"
                    default: self.errorMessage = "Failed to load meal history"
                    }
                }
            }
        }
    }

    func fetchMealsAsync() async {
        await withCheckedContinuation { continuation in
            fetchMeals()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { continuation.resume() }
        }
    }

    private func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie") { return Int(parts[1]) }
        }
        return nil
    }
}



struct HistoryMealRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: Meal

    var calories: Int? {
        for line in meal.nutrition_info.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie") { return Int(parts[1]) }
        }
        return nil
    }

    var mealTime: String {
        guard let s = meal.saved_at, let d = ISO8601DateFormatter().date(from: s) else { return "" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 14) {

            Group {
                if let base64 = meal.image_thumb ?? meal.image_full, !base64.isEmpty,
                   let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    themeManager.current.inputBackground
                        .overlay(Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.4)))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14))


            VStack(alignment: .leading, spacing: 5) {
                Text(meal.dish_prediction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let mealType = meal.meal_type {
                        Text(mealType.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                    }
                    Text(mealTime)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            Spacer()


            HStack(spacing: 6) {
                if let cal = calories {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(cal)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                        Text("kcal")
                            .font(.system(size: 10))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            }
        }
        .padding(14)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}



struct FilterPill: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected
                    ? (themeManager.current == .dark ? .black : .white)
                    : themeManager.current.primaryText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected
                          ? (themeManager.current == .dark ? Color.white : Color.black)
                          : themeManager.current.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.clear : themeManager.current.cardBorder, lineWidth: 1))
        }
    }
}

struct DateHeader: View {
    @EnvironmentObject var themeManager: ThemeManager
    let date: String; let count: Int
    var body: some View {
        HStack {
            Text(date).font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
            Spacer()
            Text("\(count) meals").font(.caption)
                .foregroundColor(themeManager.current.secondaryText)
        }
        .padding(.vertical, 8)
        .background(themeManager.current.background)
    }
}

struct EmptyHistoryState: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray").font(.system(size: 48))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.3))
            VStack(spacing: 6) {
                Text("No meals yet").font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Text("Start tracking your nutrition journey")
                    .font(.subheadline).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }
}

struct NoResultsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 40))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.3))
            Text("No meals found").font(.system(size: 17, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
            Text("Try adjusting your search or filters").font(.subheadline)
                .foregroundColor(themeManager.current.secondaryText)
        }
    }
}

struct ErrorStateView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let message: String; let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44)).foregroundColor(.orange)
            Text(message).font(.subheadline)
                .foregroundColor(themeManager.current.primaryText)
                .multilineTextAlignment(.center).padding(.horizontal)
            if !message.contains("Session expired") {
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.orange).cornerRadius(12)
                }
            }
        }
    }
}
