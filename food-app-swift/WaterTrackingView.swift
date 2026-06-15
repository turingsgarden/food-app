//
//  WaterTrackingView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/16/25.
//
import SwiftUI

struct WaterEntry: Identifiable, Codable {
    let _id: String
    let user_id: String
    let amount: Double
    let recorded_at: String
    var id: String { _id }
}

struct WaterTrackingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var waterEntries: [WaterEntry] = []
    @State private var todayWater: Double = 0
    @State private var selectedAmount: Double = 250
    @State private var customAmount: String = ""
    @State private var showCustomAmount = false
    @State private var isLoading = false
    @State private var showSuccess = false
    
    let quickAmounts = [125, 250, 375, 500, 750, 1000]
    let waterGoal = 2000.0
    
    var waterProgress: Double { min(todayWater / waterGoal, 1.0) }
    
    var body: some View {
        NavigationView {
            ZStack {
                themeManager.current.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            Image(systemName: "drop.fill").font(.system(size: 60)).foregroundColor(.blue)
                            Text("Water Tracker").font(.title.bold()).foregroundColor(themeManager.current.primaryText)
                            Text("Stay hydrated throughout the day").font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.top, 20)
                        
                        VStack(spacing: 20) {
                            ZStack {
                                Circle().stroke(Color.blue.opacity(0.2), lineWidth: 12).frame(width: 200, height: 200)
                                Circle().trim(from: 0, to: waterProgress)
                                    .stroke(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .topLeading, endPoint: .bottomTrailing),
                                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 200, height: 200).rotationEffect(.degrees(-90))
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: waterProgress)
                                VStack(spacing: 8) {
                                    Text("\(Int(todayWater))").font(.system(size: 42, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                                    Text("/ \(Int(waterGoal)) ml").font(.title3).foregroundColor(themeManager.current.secondaryText)
                                    Text("\(Int(waterProgress * 100))%").font(.caption).foregroundColor(.blue).fontWeight(.semibold)
                                }
                            }
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Today's Goal").font(.subheadline).foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                    Text("\(Int(todayWater)) / \(Int(waterGoal)) ml").font(.subheadline).foregroundColor(.blue)
                                }
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6).fill(themeManager.current.inputBackground).frame(height: 12)
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .leading, endPoint: .trailing))
                                            .frame(width: geometry.size.width * waterProgress, height: 12)
                                            .animation(.spring(), value: waterProgress)
                                    }
                                }
                                .frame(height: 12)
                            }
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Quick Add").font(.headline).foregroundColor(themeManager.current.primaryText).padding(.horizontal)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                                ForEach(quickAmounts, id: \.self) { amount in
                                    WaterQuickAmountButton(amount: amount, isSelected: selectedAmount == Double(amount),
                                                           action: { selectedAmount = Double(amount); showCustomAmount = false })
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Button(action: { showCustomAmount.toggle(); if showCustomAmount { customAmount = "\(Int(selectedAmount))" } }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                                    Text("Custom Amount").font(.subheadline).foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                    Image(systemName: showCustomAmount ? "chevron.up" : "chevron.down").foregroundColor(themeManager.current.secondaryText).font(.caption)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeManager.current.cardBorder, lineWidth: 1)))
                            }
                            .padding(.horizontal)
                            
                            if showCustomAmount {
                                VStack(spacing: 12) {
                                    HStack {
                                        TextField("Enter amount", text: $customAmount).keyboardType(.numberPad)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .onChange(of: customAmount) { _, newValue in
                                                if let amount = Double(newValue) { selectedAmount = amount }
                                            }
                                        Text("ml").foregroundColor(themeManager.current.secondaryText).font(.subheadline)
                                    }
                                    HStack {
                                        ForEach([100, 200, 300, 400], id: \.self) { amount in
                                            Button("\(amount)ml") { customAmount = "\(amount)"; selectedAmount = Double(amount) }
                                                .font(.caption).foregroundColor(.blue)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Capsule().fill(Color.blue.opacity(0.1)))
                                        }
                                    }
                                }
                                .padding(.horizontal).transition(.opacity)
                            }
                        }
                        
                        Button(action: addWater) {
                            HStack {
                                if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.8) }
                                else { Image(systemName: "plus.circle.fill"); Text("Add \(Int(selectedAmount)) ml") }
                            }
                            .fontWeight(.semibold).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(LinearGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(12).shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isLoading || selectedAmount <= 0).padding(.horizontal)
                        
                        if !waterEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Today's History").font(.headline).foregroundColor(themeManager.current.primaryText).padding(.horizontal)
                                LazyVStack(spacing: 12) {
                                    ForEach(todayEntries) { entry in WaterHistoryRowView(entry: entry) }
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
                            Text("Water added!").fontWeight(.semibold)
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
                    Button("Done") { dismiss() }.foregroundColor(.blue)
                }
            }
            .onAppear { fetchWaterData() }
        }
    }
    
    var todayEntries: [WaterEntry] {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        return waterEntries.filter { entry in
            if let d = ISO8601DateFormatter().date(from: entry.recorded_at) { return calendar.isDate(d, inSameDayAs: today) }
            return false
        }.sorted {
            (ISO8601DateFormatter().date(from: $0.recorded_at) ?? Date()) > (ISO8601DateFormatter().date(from: $1.recorded_at) ?? Date())
        }
    }
    
    func fetchWaterData() {
        guard let userId = getCurrentUserId(), let url = AppConfig.url(path: "/user-water?user_id=\(userId)") else { return }
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else { return }
            if let decoded = try? JSONDecoder().decode([WaterEntry].self, from: data) {
                DispatchQueue.main.async { self.waterEntries = decoded; self.calculateTodayWater() }
            }
        }.resume()
    }
    
    func calculateTodayWater() {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        let total = waterEntries.filter { entry in
            if let d = ISO8601DateFormatter().date(from: entry.recorded_at) { return calendar.isDate(d, inSameDayAs: today) }
            return false
        }.reduce(0.0) { $0 + $1.amount }
        withAnimation(.spring()) { self.todayWater = total }
    }
    
    func addWater() {
        guard selectedAmount > 0, let userId = getCurrentUserId(),
              let url = AppConfig.url(path: "/add-water") else { return }
        isLoading = true
        let payload: [String: Any] = ["user_id": userId, "amount": selectedAmount, "recorded_at": ISO8601DateFormatter().string(from: Date())]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { isLoading = false; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let newEntry = WaterEntry(_id: UUID().uuidString, user_id: userId, amount: self.selectedAmount, recorded_at: ISO8601DateFormatter().string(from: Date()))
                    self.waterEntries.append(newEntry); self.calculateTodayWater()
                    withAnimation(.spring()) { self.showSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.spring()) { self.showSuccess = false } }
                    NotificationCenter.default.post(name: Notification.Name("WaterAdded"), object: nil)
                    self.selectedAmount = 250; self.showCustomAmount = false; self.customAmount = ""
                }
            }
        }.resume()
    }
    
    func getCurrentUserId() -> String? {
        let id = SessionManager.shared.userID; return id.isEmpty ? UserDefaults.standard.string(forKey: "user_id") : id
    }
}

struct WaterQuickAmountButton: View {
    let amount: Int; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "drop.fill").font(.title2).foregroundColor(isSelected ? .white : .blue)
                Text("\(amount)").font(.headline).foregroundColor(isSelected ? .white : .blue)
                Text("ml").font(.caption).foregroundColor(isSelected ? .white.opacity(0.8) : .gray)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.blue : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct WaterHistoryRowView: View {
    let entry: WaterEntry
    var timeString: String {
        guard let date = ISO8601DateFormatter().date(from: entry.recorded_at) else { return "Unknown time" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }
    var body: some View {
        HStack {
            Image(systemName: "drop.fill").foregroundColor(.blue).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(entry.amount)) ml").font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                Text(timeString).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.6))
                        .frame(width: 4, height: CGFloat.random(in: 10...20))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.2), lineWidth: 1)))
    }
}
