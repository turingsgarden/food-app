//
//  EditHealthProfieView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/13/26.
//
//
//  EditHealthProfileView.swift  — PDF / Word / Image OCR patch
//  food-app-swift
//
//  Changes vs previous version:
//  1. Added UniformTypeIdentifiers import
//  2. Added @State vars for file importer
//  3. scanBanner now shows three options: Camera / Photo Library / File (PDF·Word)
//  4. New fileImporter sheet handles .pdf and .docx
//  5. runOCROnFile() encodes file bytes and hits /ocr-document
//  6. callDocumentOCR() mirrors callGeminiOCR() but uses file_type param
//  All other logic (sliders, save, prefill, etc.) is UNCHANGED.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers   // ← NEW

// ── OCRHealthResult and all other structs are unchanged ───────────────────────

struct OCRHealthResult {
    var systolicBP: Int?
    var diastolicBP: Int?
    var bloodSugar: Double?
    var cholesterol: Double?
    var triglycerides: Double?
    var heightCm: Double?
    var weightKg: Double?

    var hasAnyResult: Bool {
        systolicBP != nil || diastolicBP != nil || bloodSugar != nil ||
        cholesterol != nil || triglycerides != nil || heightCm != nil || weightKg != nil
    }
}

// MARK: - Main View

struct EditHealthProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @Environment(\.dismiss) var dismiss

    var onComplete: ((HealthProfile) -> Void)?

    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var age: Int = 25
    @State private var sex: String = "female"

    @State private var hasBP = false
    @State private var systolicBP: Double = 120
    @State private var diastolicBP: Double = 80
    @State private var hasBloodSugar = false
    @State private var bloodSugar: Double = 5.0
    @State private var hasCholesterol = false
    @State private var cholesterol: Double = 4.5
    @State private var hasTriglycerides = false
    @State private var triglycerides: Double = 1.2

    @State private var selectedDietary: Set<String> = []
    @State private var selectedAllergens: Set<String> = []

    @State private var isSaving = false
    @State private var errorMsg = ""
    @State private var showError = false

    // ── OCR state ──────────────────────────────────────────────────────────────
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showScanOptions = false          // confirmationDialog
    @State private var showFilePicker = false           // ← NEW: file importer
    @State private var isScanning = false
    @State private var scanResult: OCRHealthResult? = nil
    @State private var showScanResult = false
    @State private var scanErrorMsg = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var scannedImage: UIImage? = nil

    private let prefill: HealthProfile?
    private var initialProfile: HealthProfile?

    init(existingProfile: HealthProfile? = nil, onComplete: ((HealthProfile) -> Void)? = nil) {
        self.prefill = existingProfile
        self.onComplete = onComplete
        self.initialProfile = existingProfile
    }

    var bmi: Double { let h = heightCm / 100; return weightKg / (h * h) }

    var bmiLabel: (String, Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", .blue)
        case 18.5..<25: return ("Normal", .green)
        case 25..<30: return ("Overweight", .orange)
        default: return ("Obese", .red)
        }
    }

    var currentUserId: String {
        session.userID.isEmpty ? UserDefaults.standard.string(forKey: "user_id") ?? "" : session.userID
    }

    var hasChanges: Bool {
        guard let original = initialProfile else { return true }
        if abs(heightCm - original.heightCm) > 0.1 { return true }
        if abs(weightKg - original.weightKg) > 0.1 { return true }
        if age != original.age { return true }
        if sex != original.sex { return true }
        if hasBP != (original.systolicBP != nil) { return true }
        if hasBP, let os = original.systolicBP, let od = original.diastolicBP {
            if abs(systolicBP - Double(os)) > 0.5 { return true }
            if abs(diastolicBP - Double(od)) > 0.5 { return true }
        }
        if hasBloodSugar != (original.fastingBloodSugar != nil) { return true }
        if hasBloodSugar, let obs = original.fastingBloodSugar {
            if abs(bloodSugar - obs) > 0.05 { return true }
        }
        if hasCholesterol != (original.totalCholesterol != nil) { return true }
        if hasCholesterol, let oc = original.totalCholesterol {
            if abs(cholesterol - oc) > 0.05 { return true }
        }
        if hasTriglycerides != (original.triglycerides != nil) { return true }
        if hasTriglycerides, let ot = original.triglycerides {
            if abs(triglycerides - ot) > 0.05 { return true }
        }
        if selectedDietary != Set(original.dietaryPreferences) { return true }
        if selectedAllergens != Set(original.allergens) { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        bmiPreview.padding(.top, 12)
                        scanBanner.padding(.horizontal, 0)

                        sectionCard(title: "Body Metrics", icon: "figure.stand") {
                            VStack(spacing: 16) {
                                inlineSlider(label: "Height", value: $heightCm, range: 100...220, step: 1,
                                             display: "\(Int(heightCm)) cm")
                                inlineSlider(label: "Weight", value: $weightKg, range: 30...250, step: 0.5,
                                             display: String(format: "%.1f kg", weightKg))
                                inlineSlider(label: "Age", value: Binding(
                                    get: { Double(age) }, set: { age = Int($0) }),
                                    range: 12...100, step: 1, display: "\(age) yrs")
                                sexPicker
                            }
                        }

                        sectionCard(title: "Clinical Markers", icon: "heart.fill") {
                            VStack(spacing: 12) {
                                if showScanResult, let result = scanResult, result.hasAnyResult {
                                    ocrResultBadge(result: result)
                                }
                                Text("Optional — fill in if you have these values")
                                    .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                clinicalRow(title: "Blood Pressure", subtitle: "Normal: 90–120 / 60–80 mmHg", isOn: $hasBP) {
                                    VStack(spacing: 10) {
                                        inlineSlider(label: "Systolic", value: $systolicBP, range: 80...200, step: 1,
                                                     display: "\(Int(systolicBP)) mmHg", warningRange: 120...139)
                                        inlineSlider(label: "Diastolic", value: $diastolicBP, range: 40...130, step: 1,
                                                     display: "\(Int(diastolicBP)) mmHg", warningRange: 80...89)
                                    }
                                }
                                clinicalRow(title: "Fasting Blood Sugar", subtitle: "Normal: 3.9–5.5 mmol/L", isOn: $hasBloodSugar) {
                                    inlineSlider(label: "Blood Sugar", value: $bloodSugar, range: 2.0...15.0, step: 0.1,
                                                 display: String(format: "%.1f mmol/L", bloodSugar), warningRange: 5.6...6.9)
                                }
                                clinicalRow(title: "Total Cholesterol", subtitle: "Normal: < 5.2 mmol/L", isOn: $hasCholesterol) {
                                    inlineSlider(label: "Cholesterol", value: $cholesterol, range: 1.0...10.0, step: 0.1,
                                                 display: String(format: "%.1f mmol/L", cholesterol), warningRange: 5.2...6.2)
                                }
                                clinicalRow(title: "Triglycerides", subtitle: "Normal: < 1.7 mmol/L", isOn: $hasTriglycerides) {
                                    inlineSlider(label: "Triglycerides", value: $triglycerides, range: 0.2...8.0, step: 0.1,
                                                 display: String(format: "%.1f mmol/L", triglycerides), warningRange: 1.7...2.3)
                                }
                            }
                        }

                        sectionCard(title: "Dietary Preferences", icon: "leaf.fill") { dietaryGrid }
                        sectionCard(title: "Allergens to Avoid", icon: "exclamationmark.triangle.fill") { allergenGrid }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 12)
                }

                if isScanning { scanningOverlay }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationTitle("Health Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(themeManager.current.primaryText)
                }
            }
            .onAppear { applyPrefill() }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }

            // ── Photo library picker ─────────────────────────────────────────
            .photosPicker(isPresented: $showImagePicker,
                          selection: $selectedPhotoItem,
                          matching: .images)
            .onChange(of: selectedPhotoItem) { newItem in
                Task { await loadAndScanPhoto(item: newItem) }
            }

            // ── Camera ───────────────────────────────────────────────────────
            .sheet(isPresented: $showCamera) {
                CameraPickerForOCR { image in
                    self.scannedImage = image
                    self.runOCR(on: image)
                }
            }

            // ── File picker (PDF / Word) ─────────────────────────────────────
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    UTType.pdf,
                    UTType(filenameExtension: "docx") ?? UTType.data
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFilePickerResult(result)
            }

            // ── Scan source chooser ──────────────────────────────────────────
            .confirmationDialog("Scan Medical Report", isPresented: $showScanOptions, titleVisibility: .visible) {
                Button("Take Photo")            { showCamera = true }
                Button("Choose Photo")          { showImagePicker = true }
                Button("Import PDF or Word")    { showFilePicker = true }   // ← NEW
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Upload a photo, image, PDF, or Word document containing your lab or health report.")
            }
        }
    }

    // MARK: - Scan Banner (unchanged appearance)

    var scanBanner: some View {
        Button(action: { showScanOptions = true }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan Your Health Report")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Auto-fill values from a photo, PDF, or Word document")  // ← updated subtitle
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // File type badges
                HStack(spacing: 4) {
                    ForEach(["IMG", "PDF", "DOC"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(14)
            .background(themeManager.current.cardBackground)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.2), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Picker Handler (NEW)

    func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            errorMsg = "Could not open file: \(err.localizedDescription)"
            showError = true

        case .success(let urls):
            guard let url = urls.first else { return }

            // Security-scoped resource access required for files outside the sandbox
            guard url.startAccessingSecurityScopedResource() else {
                errorMsg = "Permission denied for this file."
                showError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let ext  = url.pathExtension.lowercased()
                let fileType: String = (ext == "pdf") ? "pdf" : "docx"
                runOCROnFile(data: data, fileType: fileType)
            } catch {
                errorMsg = "Failed to read file: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - OCR on File (NEW)

    func runOCROnFile(data: Data, fileType: String) {
        isScanning = true
        showScanResult = false
        let base64 = data.base64EncodedString()
        callDocumentOCR(base64: base64, fileType: fileType)
    }

    func callDocumentOCR(base64: String, fileType: String) {
        guard let token = session.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/ocr-document") else {
            DispatchQueue.main.async {
                self.isScanning = false
                self.errorMsg = "Unable to connect to OCR service."
                self.showError = true
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60    // documents can be larger than images

        let body: [String: Any] = ["file_base64": base64, "file_type": fileType]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isScanning = false
                if let error = error {
                    self.errorMsg = "Scan failed: \(error.localizedDescription)"
                    self.showError = true
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMsg = "Could not read scan results. Please try again or enter values manually."
                    self.showError = true
                    return
                }
                let result = self.parseOCRResult(json: json)
                if result.hasAnyResult {
                    self.applyOCRResult(result)
                    self.scanResult = result
                    self.showScanResult = true
                } else {
                    self.errorMsg = "No health values detected in this document. Make sure it contains lab results and try again."
                    self.showError = true
                }
            }
        }.resume()
    }

    // MARK: - Existing OCR (image) — unchanged

    func loadAndScanPhoto(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run { runOCR(on: image) }
        } catch {
            await MainActor.run {
                errorMsg = "Failed to load image: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    func runOCR(on image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        isScanning = true
        showScanResult = false
        callGeminiOCR(base64: imageData.base64EncodedString(), prompt: "")
    }

    func callGeminiOCR(base64: String, prompt: String) {
        guard let token = session.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/ocr-health-report") else {
            DispatchQueue.main.async { self.isScanning = false; self.errorMsg = "Unable to connect."; self.showError = true }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["image_base64": base64])

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isScanning = false
                if let error = error { self.errorMsg = "Scan failed: \(error.localizedDescription)"; self.showError = true; return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMsg = "Could not read scan results. Please enter values manually."; self.showError = true; return
                }
                let result = self.parseOCRResult(json: json)
                if result.hasAnyResult {
                    self.applyOCRResult(result); self.scanResult = result; self.showScanResult = true
                } else {
                    self.errorMsg = "No health values detected. Try a clearer image or enter values manually."; self.showError = true
                }
            }
        }.resume()
    }

    // MARK: - Parse / Apply / Prefill / Save — all unchanged

    func parseOCRResult(json: [String: Any]) -> OCRHealthResult {
        var result = OCRHealthResult()
        if let v = json["systolic_bp"] as? Int    { result.systolicBP = v }
        else if let v = json["systolic_bp"] as? Double { result.systolicBP = Int(v) }
        if let v = json["diastolic_bp"] as? Int    { result.diastolicBP = v }
        else if let v = json["diastolic_bp"] as? Double { result.diastolicBP = Int(v) }
        if let v = json["blood_sugar"] as? Double  { result.bloodSugar = v }
        else if let v = json["blood_sugar"] as? Int { result.bloodSugar = Double(v) }
        if let v = json["cholesterol"] as? Double  { result.cholesterol = v }
        else if let v = json["cholesterol"] as? Int { result.cholesterol = Double(v) }
        if let v = json["triglycerides"] as? Double { result.triglycerides = v }
        else if let v = json["triglycerides"] as? Int { result.triglycerides = Double(v) }
        if let v = json["height_cm"] as? Double { result.heightCm = v }
        else if let v = json["height_cm"] as? Int { result.heightCm = Double(v) }
        if let v = json["weight_kg"] as? Double { result.weightKg = v }
        else if let v = json["weight_kg"] as? Int { result.weightKg = Double(v) }
        return result
    }

    func applyOCRResult(_ result: OCRHealthResult) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let h = result.heightCm, h >= 100 && h <= 220 { heightCm = h }
            if let w = result.weightKg, w >= 30 && w <= 250 { weightKg = w }
            if let s = result.systolicBP, let d = result.diastolicBP,
               s >= 80 && s <= 200 && d >= 40 && d <= 130 {
                hasBP = true; systolicBP = Double(s); diastolicBP = Double(d)
            }
            if let bs = result.bloodSugar, bs >= 2.0 && bs <= 15.0 { hasBloodSugar = true; bloodSugar = bs }
            if let ch = result.cholesterol, ch >= 1.0 && ch <= 10.0 { hasCholesterol = true; cholesterol = ch }
            if let tr = result.triglycerides, tr >= 0.2 && tr <= 8.0 { hasTriglycerides = true; triglycerides = tr }
        }
    }

    func applyPrefill() {
        guard let p = prefill else { return }
        heightCm = p.heightCm; weightKg = p.weightKg; age = p.age; sex = p.sex
        if let s = p.systolicBP, let d = p.diastolicBP { hasBP = true; systolicBP = Double(s); diastolicBP = Double(d) }
        if let bs = p.fastingBloodSugar { hasBloodSugar = true; bloodSugar = bs }
        if let ch = p.totalCholesterol  { hasCholesterol = true; cholesterol = ch }
        if let tr = p.triglycerides     { hasTriglycerides = true; triglycerides = tr }
        selectedDietary  = Set(p.dietaryPreferences)
        selectedAllergens = Set(p.allergens)
    }

    func saveProfile() {
        guard hasChanges, !sex.isEmpty else { return }
        isSaving = true
        let profile = HealthProfile(
            userId: currentUserId,
            heightCm: heightCm, weightKg: weightKg, age: age, sex: sex,
            systolicBP: hasBP ? Int(systolicBP) : nil,
            diastolicBP: hasBP ? Int(diastolicBP) : nil,
            fastingBloodSugar: hasBloodSugar ? bloodSugar : nil,
            totalCholesterol: hasCholesterol ? cholesterol : nil,
            triglycerides: hasTriglycerides ? triglycerides : nil,
            dietaryPreferences: Array(selectedDietary),
            allergens: Array(selectedAllergens)
        )
        HealthAPIManager.shared.saveHealthProfile(profile) { success, err in
            self.isSaving = false
            if success {
                UserDefaults.standard.set(true, forKey: "health_profile_complete")
                NotificationCenter.default.post(name: Notification.Name("HealthProfileSaved"), object: nil)
                self.onComplete?(profile)
                self.dismiss()
            } else {
                self.errorMsg = err ?? "Failed to save. Please try again."
                self.showError = true
            }
        }
    }

    // MARK: - UI sub-components (all unchanged from original)

    func ocrResultBadge(result: OCRHealthResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(.green)
                Text("Scan complete — values auto-filled below")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                Spacer()
                Button(action: { showScanResult = false }) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            let items = buildDetectedItems(result: result)
            if !items.isEmpty {
                FlowLayout(items: items) { item in
                    Text(item).font(.system(size: 11, weight: .medium)).foregroundColor(.green)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.08)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.2), lineWidth: 1))
                }
            }
            Text("Adjust the sliders if any values look incorrect.")
                .font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
        }
        .padding(12).background(Color.green.opacity(0.04)).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.15), lineWidth: 1))
    }

    func buildDetectedItems(result: OCRHealthResult) -> [String] {
        var items: [String] = []
        if let s = result.systolicBP, let d = result.diastolicBP { items.append("BP: \(s)/\(d) mmHg") }
        if let bs = result.bloodSugar  { items.append("Glucose: \(String(format: "%.1f", bs)) mmol/L") }
        if let ch = result.cholesterol { items.append("Cholesterol: \(String(format: "%.1f", ch)) mmol/L") }
        if let tr = result.triglycerides { items.append("Triglycerides: \(String(format: "%.1f", tr)) mmol/L") }
        if let h = result.heightCm    { items.append("Height: \(Int(h)) cm") }
        if let w = result.weightKg    { items.append("Weight: \(String(format: "%.1f", w)) kg") }
        return items
    }

    var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20).fill(themeManager.current.cardBackground)
                .frame(width: 240, height: 180)
                .overlay(
                    VStack(spacing: 16) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .blue)).scaleEffect(1.4)
                        VStack(spacing: 6) {
                            Text("Scanning…").font(.system(size: 16, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                            Text("Detecting health values").font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                        }
                    }
                )
        }
    }

    var bmiPreview: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(themeManager.current.inputBackground).frame(width: 80, height: 80)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", bmi))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("BMI").font(.system(size: 10, weight: .semibold)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            Text(bmiLabel.0).font(.system(size: 12, weight: .bold)).foregroundColor(bmiLabel.1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(bmiLabel.1.opacity(0.1)).cornerRadius(10)
        }
    }

    var sexPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biological Sex").font(.system(size: 13, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
            HStack(spacing: 10) {
                ForEach(["Male", "Female", "Other"], id: \.self) { opt in
                    Button(action: { sex = opt.lowercased() }) {
                        Text(opt)
                            .font(.system(size: 13, weight: sex == opt.lowercased() ? .bold : .regular))
                            .foregroundColor(sex == opt.lowercased()
                                ? (themeManager.current == .dark ? .black : .white)
                                : themeManager.current.primaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(sex == opt.lowercased()
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : themeManager.current.inputBackground))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeManager.current.cardBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    var dietaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(DietaryOption.all) { option in
                let isSelected = selectedDietary.contains(option.id)
                Button(action: {
                    if option.id == "no_restriction" {
                        selectedDietary = isSelected ? [] : ["no_restriction"]
                    } else {
                        selectedDietary.remove("no_restriction")
                        if isSelected { selectedDietary.remove(option.id) } else { selectedDietary.insert(option.id) }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon).font(.system(size: 12))
                            .foregroundColor(isSelected ? (themeManager.current == .dark ? .black : .white) : .green).frame(width: 18)
                        Text(option.displayName).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? (themeManager.current == .dark ? .black : .white) : themeManager.current.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? (themeManager.current == .dark ? Color.white : Color.black) : themeManager.current.inputBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var allergenGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(AllergenOption.all) { allergen in
                let isSelected = selectedAllergens.contains(allergen.id)
                Button(action: {
                    if isSelected { selectedAllergens.remove(allergen.id) } else { selectedAllergens.insert(allergen.id) }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "xmark.circle.fill" : "circle").font(.system(size: 13))
                            .foregroundColor(isSelected ? .red : themeManager.current.secondaryText)
                        Text(allergen.displayName).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(themeManager.current.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.red.opacity(0.06) : themeManager.current.inputBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.red.opacity(0.3) : themeManager.current.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var saveButton: some View {
        VStack(spacing: 8) {
            Button(action: saveProfile) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(
                            tint: themeManager.current == .dark ? .black : .white)).scaleEffect(0.85)
                    } else if !hasChanges {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    }
                    Text(isSaving ? "Saving…" : hasChanges ? "Save Changes" : "No Changes")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(hasChanges
                    ? (themeManager.current == .dark ? .black : .white)
                    : themeManager.current.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(hasChanges
                    ? (themeManager.current == .dark ? Color.white : Color.black)
                    : themeManager.current.inputBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(hasChanges ? Color.clear : themeManager.current.cardBorder, lineWidth: 1))
            }
            .disabled(isSaving || sex.isEmpty || !hasChanges)
            if !hasChanges {
                Text("Make changes to enable saving").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }

    func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            }
            content()
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func inlineSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                      step: Double, display: String, warningRange: ClosedRange<Double>? = nil) -> some View {
        let isWarning = warningRange.map { value.wrappedValue >= $0.lowerBound && value.wrappedValue <= $0.upperBound } ?? false
        let isDanger  = warningRange.map { value.wrappedValue > $0.upperBound } ?? false
        let accent: Color = isDanger ? .red : isWarning ? .orange : (themeManager.current == .dark ? .white : .black)
        return VStack(spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text(display).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(accent)
            }
            Slider(value: value, in: range, step: step).accentColor(accent)
        }
    }

    func clinicalRow<Content: View>(title: String, subtitle: String, isOn: Binding<Bool>,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                    Text(subtitle).font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle(tint: themeManager.current == .dark ? .white : .black))
                    .labelsHidden()
            }
            if isOn.wrappedValue { content().padding(.top, 4) }
        }
        .padding(12).background(themeManager.current.inputBackground).cornerRadius(12)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn.wrappedValue)
    }
}

// MARK: - CameraPickerForOCR (unchanged)

struct CameraPickerForOCR: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.delegate = context.coordinator; picker.allowsEditing = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

// MARK: - FlowLayout (unchanged)

private struct _FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]; let content: (Item) -> Content
    @State private var totalHeight: CGFloat = .zero
    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) { self.items = items; self.content = content }
    var body: some View { GeometryReader { geo in generateContent(in: geo) }.frame(height: totalHeight) }
    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero; var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item).padding(.trailing, 8).padding(.bottom, 8)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width { width = 0; height -= d.height }
                        let result = width
                        if item == items.last { width = 0 } else { width -= d.width }
                        return result
                    }
                    .alignmentGuide(.top) { _ in let result = height; if item == items.last { height = 0 }; return result }
            }
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: _HeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(_HeightKey.self) { totalHeight = $0 }
    }
}
private struct _HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
