import SwiftUI

struct MealHistoryView: View {
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
            let matchesFilter = selectedFilter == "All" || meal.meal_type == selectedFilter
            let matchesSearch = searchText.isEmpty || meal.dish_prediction.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }
    
    var groupedMeals: [(String, [Meal])] {
        Dictionary(grouping: filteredMeals) { meal in
            if let savedAt = meal.saved_at,
               let date = ISO8601DateFormatter().date(from: savedAt) {
                return formatDateHeader(date)
            }
            return "Unknown Date"
        }
        .sorted { $0.key > $1.key }
        .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.black.opacity(0.95),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom Navigation Bar HStack
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meal History")
                                .font(.largeTitle.bold())
                                .foregroundColor(.white)
                            
                            Text("\\(meals.count) meals tracked")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Stats Card
                        VStack(spacing: 4) {
                            Text("\\(totalCalories)")
                                .font(.title2.bold())
                                .foregroundColor(.orange)
                            Text("Total kcal")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search meals...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    
                    // Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filters, id: \\.self) { filter in
                                FilterPill(
                                    title: filter,
                                    isSelected: selectedFilter == filter,
                                    action: { selectedFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 20)

                    // Content
                    if isLoading {
                        Spacer()
                        ProgressView("Loading meals...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .foregroundColor(.white)
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
                                ForEach(groupedMeals, id: \\.0) { date, meals in
                                    Section {
                                        ForEach(meals) { meal in
                                            MealHistoryCard(meal: meal)
                                                .onTapGesture {
                                                    selectedMeal = meal
                                                }
                                        }
                                    } header: {
                                        DateHeader(date: date, count: meals.count)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                print("📱 MealHistoryView appeared")
                print("🔍 Is logged in: \\(SessionManager.shared.isLoggedIn)")
                print("🆔 User ID: \\(SessionManager.shared.userID)")
                print("🔑 Has token: \\(SessionManager.shared.getAuthToken() != nil)")
                
                fetchMeals()
            }
            // Listen for meal saved notifications
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealSaved"))) { _ in
                print("🔔 Meal saved notification received in MealHistoryView")
                // Add a small delay to ensure backend has processed the save
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fetchMeals()
                }
            }
            // Listen for meal updated notifications
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealUpdated"))) { _ in
                print("🔔 Meal updated notification received in MealHistoryView")
                // Add a small delay to ensure backend has processed the update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fetchMeals()
                }
            }
            // Listen for meal deleted notifications
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealDeleted"))) { _ in
                print("🔔 Meal deleted notification received in MealHistoryView")
                fetchMeals()
            }
            .refreshable {
                await fetchMealsAsync()
            }
            .sheet(item: $selectedMeal) { meal in
                NavigationView {
                    MealDetailView(meal: meal)
                        .onDisappear {
                            // Refresh when detail view closes in case meal was edited
                            fetchMeals()
                        }
                }
            }
        }
    }
    
    // Components
    
    func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    func fetchMeals() {
        isLoading = true
        errorMessage = ""
        lastRefreshTime = Date()
        
        // Check if user is logged in
        guard SessionManager.shared.isLoggedIn else {
            errorMessage = "Please log in to view meal history"
            isLoading = false
            return
        }
        
        print("🔄 Fetching meals at \\(Date())")
        
        // Use NetworkManager which handles JWT authentication
        NetworkManager.shared.getUserMeals { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let fetchedMeals):
                    print("✅ Successfully fetched \\(fetchedMeals.count) meals")
                    
                    // Remove duplicates based on meal ID
                    var uniqueMeals: [Meal] = []
                    var seenMealIds: Set<String> = []
                    
                    for meal in fetchedMeals {
                        if !seenMealIds.contains(meal._id) {
                            seenMealIds.insert(meal._id)
                            uniqueMeals.append(meal)
                            
                            // Debug log nutrition info
                            if !meal.nutrition_info.isEmpty {
                                print("📊 Meal '\\(meal.dish_prediction)' nutrition: \\(meal.nutrition_info.prefix(100))...")
                            }
                        }
                    }
                    
                    // Sort by date (newest first)
                    self.meals = uniqueMeals.sorted { meal1, meal2 in
                        guard let date1 = ISO8601DateFormatter().date(from: meal1.saved_at ?? ""),
                              let date2 = ISO8601DateFormatter().date(from: meal2.saved_at ?? "") else {
                            return false
                        }
                        return date1 > date2
                    }
                    
                    // Calculate total calories using the global function from Meal.swift
                    self.totalCalories = self.meals.compactMap { meal in
                        extractCalories(from: meal.nutrition_info)
                    }.reduce(0, +)
                    
                    print("📊 Total calories calculated: \\(self.totalCalories)")
                    print("📊 Unique meals loaded: \\(self.meals.count)")
                    
                case .failure(let error):
                    print("❌ Failed to load meals: \\(error)")
                    
                    // Better error handling
                    if let nsError = error as NSError? {
                        switch nsError.code {
                        case 401:
                            self.errorMessage = "Session expired. Please log in again."
                            // Optionally trigger logout
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                SessionManager.shared.logout()
                            }
                        case -1009:
                            self.errorMessage = "No internet connection"
                        case -1001:
                            self.errorMessage = "Request timed out"
                        case -1005:
                            self.errorMessage = "Network connection lost"
                        default:
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = "Failed to load meal history"
                    }
                }
            }
        }
    }
    
    func fetchMealsAsync() async {
        await withCheckedContinuation { continuation in
            fetchMeals()
            // Wait a bit longer for the async operation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                continuation.resume()
            }
        }
    }
}

// Supporting Views

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.orange : Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

struct DateHeader: View {
    let date: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(date)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\\(count) meals")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color.black.opacity(0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct MealHistoryCard: View {
    let meal: Meal
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            if let base64 = meal.image_thumb ?? meal.image_full,
               !base64.isEmpty,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(16)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange.opacity(0.3), .orange.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.title2)
                    )
            }
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                Text(meal.dish_prediction)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 16) {
                    // Calories - with better extraction
                    if let cal = extractCalories(from: meal.nutrition_info) {
                        Label("\\(cal) kcal", systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    
                    // Meal Type
                    if let mealType = meal.meal_type {
                        Text(mealType)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.2))
                            )
                            .foregroundColor(.blue)
                    }
                }
                
                // Time
                if let savedAt = meal.saved_at,
                   let date = ISO8601DateFormatter().date(from: savedAt) {
                    Text(formattedTime(date))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

struct EmptyHistoryState: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No meals yet")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                
                Text("Start tracking your nutrition journey")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct NoResultsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("No meals found")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if !message.contains("Session expired") {
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
        }
    }
}
