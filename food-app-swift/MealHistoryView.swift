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
        }
        .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meal History").font(.largeTitle.bold())
                                .foregroundColor(themeManager.current.primaryText)
                            Text("\(meals.count) meals tracked").font(.caption)
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(totalCalories)").font(.title2.bold()).foregroundColor(.orange)
                            Text("Total kcal").font(.caption2)
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)))
                    }
                    .padding(.horizontal).padding(.top, 10).padding(.bottom, 20)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(themeManager.current.secondaryText)
                        TextField("Search meals...", text: $searchText)
                            .foregroundColor(themeManager.current.primaryText)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.current.inputBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(themeManager.current.cardBorder, lineWidth: 1)))
                    .padding(.horizontal).padding(.bottom, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filters, id: \.self) { filter in
                                FilterPill(title: filter, isSelected: selectedFilter == filter, action: { selectedFilter = filter })
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 20)

                    if isLoading {
                        Spacer()
                        ProgressView("Loading meals...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .foregroundColor(themeManager.current.primaryText)
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
                            LazyVStack(spacing: 20, pinnedViews: .sectionHeaders) {
                                ForEach(Array(groupedMeals.enumerated()), id: \.offset) { index, group in
                                    let (date, groupMeals) = group
                                    Section {
                                        ForEach(groupMeals) { meal in
                                            Button(action: { selectedMeal = meal }) {
                                                MealHistoryCard(meal: meal)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } header: {
                                        DateHeader(date: date, count: groupMeals.count)
                                    }
                                }
                            }
                            .padding(.horizontal)
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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealDeleted"))) { _ in
                fetchMeals()
            }
            .refreshable { await fetchMealsAsync() }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal)
                    .environmentObject(themeManager)
                    .onDisappear { fetchMeals() }
            }
        }
    }
    
    func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
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
                    var uniqueMeals: [Meal] = []
                    var seenIds: Set<String> = []
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
                    case 401: self.errorMessage = "Session expired. Please log in again."
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
}

// MARK: - Supporting Views

struct FilterPill: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : themeManager.current.primaryText)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.orange : themeManager.current.inputBackground))
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
            Text(date).font(.headline).foregroundColor(themeManager.current.primaryText)
            Spacer()
            Text("\(count) meals").font(.caption).foregroundColor(themeManager.current.secondaryText)
        }
        .padding(.vertical, 8)
        .background(themeManager.current.background)
    }
}

struct MealHistoryCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: Meal
    var body: some View {
        HStack(spacing: 16) {
            if let base64 = meal.image_thumb ?? meal.image_full,
               !base64.isEmpty,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 100, height: 100).clipped().cornerRadius(16)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(gradient: Gradient(colors: [.orange.opacity(0.3), .orange.opacity(0.1)]),
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .overlay(Image(systemName: "photo").foregroundColor(.white.opacity(0.5)).font(.title2))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(meal.dish_prediction).font(.headline)
                    .foregroundColor(themeManager.current.primaryText).lineLimit(1)
                HStack(spacing: 16) {
                    if let cal = extractCalories(from: meal.nutrition_info) {
                        Label("\(cal) kcal", systemImage: "flame.fill")
                            .font(.subheadline).foregroundColor(.orange)
                    }
                    if let mealType = meal.meal_type {
                        Text(mealType.capitalized).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                }
                if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                    Text(formattedTime(date)).font(.caption)
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(themeManager.current.secondaryText).font(.caption)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.current.cardBorder, lineWidth: 1)))
    }
    func formattedTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }
}

struct EmptyHistoryState: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray").font(.system(size: 60))
                .foregroundColor(themeManager.current.secondaryText)
            VStack(spacing: 8) {
                Text("No meals yet").font(.title3.bold())
                    .foregroundColor(themeManager.current.primaryText)
                Text("Start tracking your nutrition journey").font(.subheadline)
                    .foregroundColor(themeManager.current.secondaryText)
            }
        }
    }
}

struct NoResultsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 40))
                .foregroundColor(themeManager.current.secondaryText)
            Text("No meals found").font(.headline)
                .foregroundColor(themeManager.current.primaryText)
            Text("Try adjusting your search or filters").font(.subheadline)
                .foregroundColor(themeManager.current.secondaryText)
        }
    }
}

struct ErrorStateView: View {
    let message: String; let retry: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50)).foregroundColor(.orange)
            Text(message).font(.subheadline).foregroundColor(.white)
                .multilineTextAlignment(.center).padding(.horizontal)
            if !message.contains("Session expired") {
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(12)
                }
            }
        }
    }
}
