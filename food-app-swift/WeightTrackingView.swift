//
//  WeightTrackingView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/16/25.
//

import SwiftUI
import Charts

struct WeightEntry: Identifiable, Codable {
    let _id: String; let user_id: String; let weight: Double; let recorded_at: String
    var id: String { _id }
}

struct WeightChartData: Identifiable {
    let id = UUID(); let date: Date; let weight: Double; let index: Int
}

struct WeightTrackingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var weightEntries: [WeightEntry] = []
    @State private var currentWeight: String = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var selectedUnit = "kg"
    
    let weightUnits = ["kg", "lbs"]
    
    var latestWeight: Double { weightEntries.first?.weight ?? 0 }
    
    var weightTrend: String {
        guard weightEntries.count >= 2 else { return "No trend data" }
        let diff = weightEntries[0].weight - weightEntries[1].weight
        if abs(diff) < 0.1 { return "Stable" }
        return diff > 0 ? "↗️ +\(String(format: "%.1f", diff)) \(selectedUnit)" : "↘️ \(String(format: "%.1f", diff)) \(selectedUnit)"
    }
    
    var chartData: [WeightChartData] {
        weightEntries.prefix(30).reversed().enumerated().map { index, entry in
            WeightChartData(date: ISO8601DateFormatter().date(from: entry.recorded_at) ?? Date(), weight: entry.weight, index: index)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.current.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            Image(systemName: "scalemass.fill").font(.system(size: 60)).foregroundColor(.purple)
                            Text("Weight Tracker").font(.title.bold()).foregroundColor(themeManager.current.primaryText)
                            Text("Track your weight progress over time").font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.top, 20)
                        
                        VStack(spacing: 20) {
                            if latestWeight > 0 {
                                VStack(spacing: 12) {
                                    Text("Current Weight").font(.headline).foregroundColor(themeManager.current.primaryText)
                                    HStack(alignment: .bottom, spacing: 4) {
                                        Text(String(format: "%.1f", latestWeight))
                                            .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(.purple)
                                        Text(selectedUnit).font(.title2).foregroundColor(themeManager.current.secondaryText).padding(.bottom, 8)
                                    }
                                    VStack(spacing: 4) {
                                        Text(weightTrend).font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                                        if let lastEntry = weightEntries.first,
                                           let lastDate = ISO8601DateFormatter().date(from: lastEntry.recorded_at) {
                                            Text("Last updated: \(formatDate(lastDate))").font(.caption).foregroundColor(themeManager.current.secondaryText.opacity(0.7))
                                        }
                                    }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.3), lineWidth: 1)))
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "scalemass").font(.system(size: 40)).foregroundColor(.purple.opacity(0.6))
                                    Text("No weight data yet").font(.headline).foregroundColor(themeManager.current.primaryText)
                                    Text("Add your first weight entry to start tracking").font(.subheadline).foregroundColor(themeManager.current.secondaryText).multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 2, dash: [5])).foregroundColor(.purple.opacity(0.3))))
                            }
                        }
                        .padding(.horizontal)
                        
                        if chartData.count > 1 {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Weight Trend").font(.headline).foregroundColor(themeManager.current.primaryText).padding(.horizontal)
                                Chart(chartData) { data in
                                    LineMark(x: .value("Date", data.date), y: .value("Weight", data.weight))
                                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.purple, .pink]), startPoint: .leading, endPoint: .trailing))
                                        .lineStyle(StrokeStyle(lineWidth: 3))
                                    PointMark(x: .value("Date", data.date), y: .value("Weight", data.weight))
                                        .foregroundStyle(Color.purple).symbolSize(50)
                                }
                                .frame(height: 200)
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                                        AxisTick().foregroundStyle(Color.white.opacity(0.3))
                                        AxisValueLabel().foregroundStyle(Color.gray)
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { _ in
                                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                                        AxisTick().foregroundStyle(Color.white.opacity(0.3))
                                        AxisValueLabel().foregroundStyle(Color.gray)
                                    }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1)))
                            }
                            .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Add Weight Entry").font(.headline).foregroundColor(themeManager.current.primaryText).padding(.horizontal)
                            VStack(spacing: 16) {
                                Picker("Unit", selection: $selectedUnit) {
                                    ForEach(weightUnits, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(SegmentedPickerStyle()).padding(.horizontal)
                                
                                HStack {
                                    TextField("Enter weight", text: $currentWeight).keyboardType(.decimalPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle()).frame(maxWidth: 120)
                                    Text(selectedUnit).foregroundColor(themeManager.current.secondaryText).font(.subheadline)
                                    Spacer()
                                    if let weight = Double(currentWeight) {
                                        let converted = selectedUnit == "kg" ? weight * 2.20462 : weight / 2.20462
                                        let otherUnit = selectedUnit == "kg" ? "lbs" : "kg"
                                        Text("≈ \(String(format: "%.1f", converted)) \(otherUnit)").font(.caption).foregroundColor(.purple)
                                    }
                                }
                                .padding(.horizontal)
                                
                                if !weightEntries.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("Quick adjustments").font(.caption).foregroundColor(themeManager.current.secondaryText)
                                        HStack {
                                            ForEach([-2, -1, -0.5, 0.5, 1, 2], id: \.self) { adj in
                                                Button("\(adj > 0 ? "+" : "")\(String(format: "%.1f", adj))") {
                                                    currentWeight = String(format: "%.1f", latestWeight + adj)
                                                }
                                                .font(.caption).foregroundColor(.purple)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Capsule().fill(Color.purple.opacity(0.1)))
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        Button(action: addWeight) {
                            HStack {
                                if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.8) }
                                else { Image(systemName: "plus.circle.fill"); Text("Add Weight Entry") }
                            }
                            .fontWeight(.semibold).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(LinearGradient(gradient: Gradient(colors: [.purple, .purple.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(12).shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isLoading || currentWeight.isEmpty).padding(.horizontal)
                        
                        if !weightEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Recent History").font(.headline).foregroundColor(themeManager.current.primaryText).padding(.horizontal)
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(weightEntries.prefix(10))) { entry in
                                        WeightHistoryRowView(entry: entry, unit: selectedUnit)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        Spacer(minLength: 40)
                    }
                }
                
                if showSuccess {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Weight logged!").fontWeight(.semibold)
                        }
                        .foregroundColor(.white).padding()
                        .background(Capsule().fill(Color.green).shadow(color: .green.opacity(0.3), radius: 10))
                        .transition(.move(edge: .bottom).combined(with: .opacity)).padding(.bottom, 50)
                    }
                    .animation(.spring(), value: showSuccess)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.purple)
                }
            }
            .onAppear { fetchWeightData() }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
    }
    
    func fetchWeightData() {
        guard let userId = getCurrentUserId(), let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-weight?user_id=\(userId)") else { return }
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else { return }
            if let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
                DispatchQueue.main.async {
                    self.weightEntries = decoded.sorted {
                        (ISO8601DateFormatter().date(from: $0.recorded_at) ?? Date()) > (ISO8601DateFormatter().date(from: $1.recorded_at) ?? Date())
                    }
                }
            }
        }.resume()
    }
    
    func addWeight() {
        guard let weight = Double(currentWeight), weight > 0,
              let userId = getCurrentUserId(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/add-weight") else { return }
        isLoading = true
        let weightInKg = selectedUnit == "lbs" ? weight / 2.20462 : weight
        let payload: [String: Any] = ["user_id": userId, "weight": weightInKg, "recorded_at": ISO8601DateFormatter().string(from: Date())]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { isLoading = false; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let newEntry = WeightEntry(_id: UUID().uuidString, user_id: userId, weight: weightInKg, recorded_at: ISO8601DateFormatter().string(from: Date()))
                    self.weightEntries.insert(newEntry, at: 0)
                    withAnimation(.spring()) { self.showSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.spring()) { self.showSuccess = false } }
                    NotificationCenter.default.post(name: Notification.Name("WeightAdded"), object: nil)
                    self.currentWeight = ""
                }
            }
        }.resume()
    }
    
    func getCurrentUserId() -> String? {
        let id = SessionManager.shared.userID; return id.isEmpty ? UserDefaults.standard.string(forKey: "user_id") : id
    }
}

struct WeightHistoryRowView: View {
    let entry: WeightEntry; let unit: String
    var displayWeight: Double { unit == "lbs" ? entry.weight * 2.20462 : entry.weight }
    var dateString: String {
        guard let date = ISO8601DateFormatter().date(from: entry.recorded_at) else { return "Unknown date" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
    }
    var body: some View {
        HStack {
            Image(systemName: "scalemass.fill").foregroundColor(.purple).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f %@", displayWeight, unit)).font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                Text(dateString).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Circle().fill(Color.purple.opacity(0.3)).frame(width: 8, height: 8).scaleEffect(1.5)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2), lineWidth: 1)))
    }
}
