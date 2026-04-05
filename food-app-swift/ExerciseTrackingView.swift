//
//  ExerciseTrackingView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/16/25.
//

import SwiftUI
import Charts

// MARK: - Exercise Entry Model
struct ExerciseEntry: Identifiable, Codable {
    
    let _id: String
    let user_id: String
    let exercise_type: String
    let duration: Int
    let intensity: String?
    let calories_burned: Int?
    let notes: String?
    let recorded_at: String
    
    var id: String { _id }
}

// MARK: - Exercise Chart Data
struct ExerciseChartData: Identifiable {
    let id = UUID()
    let date: Date
    let duration: Int
    let dayName: String
}

struct ExerciseTrackingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var exerciseEntries: [ExerciseEntry] = []
    @State private var selectedExerciseType = "Walking"
    @State private var duration: String = ""
    @State private var caloriesBurned: String = ""
    @State private var selectedDate = Date()
    @State private var exerciseNotes: String = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showDatePicker = false
    @State private var selectedIntensity = "Moderate"
    
    let exerciseTypes = ["Walking", "Running", "Cycling", "Swimming", "Gym", "Yoga", "Dancing", "Sports", "Other"]
    let intensityLevels = ["Light", "Moderate", "Vigorous"]
    
    var totalExerciseThisWeek: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let weekEntries = exerciseEntries.filter { entry in
            if let entryDate = ISO8601DateFormatter().date(from: entry.recorded_at) {
                return entryDate >= weekAgo
            }
            return false
        }
        
        return weekEntries.reduce(0) { $0 + $1.duration }
    }
    
    var weeklyGoal: Int { 150 } // minutes per week (WHO recommendation)
    
    var exerciseProgress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(Double(totalExerciseThisWeek) / Double(weeklyGoal), 1.0)
    }
    
    var chartData: [ExerciseChartData] {
        let calendar = Calendar.current
        let last7Days = (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: -dayOffset, to: Date())
        }.reversed()
        
        return last7Days.map { date in
            let dayEntry = exerciseEntries.filter { entry in
                if let entryDate = ISO8601DateFormatter().date(from: entry.recorded_at) {
                    return calendar.isDate(entryDate, inSameDayAs: date)
                }
                return false
            }.reduce(0) { $0 + $1.duration }
            
            return ExerciseChartData(
                date: date,
                duration: dayEntry,
                dayName: DateFormatter().shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            )
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                // ✅ 改成
                themeManager.current.background
                    .ignoresSafeArea()
                
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Exercise Tracker")
                                .font(.title.bold())
                                .foregroundColor(.white)
                            
                            Text("Track your workouts and stay active")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 20)
                        
                        // Weekly Progress Section
                        VStack(spacing: 20) {
                            // Circular Progress
                            ZStack {
                                Circle()
                                    .stroke(Color.green.opacity(0.2), lineWidth: 12)
                                    .frame(width: 200, height: 200)
                                
                                Circle()
                                    .trim(from: 0, to: exerciseProgress)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.green, .mint]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                    )
                                    .frame(width: 200, height: 200)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: exerciseProgress)
                                
                                VStack(spacing: 8) {
                                    Text("\(totalExerciseThisWeek)")
                                        .font(.system(size: 42, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("/ \(weeklyGoal) min")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                    
                                    Text("This Week")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                }
                            }
                            
                            // Progress Bar
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Weekly Goal")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text("\(totalExerciseThisWeek) / \(weeklyGoal) min")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                                
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 12)
                                        
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.green, .mint]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geometry.size.width * exerciseProgress, height: 12)
                                            .animation(.spring(), value: exerciseProgress)
                                    }
                                }
                                .frame(height: 12)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Weekly Chart
                        if chartData.count > 1 {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("This Week")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                Chart(chartData) { data in
                                    BarMark(
                                        x: .value("Day", data.dayName),
                                        y: .value("Duration", data.duration)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.green, .mint]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .cornerRadius(4)
                                }
                                .frame(height: 200)
                                .chartYAxis {
                                    AxisMarks { _ in
                                        AxisGridLine()
                                            .foregroundStyle(Color.white.opacity(0.1))
                                        AxisTick()
                                            .foregroundStyle(Color.white.opacity(0.3))
                                        AxisValueLabel()
                                            .foregroundStyle(Color.gray)
                                    }
                                }
                                .chartXAxis {
                                    AxisMarks { _ in
                                        AxisTick()
                                            .foregroundStyle(Color.white.opacity(0.3))
                                        AxisValueLabel()
                                            .foregroundStyle(Color.gray)
                                    }
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
                            .padding(.horizontal)
                        }
                        
                        // Add Exercise Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Add Exercise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                // Date Selector
                                Button(action: { showDatePicker = true }) {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.green)
                                        Text("Date: \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
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
                                }
                                .padding(.horizontal)
                                
                                // Exercise Type Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Exercise Type")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Menu {
                                        ForEach(exerciseTypes, id: \.self) { type in
                                            Button(action: { selectedExerciseType = type }) {
                                                HStack {
                                                    Text(type)
                                                    if selectedExerciseType == type {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedExerciseType)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .foregroundColor(.gray)
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
                                    }
                                }
                                .padding(.horizontal)
                                
                                // Duration Input
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Duration (minutes)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    HStack {
                                        TextField("e.g., 30", text: $duration)
                                            .keyboardType(.numberPad)
                                            .foregroundColor(.white)
                                        
                                        Text("minutes")
                                            .foregroundColor(.gray)
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
                                }
                                .padding(.horizontal)
                                
                                // Intensity Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Intensity")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    HStack(spacing: 12) {
                                        ForEach(intensityLevels, id: \.self) { intensity in
                                            Button(action: { selectedIntensity = intensity }) {
                                                Text(intensity)
                                                    .font(.subheadline)
                                                    .fontWeight(selectedIntensity == intensity ? .semibold : .regular)
                                                    .foregroundColor(selectedIntensity == intensity ? .black : .white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill(selectedIntensity == intensity ? Color.green : Color.white.opacity(0.1))
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 12)
                                                                    .stroke(selectedIntensity == intensity ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                                            )
                                                    )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                
                                // Calories Burned (Optional)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Calories Burned (Optional)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    HStack {
                                        TextField("Auto-calculated", text: $caloriesBurned)
                                            .keyboardType(.numberPad)
                                            .foregroundColor(.white)
                                        
                                        Text("kcal")
                                            .foregroundColor(.gray)
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
                                }
                                .padding(.horizontal)
                                
                                // Notes (Optional)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes (Optional)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    TextField("How did you feel?", text: $exerciseNotes, axis: .vertical)
                                        .lineLimit(3)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                                )
                                        )
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Add Button
                        Button(action: addExercise) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Exercise")
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.green, .green.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isLoading || duration.isEmpty)
                        .padding(.horizontal)
                        
                        // Recent Exercise History
                        if !exerciseEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Recent Activities")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(exerciseEntries.prefix(10))) { entry in
                                        ExerciseHistoryRowView(entry: entry)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
                
                // Success Animation
                if showSuccess {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Exercise logged!")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            Capsule()
                                .fill(Color.green)
                                .shadow(color: .green.opacity(0.3), radius: 10)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 50)
                    }
                    .animation(.spring(), value: showSuccess)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
            .onAppear {
                fetchExerciseData()
            }
            .sheet(isPresented: $showDatePicker) {
                ExerciseDatePickerSheet(selectedDate: $selectedDate)
            }
        }
    }
    
    func fetchExerciseData() {
        guard let userId = getCurrentUserId() else { return }
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-exercise?user_id=\(userId)") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ Exercise fetch error: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([ExerciseEntry].self, from: data)
                DispatchQueue.main.async {
                    self.exerciseEntries = decoded.sorted { entry1, entry2 in
                        let date1 = ISO8601DateFormatter().date(from: entry1.recorded_at) ?? Date()
                        let date2 = ISO8601DateFormatter().date(from: entry2.recorded_at) ?? Date()
                        return date1 > date2
                    }
                }
            } catch {
                print("❌ Exercise decode error: \(error)")
            }
        }.resume()
    }
    
    func addExercise() {
        guard let durationInt = Int(duration),
              durationInt > 0 else { return }
        
        guard let userId = getCurrentUserId() else { return }
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/add-exercise") else { return }
        
        isLoading = true
        
        // Calculate calories if not provided
        let calculatedCalories = caloriesBurned.isEmpty ?
            estimateCalories(exercise: selectedExerciseType, duration: durationInt, intensity: selectedIntensity) :
            Int(caloriesBurned) ?? 0
        
        let payload: [String: Any] = [
            "user_id": userId,
            "exercise_type": selectedExerciseType,
            "duration": durationInt,
            "intensity": selectedIntensity,
            "calories_burned": calculatedCalories,
            "notes": exerciseNotes,
            "recorded_at": ISO8601DateFormatter().string(from: selectedDate)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Add to local array for immediate UI update
                    let newEntry = ExerciseEntry(
                        _id: UUID().uuidString,
                        user_id: userId,
                        exercise_type: self.selectedExerciseType,
                        duration: durationInt,
                        intensity: self.selectedIntensity,
                        calories_burned: calculatedCalories,
                        notes: self.exerciseNotes,
                        recorded_at: ISO8601DateFormatter().string(from: self.selectedDate)
                    )
                    
                    self.exerciseEntries.insert(newEntry, at: 0)
                    
                    // Show success animation
                    withAnimation(.spring()) {
                        self.showSuccess = true
                    }
                    
                    // Hide success animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.spring()) {
                            self.showSuccess = false
                        }
                    }
                    
                    // Post notification
                    NotificationCenter.default.post(name: Notification.Name("ExerciseAdded"), object: nil)
                    
                    // Reset form
                    self.duration = ""
                    self.caloriesBurned = ""
                    self.exerciseNotes = ""
                    self.selectedDate = Date()
                }
            }
        }.resume()
    }
    
    func estimateCalories(exercise: String, duration: Int, intensity: String) -> Int {
        // Basic calorie estimation (simplified)
        let baseCaloriesPerMinute: Double
        
        switch exercise.lowercased() {
        case "running":
            baseCaloriesPerMinute = 10.0
        case "cycling":
            baseCaloriesPerMinute = 8.0
        case "swimming":
            baseCaloriesPerMinute = 11.0
        case "walking":
            baseCaloriesPerMinute = 4.0
        case "gym":
            baseCaloriesPerMinute = 6.0
        case "yoga":
            baseCaloriesPerMinute = 3.0
        default:
            baseCaloriesPerMinute = 5.0
        }
        
        let intensityMultiplier: Double
        switch intensity {
        case "Light":
            intensityMultiplier = 0.7
        case "Moderate":
            intensityMultiplier = 1.0
        case "Vigorous":
            intensityMultiplier = 1.5
        default:
            intensityMultiplier = 1.0
        }
        
        return Int(baseCaloriesPerMinute * Double(duration) * intensityMultiplier)
    }
    
    func getCurrentUserId() -> String? {
        // Check SessionManager first - userID is String, not String?
        let sessionId = SessionManager.shared.userID
        if !sessionId.isEmpty {
            return sessionId
        }
        
        // Check UserDefaults as fallback
        return UserDefaults.standard.string(forKey: "user_id")
    }
}

// MARK: - Supporting Views
struct ExerciseHistoryRowView: View {
    let entry: ExerciseEntry
    
    var timeString: String {
        guard let date = ISO8601DateFormatter().date(from: entry.recorded_at) else {
            return "Unknown time"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            Image(systemName: exerciseIcon(for: entry.exercise_type))
                .foregroundColor(.green)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise_type)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text("\(entry.duration) min")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if let calories = entry.calories_burned, calories > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(calories) kcal")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let intensity = entry.intensity {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(intensity)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Activity indicator
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    func exerciseIcon(for exercise: String) -> String {
        switch exercise.lowercased() {
        case "running":
            return "figure.run"
        case "walking":
            return "figure.walk"
        case "cycling":
            return "bicycle"
        case "swimming":
            return "figure.pool.swim"
        case "gym":
            return "dumbbell.fill"
        case "yoga":
            return "figure.yoga"
        case "dancing":
            return "figure.dance"
        case "sports":
            return "sportscourt.fill"
        default:
            return "figure.mixed.cardio"
        }
    }
}

struct ExerciseDatePickerSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedDate: Date
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(WheelDatePickerStyle())
                .padding()
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}
