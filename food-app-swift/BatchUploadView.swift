//  BatchUploadView.swift
//  food-app-swift
//
//  Created by Helen Tu on 3/2/26.
//


import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Data Models

struct BatchMealResult: Identifiable {
    let id = UUID()
    var image: UIImage
    var status: AnalysisStatus
    var dishName: String = ""
    var visibleIngredients: [EditableIngredient] = []
    var hiddenIngredients: [EditableIngredient] = []
    var rawNutritionInfo: String = ""
    var rawHiddenIngredients: String = ""
    var mealType: String = "LUNCH"
    var savedAt: Date = Date()
    var isSaved: Bool = false

    enum AnalysisStatus {
        case pending, analyzing, completed, failed(String)
    }
}

// MARK: - Main Batch Upload View

struct BatchUploadView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var showCameraPermissionAlert = false
    @State private var batchResults: [BatchMealResult] = []
    @State private var currentIndex: Int = 0
    @State private var isAnalyzing = false
    @State private var analysisProgress: Int = 0
    @State private var stage: Stage = .selection
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSummary = false
    @State private var showDatePicker = false

    enum Stage { case selection, analyzing, results }

    var totalCalories: Int {
        batchResults.filter { if case .completed = $0.status { return true } else { return false } }
            .compactMap { extractCalories(from: $0.rawNutritionInfo) }.reduce(0, +)
    }
    var completedCount: Int {
        batchResults.filter { if case .completed = $0.status { return true } else { return false } }.count
    }
    var allSaved: Bool {
        !batchResults.isEmpty && batchResults.allSatisfy { $0.isSaved }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    headerBar
                    switch stage {
                    case .selection: selectionStage
                    case .analyzing: analyzingStage
                    case .results: resultsStage
                    }
                }
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(toastMessage)
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Capsule().fill(Color.green))
                        .shadow(color: .green.opacity(0.3), radius: 10)
                        .padding(.bottom, 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: showToast)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .onAppear { cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video) }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                loadSelectedPhotos(items)
            }
            .sheet(isPresented: $showCamera) {
                BatchCameraView { image in addCameraImage(image) }
            }
            .sheet(isPresented: $showSummary) {
                BatchSummarySheet(results: batchResults, totalCalories: totalCalories)
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showDatePicker) {
                if !batchResults.isEmpty && currentIndex < batchResults.count {
                    DatePickerSheet(selectedDate: Binding(
                        get: { batchResults[currentIndex].savedAt },
                        set: { batchResults[currentIndex].savedAt = $0 }
                    ))
                }
            }
            .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } message: {
                Text("Please allow camera access in Settings to take photos of your meals.")
            }
        }
    }

    // MARK: - Header

    var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage == .results ? "Results" : "Batch Analysis")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                if stage == .results {
                    Text("\(completedCount) of \(batchResults.count) analyzed")
                        .font(.caption).foregroundColor(themeManager.current.secondaryText)
                } else {
                    Text("Select up to 9 photos")
                        .font(.caption).foregroundColor(themeManager.current.secondaryText)
                }
            }
            Spacer()
            if stage == .results {
                Button(action: { showSummary = true }) {
                    Label("Summary", systemImage: "chart.bar.fill")
                        .font(.caption.bold()).foregroundColor(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    // MARK: - Selection Stage

    var selectionStage: some View {
        ScrollView {
            VStack(spacing: 24) {
                if batchResults.isEmpty { emptySelectionView }
                else { selectedPhotosGrid }

                HStack(spacing: 12) {
                    
                    Button(action: checkCameraAndOpen) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                            Text("Camera")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(14)
                    }

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(1, 9 - batchResults.count),
                        matching: .images
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Gallery (\(batchResults.count)/9)")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(themeManager.current.cardBorder, lineWidth: 1))
                    }
                    .disabled(batchResults.count >= 9)
                    .opacity(batchResults.count >= 9 ? 0.5 : 1)
                }
                .padding(.horizontal, 20)

                if !batchResults.isEmpty {
                    Button(action: startBatchAnalysis) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Analyze \(batchResults.count) Photo\(batchResults.count > 1 ? "s" : "")")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(16)
                        .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 20)
                }
                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
    }

    var emptySelectionView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.current.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .foregroundColor(themeManager.current.cardBorder))
                .frame(height: 240)
            VStack(spacing: 16) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 48)).foregroundColor(.orange.opacity(0.6))
                Text("Select up to 9 photos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                Text("AI analyzes all photos automatically")
                    .font(.caption).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .padding(.horizontal, 20)
    }

    var selectedPhotosGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(batchResults.count) photo\(batchResults.count > 1 ? "s" : "") selected")
                .font(.caption).foregroundColor(themeManager.current.secondaryText)
                .padding(.horizontal, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(batchResults.enumerated()), id: \.element.id) { index, result in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: result.image)
                            .resizable().scaledToFill()
                            .frame(height: 110).clipped().cornerRadius(10)
                        Button(action: { removePhoto(at: index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3).foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                        .padding(4)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Analyzing Stage

    var analyzingStage: some View {
        VStack(spacing: 32) {
            Spacer()
           
            ZStack {
                Circle()
                    .stroke(themeManager.current.cardBorder, lineWidth: 10)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: batchResults.isEmpty ? 0 : CGFloat(analysisProgress) / CGFloat(batchResults.count))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 120, height: 120).rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: analysisProgress)
                VStack(spacing: 2) {
                    Text("\(analysisProgress)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("of \(batchResults.count)")
                        .font(.caption).foregroundColor(themeManager.current.secondaryText)
                }
            }
            Text("Analyzing photos...")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(batchResults.enumerated()), id: \.element.id) { _, result in
                        ZStack {
                            Image(uiImage: result.image)
                                .resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipped().cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .fill(statusOverlayColor(result.status).opacity(0.45)))
                            statusIcon(result.status)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer()
        }
    }

    func statusOverlayColor(_ status: BatchMealResult.AnalysisStatus) -> Color {
        switch status {
        case .pending: return .black
        case .analyzing: return .orange
        case .completed: return .clear
        case .failed: return .red
        }
    }

    @ViewBuilder
    func statusIcon(_ status: BatchMealResult.AnalysisStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock").foregroundColor(.white.opacity(0.7))
        case .analyzing:
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).scaleEffect(0.8)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.title3)
        }
    }

    // MARK: - Results Stage

    var resultsStage: some View {
        VStack(spacing: 0) {
            
            if batchResults.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<batchResults.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentIndex
                                  ? (themeManager.current == .dark ? Color.white : Color.black)
                                  : themeManager.current.cardBorder)
                            .frame(width: i == currentIndex ? 8 : 6, height: i == currentIndex ? 8 : 6)
                            .animation(.spring(), value: currentIndex)
                    }
                }
                .padding(.vertical, 10)
            }

            TabView(selection: $currentIndex) {
                ForEach(Array(batchResults.enumerated()), id: \.element.id) { index, result in
                    resultCard(index: index, result: result).tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            bottomBar
        }
    }

    @ViewBuilder
    func resultCard(index: Int, result: BatchMealResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // saved badge
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: result.image)
                        .resizable().scaledToFill()
                        .frame(height: 220).clipped().cornerRadius(18)
                    if result.isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold()).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.green)).padding(12)
                    }
                }

                switch result.status {
                case .analyzing:
                    AnalyzingView()

                case .failed(let msg):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40)).foregroundColor(.red)
                        Text(msg).font(.subheadline)
                            .foregroundColor(themeManager.current.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Retry") { retryAnalysis(index: index) }
                            .foregroundColor(.orange).fontWeight(.semibold)
                    }.padding()

                case .completed:
                    completedResultContent(index: index, result: result)

                case .pending:
                    Text("Waiting to analyze...")
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 120)
        }
    }

    @ViewBuilder
    func completedResultContent(index: Int, result: BatchMealResult) -> some View {
        VStack(spacing: 16) {
           
            TextField("Dish name", text: Binding(
                get: { batchResults[index].dishName },
                set: { batchResults[index].dishName = $0 }
            ))
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(themeManager.current.primaryText)
            .padding(14)
            .background(themeManager.current.inputBackground)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1))

           
            HStack(spacing: 12) {
                MealTypeSelector(selectedType: Binding(
                    get: { batchResults[index].mealType },
                    set: { batchResults[index].mealType = $0 }
                ))
                .environmentObject(themeManager)

                DateSelector(
                    selectedDate: Binding(
                        get: { batchResults[index].savedAt },
                        set: { batchResults[index].savedAt = $0 }
                    ),
                    showPicker: $showDatePicker
                )
                .environmentObject(themeManager)
            }

            
            if !result.rawNutritionInfo.isEmpty {
                BeautifulNutritionView(nutritionText: result.rawNutritionInfo)
                    .environmentObject(themeManager)
            }

          
            let allIngredients = result.visibleIngredients + result.hiddenIngredients
            if !allIngredients.isEmpty {
                IngredientTableView(ingredients: allIngredients)
                    .environmentObject(themeManager)
            }

            
            if !result.isSaved {
                Button(action: { saveSingleMeal(index: index) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save This Meal")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.green).cornerRadius(16)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved to Diary")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.opacity(0.1)))
            }
        }
    }

    // MARK: - Bottom Bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(themeManager.current.cardBorder)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total").font(.caption2).foregroundColor(themeManager.current.secondaryText)
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 12)).foregroundColor(.orange)
                        Text("\(totalCalories) kcal")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                    }
                }
                Spacer()
                if !allSaved {
                    Button(action: saveAllMeals) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save All")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(14)
                    }
                } else {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32).padding(.vertical, 12)
                            .background(Color.green).cornerRadius(14)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(themeManager.current.cardBackground)
        }
    }

    

    func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        if batchResults.count < 9 { batchResults.append(BatchMealResult(image: image, status: .pending)) }
                    }
                }
            }
            await MainActor.run { selectedPhotos = [] }
        }
    }

    func addCameraImage(_ image: UIImage) {
        guard batchResults.count < 9 else { return }
        batchResults.append(BatchMealResult(image: image, status: .pending))
    }

    func removePhoto(at index: Int) { batchResults.remove(at: index) }

    func checkCameraAndOpen() {
        switch cameraPermissionStatus {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermissionStatus = granted ? .authorized : .denied
                    if granted { self.showCamera = true } else { self.showCameraPermissionAlert = true }
                }
            }
        default: showCameraPermissionAlert = true
        }
    }

    func startBatchAnalysis() {
        stage = .analyzing; isAnalyzing = true; analysisProgress = 0
        for i in 0..<batchResults.count { batchResults[i].status = .analyzing }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<batchResults.count {
                    group.addTask { await self.analyzeSingle(index: index) }
                }
            }
            await MainActor.run {
                self.isAnalyzing = false
                withAnimation(.spring()) { self.stage = .results; self.currentIndex = 0 }
            }
        }
    }

    func analyzeSingle(index: Int) async {
        let image = await MainActor.run { batchResults[index].image }
        guard let imageData = compressImage(image, maxSizeKB: 500) else {
            await MainActor.run {
                self.batchResults[index].status = .failed("Failed to process image")
                self.analysisProgress += 1
            }
            return
        }
        await withCheckedContinuation { continuation in
            NetworkManager.shared.uploadImage(imageData: imageData) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let g):
                        self.batchResults[index].dishName = g.dish_prediction
                        self.batchResults[index].visibleIngredients = self.parseIngredientsToEditable(from: g.image_description)
                        self.batchResults[index].rawNutritionInfo = g.nutrition_info
                        if let hidden = g.hidden_ingredients, !hidden.isEmpty {
                            self.batchResults[index].hiddenIngredients = self.parseIngredientsToEditable(from: hidden)
                            self.batchResults[index].rawHiddenIngredients = hidden
                        }
                        self.batchResults[index].status = .completed
                    case .failure(let e):
                        self.batchResults[index].status = .failed(e.localizedDescription)
                    }
                    self.analysisProgress += 1
                    continuation.resume()
                }
            }
        }
    }

    func retryAnalysis(index: Int) {
        batchResults[index].status = .analyzing
        let image = batchResults[index].image
        guard let imageData = compressImage(image, maxSizeKB: 500) else {
            batchResults[index].status = .failed("Failed to process image"); return
        }
        NetworkManager.shared.uploadImage(imageData: imageData) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let g):
                    self.batchResults[index].dishName = g.dish_prediction
                    self.batchResults[index].rawNutritionInfo = g.nutrition_info
                    self.batchResults[index].status = .completed
                case .failure(let e):
                    self.batchResults[index].status = .failed(e.localizedDescription)
                }
            }
        }
    }

    func saveSingleMeal(index: Int) {
        guard !batchResults[index].isSaved else { return }
        guard case .completed = batchResults[index].status else { return }
        batchResults[index].isSaved = true

        let result = batchResults[index]
        let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
        let fullBase64 = compressImage(result.image, maxSizeKB: 500)?.base64EncodedString() ?? ""
        let thumbBase64 = compressImage(result.image, maxSizeKB: 50)?.base64EncodedString() ?? ""
        let visibleStr = result.visibleIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit)" }.joined(separator: "\n")
        let hiddenStr = result.hiddenIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit)" }.joined(separator: "\n")
        let payload: [String: Any] = [
            "user_id": userId, "dish_prediction": result.dishName,
            "image_description": visibleStr, "hidden_ingredients": hiddenStr,
            "nutrition_info": result.rawNutritionInfo, "image_full": fullBase64,
            "image_thumb": thumbBase64, "meal_type": result.mealType,
            "saved_at": ISO8601DateFormatter().string(from: result.savedAt)
        ]
        NetworkManager.shared.saveMeal(payload) { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.showToastMessage("Meal saved!")
                } else {
                    self.batchResults[index].isSaved = false
                }
            }
        }
    }

    func saveAllMeals() {
        let indicesToSave = (0..<batchResults.count).filter { index in
            !batchResults[index].isSaved &&
            { if case .completed = batchResults[index].status { return true } else { return false } }()
        }
        for index in indicesToSave { saveSingleMeal(index: index) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
        }
    }

    func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showToast = false } }
    }

    func compressImage(_ image: UIImage, maxSizeKB: Int) -> Data? {
        let maxDim: CGFloat = 1024
        let size = image.size
        var newSize = size
        if size.width > maxDim || size.height > maxDim {
            let ratio = min(maxDim / size.width, maxDim / size.height)
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        var compression: CGFloat = 0.8
        var data = resized.jpegData(compressionQuality: compression)
        while let d = data, d.count > maxSizeKB * 1024, compression > 0.1 {
            compression -= 0.1; data = resized.jpegData(compressionQuality: compression)
        }
        return data
    }

    func parseIngredientsToEditable(from text: String) -> [EditableIngredient] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            let name = parts[0]
            let quantity = parts[1]
           
            let rawUnit = parts.count >= 3 ? parts[2] : ""
            let unit: String
            if Double(rawUnit) != nil || rawUnit.isEmpty {
                unit = guessIngredientUnit(for: name)
            } else {
                unit = rawUnit
            }
            return EditableIngredient(id: UUID().uuidString, name: name, quantity: quantity, unit: unit)
        }
    }

    func guessIngredientUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("oil") || n.contains("sauce") || n.contains("milk") || n.contains("water") || n.contains("vinegar") { return "ml" }
        if n.contains("salt") || n.contains("pepper") || n.contains("spice") || n.contains("powder") { return "tsp" }
        if n.contains("bread") || n.contains("egg") || n.contains("slice") || n.contains("piece") { return "pcs" }
        return "g"
    }

    func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|")
            if parts.count >= 2, parts[0].lowercased().contains("calories") {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}

// MARK: - Batch Summary Sheet

struct BatchSummarySheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    let results: [BatchMealResult]
    let totalCalories: Int
    @Environment(\.dismiss) var dismiss

    var completedResults: [BatchMealResult] {
        results.filter { if case .completed = $0.status { return true } else { return false } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                      
                        VStack(spacing: 6) {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text("\(totalCalories)")
                                    .font(.system(size: 56, weight: .black, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("kcal")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            Text("Total Calories")
                                .font(.subheadline)
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.vertical, 24).frame(maxWidth: .infinity)
                        .background(themeManager.current.cardBackground)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(themeManager.current.cardBorder, lineWidth: 1))


                        VStack(alignment: .leading, spacing: 12) {
                            Text("Meal Breakdown")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(themeManager.current.primaryText)
                            ForEach(Array(completedResults.enumerated()), id: \.element.id) { index, result in
                                HStack(spacing: 12) {
                                    Image(uiImage: result.image)
                                        .resizable().scaledToFill()
                                        .frame(width: 50, height: 50).clipped()
                                        .cornerRadius(12)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.dishName.isEmpty ? "Meal \(index + 1)" : result.dishName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(themeManager.current.primaryText)
                                        Text(result.mealType.capitalized)
                                            .font(.caption)
                                            .foregroundColor(themeManager.current.secondaryText)
                                    }
                                    Spacer()
                                    if let cal = extractCalories(from: result.rawNutritionInfo) {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text("\(cal)")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(themeManager.current.primaryText)
                                            Text("kcal").font(.caption)
                                                .foregroundColor(themeManager.current.secondaryText)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(themeManager.current.cardBackground)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(themeManager.current.cardBorder, lineWidth: 1))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationTitle("Batch Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.current == .dark ? .white : .black)
                }
            }
        }
    }

    func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|")
            if parts.count >= 2, parts[0].lowercased().contains("calories") {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}



struct BatchCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: BatchCameraView
        init(_ parent: BatchCameraView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
