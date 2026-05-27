import SwiftUI
import PhotosUI
import AVFoundation

struct UploadMealView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoading = false
    @State private var detectedDish: String = ""
    @State private var editableDishName: String = ""
    @State private var visibleIngredients: [EditableIngredient] = []
    @State private var hiddenIngredients: [EditableIngredient] = []
    @State private var nutritionLines: [String] = []
    @State private var rawNutritionInfo: String = ""
    @State private var rawHiddenIngredients: String = ""
    @State private var calories: Int?
    @State private var showToast = false
    @State private var errorMessage = ""
    @State private var retryCount = 0
    @State private var selectedDate = Date()
    @State private var selectedMealType = "Lunch"
    @State private var isEditingIngredients = false
    @State private var isEditingHidden = false
    @State private var showDatePicker = false
    @State private var showCamera = false
    @State private var analysisStep = 0
    @State private var isRecalculatingNutrition = false
    @State private var showCameraPermissionAlert = false
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var showColdStartLoading = false
    @State private var currentError: AppError?
    @State private var analysisRequestId: String?

    let mealTypes = ["Breakfast", "Lunch", "Evening Snacks", "Dinner"]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add Meal").font(.largeTitle.bold())
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("Snap and track your nutrition").font(.caption)
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill").font(.title2)
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                        .padding(.horizontal).padding(.top, 20)
                        .overlay(
                            ZStack {
                                if showColdStartLoading { ServerWarmupView() }
                                if let error = currentError { ErrorToast(error: error, isShowing: .constant(true)) }
                            }
                        )

                        if selectedImage == nil {
                            VStack(spacing: 20) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.1)]),
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 250)
                                        .overlay(RoundedRectangle(cornerRadius: 20)
                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                            .foregroundColor(.orange.opacity(0.5)))
                                    VStack(spacing: 16) {
                                        Image(systemName: "camera.fill").font(.system(size: 50)).foregroundColor(.orange)
                                        Text("Add a photo of your meal").font(.headline)
                                            .foregroundColor(themeManager.current.primaryText)
                                        Text("Take a photo or choose from library").font(.caption)
                                            .foregroundColor(themeManager.current.secondaryText)
                                    }
                                }
                                HStack(spacing: 16) {
                                    Button(action: { checkCameraPermissionAndOpen() }) {
                                        HStack { Image(systemName: "camera.fill"); Text("Camera") }
                                            .fontWeight(.semibold).foregroundColor(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                                            .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .cornerRadius(12)
                                    }
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        HStack { Image(systemName: "photo.fill"); Text("Gallery") }
                                            .fontWeight(.semibold).foregroundColor(themeManager.current.primaryText)
                                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                                            .background(RoundedRectangle(cornerRadius: 12)
                                                .fill(themeManager.current.inputBackground)
                                                .overlay(RoundedRectangle(cornerRadius: 12)
                                                    .stroke(themeManager.current.cardBorder, lineWidth: 1)))
                                    }
                                    .onChange(of: selectedPhoto, initial: false) { _, newItem in
                                        Task {
                                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                                               let uiImage = UIImage(data: data) {
                                                self.selectedImage = uiImage; self.errorMessage = ""; self.retryCount = 0
                                                analyzeImage()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            ZStack {
                                Image(uiImage: selectedImage!).resizable().scaledToFill()
                                    .frame(height: 250).clipped().cornerRadius(20)
                                    .overlay(LinearGradient(gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.3)]),
                                                            startPoint: .center, endPoint: .bottom).cornerRadius(20))
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            selectedImage = nil; detectedDish = ""
                                            visibleIngredients = []; hiddenIngredients = []
                                            nutritionLines = []; rawNutritionInfo = ""
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.triangle.2.circlepath"); Text("Change")
                                            }
                                            .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Capsule().fill(Color.black.opacity(0.6)).blur(radius: 10))
                                        }
                                        .padding()
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.horizontal)

                            if isLoading {
                                AnalyzingView()
                            } else if !errorMessage.isEmpty {
                                ErrorView(message: errorMessage, retry: analyzeImage)
                                    .environmentObject(themeManager).padding(.horizontal)
                            } else if !detectedDish.isEmpty {
                                VStack(spacing: 20) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("DISH NAME").font(.caption)
                                            .foregroundColor(themeManager.current.secondaryText).tracking(1)
                                        TextField("Dish name", text: $editableDishName)
                                            .font(.title3.bold()).foregroundColor(themeManager.current.primaryText)
                                            .padding()
                                            .background(RoundedRectangle(cornerRadius: 12)
                                                .fill(themeManager.current.inputBackground)
                                                .overlay(RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)))
                                    }
                                    .padding(.horizontal)

                                    HStack(spacing: 16) {
                                        MealTypeSelector(selectedType: $selectedMealType)
                                            .environmentObject(themeManager)
                                        DateSelector(selectedDate: $selectedDate, showPicker: $showDatePicker)
                                            .environmentObject(themeManager)
                                    }
                                    .padding(.horizontal)

                                    VStack(alignment: .leading, spacing: 16) {
                                        SectionHeader(title: "Visible Ingredients", icon: "leaf.fill", color: Color.green,
                                                      action: { isEditingIngredients.toggle() },
                                                      actionIcon: isEditingIngredients ? "checkmark" : "pencil")
                                            .environmentObject(themeManager)
                                        VStack(spacing: 12) {
                                            ForEach($visibleIngredients) { $ingredient in
                                                if isEditingIngredients {
                                                    EditableIngredientRow(ingredient: $ingredient,
                                                                          onDelete: { removeVisibleIngredient(id: ingredient.id) })
                                                        .environmentObject(themeManager)
                                                } else {
                                                    IngredientDisplay(text: "\(ingredient.name) – \(ingredient.quantity) \(ingredient.unit)")
                                                        .environmentObject(themeManager)
                                                }
                                            }
                                            if isEditingIngredients {
                                                Button(action: addNewVisibleIngredient) {
                                                    HStack { Image(systemName: "plus.circle.fill"); Text("Add Ingredient") }
                                                        .font(.subheadline).foregroundColor(Color.green)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)

                                    if !hiddenIngredients.isEmpty {
                                        VStack(alignment: .leading, spacing: 16) {
                                            SectionHeader(title: "Hidden Ingredients", icon: "eye.slash.fill", color: Color.pink,
                                                          action: { isEditingHidden.toggle() },
                                                          actionIcon: isEditingHidden ? "checkmark" : "pencil")
                                                .environmentObject(themeManager)
                                            VStack(spacing: 12) {
                                                ForEach($hiddenIngredients) { $ingredient in
                                                    if isEditingHidden {
                                                        EditableIngredientRow(ingredient: $ingredient,
                                                                              onDelete: { removeHiddenIngredient(id: ingredient.id) })
                                                            .environmentObject(themeManager)
                                                    } else {
                                                        IngredientDisplay(text: "\(ingredient.name) – \(ingredient.quantity) \(ingredient.unit)", isHidden: true)
                                                            .environmentObject(themeManager)
                                                    }
                                                }
                                                if isEditingHidden {
                                                    Button(action: addNewHiddenIngredient) {
                                                        HStack { Image(systemName: "plus.circle.fill"); Text("Add Hidden Ingredient") }
                                                            .font(.subheadline).foregroundColor(Color.pink)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }

                                    VStack(spacing: 16) {
                                        BeautifulNutritionView(nutritionText: rawNutritionInfo)
                                            .environmentObject(themeManager)
                                        if isEditingIngredients || isEditingHidden {
                                            Button(action: recalculateNutrition) {
                                                HStack {
                                                    if isRecalculatingNutrition {
                                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.8)
                                                    } else {
                                                        Image(systemName: "arrow.clockwise"); Text("Recalculate Nutrition")
                                                    }
                                                }
                                                .fontWeight(.semibold).foregroundColor(.white)
                                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                                .background(LinearGradient(gradient: Gradient(colors: [.purple, .purple.opacity(0.8)]),
                                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .cornerRadius(12)
                                            }
                                            .disabled(isRecalculatingNutrition)
                                        }
                                    }
                                    .padding(.horizontal)

                                    Button(action: saveMealToBackend) {
                                        HStack { Image(systemName: "checkmark.circle.fill"); Text("Save to Diary") }
                                            .fontWeight(.semibold).foregroundColor(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                                            .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .cornerRadius(12).shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                                    }
                                    .padding(.horizontal).padding(.bottom, 40)
                                }
                            }
                        }
                    }
                }

                if showToast {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill"); Text("Meal saved successfully!")
                        }
                        .font(.subheadline.bold()).foregroundColor(.white).padding()
                        .background(Capsule().fill(Color.green).shadow(color: Color.green.opacity(0.3), radius: 10))
                        .transition(.move(edge: .bottom).combined(with: .opacity)).padding(.bottom, 50)
                    }
                    .animation(.spring(), value: showToast)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .onAppear { checkInitialCameraPermission() }
            .sheet(isPresented: $showDatePicker) { DatePickerSheet(selectedDate: $selectedDate) }
            .sheet(isPresented: $showCamera) {
                SimpleCameraView(selectedImage: $selectedImage)
                    .onDisappear { if selectedImage != nil { analyzeImage() } }
            }
            .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Settings") { openAppSettings() }
            } message: {
                Text("Please allow camera access in Settings to take photos of your meals.")
            }
        }
    }

    func checkInitialCameraPermission() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func checkCameraPermissionAndOpen() {
        switch cameraPermissionStatus {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.cameraPermissionStatus = .authorized; self.showCamera = true }
                    else { self.cameraPermissionStatus = .denied; self.showCameraPermissionAlert = true }
                }
            }
        default: showCameraPermissionAlert = true
        }
    }

    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    func removeVisibleIngredient(id: String) { visibleIngredients.removeAll { $0.id == id } }
    func removeHiddenIngredient(id: String) { hiddenIngredients.removeAll { $0.id == id } }

    func addNewVisibleIngredient() {
        visibleIngredients.append(EditableIngredient(id: UUID().uuidString, name: "New Ingredient", quantity: "1", unit: "piece"))
    }
    func addNewHiddenIngredient() {
        hiddenIngredients.append(EditableIngredient(id: UUID().uuidString, name: "New Hidden Ingredient", quantity: "1", unit: "tsp"))
    }

    func recalculateNutrition() {
        isRecalculatingNutrition = true
        let allIngredients = visibleIngredients + hiddenIngredients
        let ingredientsList = allIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit)" }.joined(separator: "\n")
        NetworkManager.shared.recalculateNutrition(ingredients: ingredientsList) { result in
            self.isRecalculatingNutrition = false
            switch result {
            case .success(let nutritionData):
                self.rawNutritionInfo = nutritionData.nutrition_info
                self.nutritionLines = self.parseNutritionLines(from: nutritionData.nutrition_info)
                self.calories = self.extractCalories(from: nutritionData.nutrition_info)
            case .failure(let error):
                print("❌ Nutrition recalculation failed: \(error)")
                self.errorMessage = "Failed to recalculate nutrition"
            }
        }
    }

    func resizeImage(_ image: UIImage, maxDimension: CGFloat = 800) -> UIImage? {
        let size = image.size
        var newSize: CGSize
        if size.width > size.height {
            if size.width > maxDimension { newSize = CGSize(width: maxDimension, height: size.height * maxDimension / size.width) }
            else { return image }
        } else {
            if size.height > maxDimension { newSize = CGSize(width: size.width * maxDimension / size.height, height: maxDimension) }
            else { return image }
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }

    func compressImage(_ image: UIImage, maxSizeKB: Int = 500) -> Data? {
        let resized = resizeImage(image, maxDimension: 1024) ?? image
        var compression: CGFloat = 0.8
        var imageData = resized.jpegData(compressionQuality: compression)
        while let data = imageData, data.count > maxSizeKB * 1024 && compression > 0.1 {
            compression -= 0.1; imageData = resized.jpegData(compressionQuality: compression)
        }
        if let data = imageData, data.count > maxSizeKB * 1024 {
            let smallerImage = resizeImage(resized, maxDimension: 600) ?? resized
            imageData = smallerImage.jpegData(compressionQuality: 0.5)
        }
        return imageData
    }

    func analyzeImage() {
        guard let image = selectedImage else { return }
        isLoading = true; errorMessage = ""; currentError = nil
        let resizedImage = resizeImage(image, maxDimension: 800) ?? image
        guard let imageData = compressImage(resizedImage, maxSizeKB: 500) else {
            isLoading = false; currentError = .validation("Failed to process image"); return
        }
        NetworkManager.shared.uploadImageWithColdStartHandling(imageData: imageData, onColdStart: {
            self.showColdStartLoading = true
        }) { result in
            self.isLoading = false; self.showColdStartLoading = false
            switch result {
            case .success(let geminiResult):
                withAnimation(.spring()) {
                    self.analysisRequestId = geminiResult.requestId
                    self.detectedDish = geminiResult.dish_prediction
                    self.editableDishName = geminiResult.dish_prediction
                    self.visibleIngredients = self.parseIngredientsToEditable(from: geminiResult.image_description)
                    if let hiddenText = geminiResult.hidden_ingredients, !hiddenText.isEmpty {
                        self.hiddenIngredients = self.parseIngredientsToEditable(from: hiddenText)
                        self.rawHiddenIngredients = hiddenText
                    } else { self.hiddenIngredients = []; self.rawHiddenIngredients = "" }
                    self.rawNutritionInfo = geminiResult.nutrition_info
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.rawNutritionInfo = geminiResult.nutrition_info }
                    self.nutritionLines = self.parseNutritionLines(from: geminiResult.nutrition_info)
                    self.calories = self.extractCalories(from: geminiResult.nutrition_info)
                }
            case .failure(let error):
                if (error as NSError).code == NSURLErrorTimedOut { self.currentError = .network(.timeout) }
                else if (error as NSError).code == NSURLErrorNotConnectedToInternet { self.currentError = .network(.noInternet) }
                else { self.currentError = .unknown(error.localizedDescription) }
            }
        }
    }

    func saveMealToBackend() {
        guard !editableDishName.isEmpty else { errorMessage = "Please enter a dish name"; return }
        let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
        if userId.isEmpty { errorMessage = "Login session missing."; return }
        isLoading = true; errorMessage = ""
        let fullImageData = compressImage(selectedImage!, maxSizeKB: 500)
        let thumbnailData = compressImage(selectedImage!, maxSizeKB: 50)
        let fullImageBase64 = fullImageData?.base64EncodedString() ?? ""
        let thumbnailBase64 = thumbnailData?.base64EncodedString() ?? ""
        let visibleIngredientsString = visibleIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit) | User edited" }.joined(separator: "\n")
        let hiddenIngredientsString = hiddenIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit) | User edited" }.joined(separator: "\n")
        let payload: [String: Any] = [
            "user_id": userId, "dish_prediction": editableDishName,
            "image_description": visibleIngredientsString, "hidden_ingredients": hiddenIngredientsString,
            "nutrition_info": rawNutritionInfo, "image_full": fullImageBase64,
            "image_thumb": thumbnailBase64, "meal_type": selectedMealType,
            "saved_at": ISO8601DateFormatter().string(from: selectedDate)
        ]
        if let requestId = analysisRequestId, !requestId.isEmpty {
            payload["request_id"] = requestId
        }
        NetworkManager.shared.saveMeal(payload) { success, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
                    withAnimation(.spring()) { self.showToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.dismiss() }
                } else {
                    if let errorMsg = error {
                        if errorMsg.contains("network connection was lost") || errorMsg.contains("-1005") {
                            self.errorMessage = "Connection lost. The image might be too large."
                        } else if errorMsg.contains("timed out") {
                            self.errorMessage = "Server timeout. Please try again."
                        } else { self.errorMessage = "Failed to save meal: \(errorMsg)" }
                    } else { self.errorMessage = "Failed to save meal. Please try again." }
                }
            }
        }
    }

    func parseIngredientsToEditable(from text: String) -> [EditableIngredient] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            return EditableIngredient(id: UUID().uuidString, name: parts[0], quantity: parts[1], unit: parts[2])
        }
    }

    func parseNutritionLines(from text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count >= 2 else { return nil }
            let nutrient = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            let unit = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            return "\(nutrient) – \(value) \(unit)"
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

// MARK: - Simple Camera View

struct SimpleCameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.allowsEditing = false; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SimpleCameraView
        init(_ parent: SimpleCameraView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.selectedImage = image }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Supporting Views

struct MealTypeSelector: View {
    @EnvironmentObject var themeManager: ThemeManager  // ✅
    @Binding var selectedType: String
    let types = ["Breakfast", "Lunch", "Evening Snacks", "Dinner"]
    let icons = ["sun.max.fill", "sun.min.fill", "cup.and.saucer.fill", "moon.fill"]

    var body: some View {
        Menu {
            ForEach(Array(zip(types, icons)), id: \.0) { type, icon in
                Button(action: { selectedType = type }) { Label(type, systemImage: icon) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEAL TYPE").font(.caption2)
                    .foregroundColor(themeManager.current.secondaryText).tracking(1)  // ✅
                HStack {
                    Image(systemName: icons[types.firstIndex(of: selectedType) ?? 1]).foregroundColor(.orange)
                    Text(selectedType).fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption)
                }
                .foregroundColor(themeManager.current.primaryText)  // ✅
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.current.inputBackground)  // ✅
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.current.cardBorder, lineWidth: 1)))  // ✅
        }
    }
}

struct DateSelector: View {
    @EnvironmentObject var themeManager: ThemeManager  // ✅
    @Binding var selectedDate: Date
    @Binding var showPicker: Bool

    var dateText: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        Button(action: { showPicker = true }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DATE").font(.caption2)
                    .foregroundColor(themeManager.current.secondaryText).tracking(1)  // ✅
                HStack {
                    Image(systemName: "calendar").foregroundColor(Color.blue)
                    Text(dateText).fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(themeManager.current.primaryText)  // ✅
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.current.inputBackground)  // ✅
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.current.cardBorder, lineWidth: 1)))  // ✅
        }
    }
}

struct AnalyzingView: View {
    @State private var dots = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.2), lineWidth: 4).frame(width: 80, height: 80)
                Circle().trim(from: 0, to: 0.7)
                    .stroke(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.5)]),
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80).rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(Double(dots) * 120))
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: dots)
                Image(systemName: "sparkles").font(.title).foregroundColor(.orange)
            }
            VStack(spacing: 8) {
                Text("Analyzing your meal").font(.headline).foregroundColor(.white)
                Text("Identifying ingredients and hidden components")
                    .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear { dots = 3 }
    }
}
