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

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers  // ← NEW

// ── OCRHealthResult and all other structs are unchanged ───────────────────────

struct OCRHealthResult {
  var systolicBP: Int?
  var diastolicBP: Int?
  var bloodSugar: Double?
  var cholesterol: Double?
  var triglycerides: Double?
  var heightCm: Double?
  var weightKg: Double?
  var hba1c: Double?
  var ldl: Double?
  var hdl: Double?

  var hasAnyResult: Bool {
    systolicBP != nil || diastolicBP != nil || bloodSugar != nil || cholesterol != nil
      || triglycerides != nil || heightCm != nil || weightKg != nil || hba1c != nil || ldl != nil
      || hdl != nil
  }
}

// MARK: - OCR raw/processed field (for the confirmation sheet)

/// One detected metric from the OCR `fields` double-layer: the raw reading the
/// model saw, plus the normalized (processed) value the user can confirm/edit.
struct OCRField: Identifiable {
  let id: String  // backend key, e.g. "cholesterol"
  let label: String  // display name, e.g. "Total Cholesterol"
  let rawName: String?  // raw label on the report, e.g. "TC"
  let rawValue: String?  // raw value text, e.g. "200"
  let rawUnit: String?  // raw unit, e.g. "mg/dL"
  let processedUnit: String  // normalized unit, e.g. "mmol/L"
  var editedValue: String  // user-editable processed value
  var accepted: Bool  // whether to apply this field

  /// Display order + human labels for the 11 MVP fields.
  static let order: [(key: String, label: String)] = [
    ("systolic_bp", "Systolic BP"),
    ("diastolic_bp", "Diastolic BP"),
    ("height_cm", "Height"),
    ("weight_kg", "Weight"),
    ("bmi", "BMI"),
    ("blood_sugar", "Blood Sugar"),
    ("hba1c", "HbA1c"),
    ("cholesterol", "Total Cholesterol"),
    ("ldl", "LDL Cholesterol"),
    ("hdl", "HDL Cholesterol"),
    ("triglycerides", "Triglycerides"),
  ]
}

/// Parse the backend `fields` double-layer into ordered, editable rows.
func parseOCRFields(json: [String: Any]) -> [OCRField] {
  guard let fields = json["fields"] as? [String: Any] else {
    return []
  }

  // JSONSerialization commonly represents JSON numbers as NSNumber.
  func readNumber(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }

    if let text = value as? String {
      let normalized = text.replacingOccurrences(of: ",", with: ".")
      return Double(normalized)
    }

    return nil
  }

  // Raw OCR values may be strings, numbers, or null.
  func readText(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else {
      return nil
    }
    if let text = value as? String {
      if let number = Double(text) {
        return String(format: "%.2f", number)
      }

      return text
    }

    if let number = value as? NSNumber {
      return String(
        format: "%.2f",
        number.doubleValue
      )
    }

    return String(describing: value)
  }

  return OCRField.order.compactMap { entry in
    guard
      let field = fields[entry.key] as? [String: Any],
      let processed = field["processed"] as? [String: Any],
      let processedValue = readNumber(processed["value"])
    else {
      // Missing or invalid fields do not need a confirmation row.
      return nil
    }

    let raw = field["raw"] as? [String: Any]

    let editedValue: String

    if processedValue.rounded() == processedValue {
      editedValue = String(Int(processedValue))
    } else {
      editedValue = String(format: "%.2f", processedValue)
    }

    return OCRField(
      id: entry.key,
      label: entry.label,
      rawName: readText(raw?["name"]),
      rawValue: readText(raw?["value"]),
      rawUnit: readText(raw?["unit"]),
      processedUnit: readText(processed["unit"]) ?? "",
      editedValue: editedValue,
      accepted: true
    )
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
  @State private var hasHbA1c = false
  @State private var hba1c: Double = 5.5
  @State private var hasLDL = false
  @State private var ldl: Double = 2.5
  @State private var hasHDL = false
  @State private var hdl: Double = 1.3

  @State private var selectedDietary: Set<String> = []
  @State private var selectedAllergens: Set<String> = []

  @State private var isSaving = false
  @State private var errorMsg = ""
  @State private var showError = false

  // ── OCR state ──────────────────────────────────────────────────────────────
  @State private var showImagePicker = false
  @State private var showCamera = false
  @State private var showScanOptions = false  // confirmationDialog
  @State private var showFilePicker = false  // ← NEW: file importer
  @State private var isScanning = false
  @State private var scanResult: OCRHealthResult? = nil
  @State private var showScanResult = false

  // ── OCR confirmation (raw → processed review) ───────────────────────────────
  @State private var showOCRConfirm = false
  @State private var pendingFields: [OCRField] = []
  @State private var pendingAdditionalFields: [HealthOCRAdditionalField] = []
  @State private var confirmedAdditionalFields: [HealthOCRAdditionalField] = []
  @State private var isAdditionalResultsExpanded = false
  @State private var ocrStatus = ""
  @State private var ocrMessage: String? = nil
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

  var bmi: Double {
    let h = heightCm / 100
    return weightKg / (h * h)
  }

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
    if hasHbA1c != (original.hba1c != nil) { return true }
    if hasHbA1c, let oa = original.hba1c, abs(hba1c - oa) > 0.05 { return true }
    if hasLDL != (original.ldl != nil) { return true }
    if hasLDL, let ol = original.ldl, abs(ldl - ol) > 0.05 { return true }
    if hasHDL != (original.hdl != nil) { return true }
    if hasHDL, let oh = original.hdl, abs(hdl - oh) > 0.05 { return true }
    if selectedDietary != Set(original.dietaryPreferences) { return true }
    if selectedAllergens != Set(original.allergens) { return true }

    let currentAdditionalFieldSignatures =
      confirmedAdditionalFields.map {
        "\($0.name)|" + "\($0.value?.displayText ?? "")|" + "\($0.unit ?? "")"
      }

    let originalAdditionalFieldSignatures =
      (original.additionalFields ?? []).map {
        "\($0.name)|" + "\($0.value?.displayText ?? "")|" + "\($0.unit ?? "")"
      }

    if currentAdditionalFieldSignatures != originalAdditionalFieldSignatures {

      return true
    }
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
                inlineSlider(
                  label: "Height", value: $heightCm, range: 100...220, step: 1,
                  display: "\(Int(heightCm)) cm")
                inlineSlider(
                  label: "Weight", value: $weightKg, range: 30...250, step: 0.5,
                  display: String(format: "%.1f kg", weightKg))
                inlineSlider(
                  label: "Age",
                  value: Binding(
                    get: { Double(age) }, set: { age = Int($0) }),
                  range: 12...100, step: 1, display: "\(age) yrs")
                sexPicker
              }
            }

            // sectionCard(title: "Clinical Markers", icon: "heart.fill") {
            //     VStack(spacing: 12) {
            //         if showScanResult, let result = scanResult, result.hasAnyResult {
            //             ocrResultBadge(result: result)
            //         }
            //         Text("Optional — fill in if you have these values")
            //             .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            //             .frame(maxWidth: .infinity, alignment: .leading)
            //         clinicalRow(title: "Blood Pressure", subtitle: "Normal: 90–120 / 60–80 mmHg", isOn: $hasBP) {
            //             VStack(spacing: 10) {
            //                 inlineSlider(label: "Systolic", value: $systolicBP, range: 80...200, step: 1,
            //                              display: "\(Int(systolicBP)) mmHg", warningRange: 120...139)
            //                 inlineSlider(label: "Diastolic", value: $diastolicBP, range: 40...130, step: 1,
            //                              display: "\(Int(diastolicBP)) mmHg", warningRange: 80...89)
            //             }
            //         }
            //         clinicalRow(title: "Fasting Blood Sugar", subtitle: "Normal: 3.9–5.5 mmol/L", isOn: $hasBloodSugar) {
            //             inlineSlider(label: "Blood Sugar", value: $bloodSugar, range: 2.0...15.0, step: 0.1,
            //                          display: String(format: "%.1f mmol/L", bloodSugar), warningRange: 5.6...6.9)
            //         }
            //         clinicalRow(title: "Total Cholesterol", subtitle: "Normal: < 5.2 mmol/L", isOn: $hasCholesterol) {
            //             inlineSlider(label: "Cholesterol", value: $cholesterol, range: 1.0...10.0, step: 0.1,
            //                          display: String(format: "%.1f mmol/L", cholesterol), warningRange: 5.2...6.2)
            //         }
            //         clinicalRow(title: "Triglycerides", subtitle: "Normal: < 1.7 mmol/L", isOn: $hasTriglycerides) {
            //             inlineSlider(label: "Triglycerides", value: $triglycerides, range: 0.2...8.0, step: 0.1,
            //                          display: String(format: "%.1f mmol/L", triglycerides), warningRange: 1.7...2.3)
            //         }
            //         clinicalRow(title: "HbA1c", subtitle: "Normal: < 5.7 %", isOn: $hasHbA1c) {
            //             inlineSlider(label: "HbA1c", value: $hba1c, range: 3.0...18.0, step: 0.1,
            //                          display: String(format: "%.1f %%", hba1c), warningRange: 5.7...6.4)
            //         }
            //         clinicalRow(title: "LDL Cholesterol", subtitle: "Normal: < 3.4 mmol/L", isOn: $hasLDL) {
            //             inlineSlider(label: "LDL", value: $ldl, range: 0.3...10.0, step: 0.1,
            //                          display: String(format: "%.1f mmol/L", ldl), warningRange: 3.4...4.1)
            //         }
            //         clinicalRow(title: "HDL Cholesterol", subtitle: "Normal: > 1.0 mmol/L", isOn: $hasHDL) {
            //             inlineSlider(label: "HDL", value: $hdl, range: 0.3...5.0, step: 0.1,
            //                          display: String(format: "%.1f mmol/L", hdl))
            //         }
            //     }
            // }
            clinicalMarkersSection

            if !confirmedAdditionalFields.isEmpty {
              extendedHealthResultsSection
            }

            sectionCard(title: "Dietary Preferences", icon: "leaf.fill") { dietaryGrid }
            sectionCard(title: "Allergens to Avoid", icon: "exclamationmark.triangle.fill") {
              allergenGrid
            }
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
      } message: {
        Text(errorMsg)
      }

      // ── Photo library picker ─────────────────────────────────────────
      .photosPicker(
        isPresented: $showImagePicker,
        selection: $selectedPhotoItem,
        matching: .images
      )
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
          UTType(filenameExtension: "docx") ?? UTType.data,
        ],
        allowsMultipleSelection: false
      ) { result in
        handleFilePickerResult(result)
      }

      // ── Scan source chooser ──────────────────────────────────────────
      .confirmationDialog(
        "Scan Medical Report", isPresented: $showScanOptions, titleVisibility: .visible
      ) {
        Button("Take Photo") { showCamera = true }
        Button("Choose Photo") { showImagePicker = true }
        Button("Import PDF or Word") { showFilePicker = true }  // ← NEW
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Upload a photo, image, PDF, or Word document containing your lab or health report.")
      }

      // ── OCR raw → processed confirmation ─────────────────────────────
      .sheet(isPresented: $showOCRConfirm) {
        OCRConfirmView(
          fields: pendingFields,
          additionalFields: pendingAdditionalFields,
          status: ocrStatus,
          message: ocrMessage
        ) { confirmed, confirmedAdditional in

          // Apply the predefined health fields.
          applyConfirmedFields(confirmed)

          // Keep the extended fields for the Health Profile UI.
          confirmedAdditionalFields =
            confirmedAdditional
        }
        .environmentObject(themeManager)
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
        let hasAccess = url.startAccessingSecurityScopedResource()

        defer {
          if hasAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }

        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
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
      let url = AppConfig.url(path: "/ocr-document")
      // let url = URL(
      //   string: "http://127.0.0.1:5001/ocr-document"
      // )

    else {
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
    request.timeoutInterval = 120

    let body: [String: Any] = ["file_base64": base64, "file_type": fileType]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) {
      data,
      response,
      error in

      DispatchQueue.main.async {
        self.isScanning = false

        if let error {
          self.errorMsg =
            "Scan failed: \(error.localizedDescription)"
          self.showError = true
          return
        }

        guard
          let httpResponse =
            response as? HTTPURLResponse
        else {
          self.errorMsg =
            "Invalid response from OCR server."
          self.showError = true
          return
        }

        guard let data else {
          self.errorMsg =
            "No OCR result was returned."
          self.showError = true
          return
        }

        guard
          (200...299).contains(
            httpResponse.statusCode
          )
        else {
          let serverMessage: String

          if let json =
            try? JSONSerialization.jsonObject(
              with: data
            ) as? [String: Any],
            let message =
              json["error"] as? String
              ?? json["message"] as? String
          {
            serverMessage = message
          } else {
            serverMessage =
              "OCR failed with status "
              + "\(httpResponse.statusCode)."
          }

          self.errorMsg = serverMessage
          self.showError = true
          return
        }

        do {
          let ocrResponse =
            try JSONDecoder().decode(
              HealthOCRResponse.self,
              from: data
            )

          // Uses the same response handling as photo OCR.
          self.handleOCRResponse(
            ocrResponse
          )

        } catch {
          self.errorMsg =
            "Could not decode document OCR result: "
            + error.localizedDescription

          self.showError = true
        }
      }
    }.resume()
  }

  // MARK: - Existing OCR (image) — unchanged

  func loadAndScanPhoto(item: PhotosPickerItem?) async {
    guard
      let item,
      let data = try? await item.loadTransferable(type: Data.self),
      let image = UIImage(data: data)
    else {
      return
    }

    await MainActor.run {
      runOCR(on: image)
    }
  }

  // func runOCR(on image: UIImage) {
  //   guard let imageData = image.jpegData(compressionQuality: 0.9) else {
  //     errorMsg = "Could not prepare the selected image."
  //     showError = true
  //     return
  //   }
  //   //clear any OCR results from a previous scan.
  //   pendingFields = []
  //   pendingAdditionalFields = []

  //   submitHealthReport(
  //     data: imageData,
  //     filename: "health-report.jpg",
  //     mimeType: "image/jpeg"
  //   )
  // }
  func runOCR(on image: UIImage) {
    let maxDimension: CGFloat = 2048
    let largestDimension = max(image.size.width, image.size.height)
    let scale = min(1, maxDimension / largestDimension)

    let targetSize = CGSize(
      width: image.size.width * scale,
      height: image.size.height * scale
    )

    guard
      let resizedImage = image.preparingThumbnail(of: targetSize),
      let imageData = resizedImage.jpegData(compressionQuality: 0.75)
    else {
      errorMsg = "Could not prepare the selected image."
      showError = true
      return
    }

    pendingFields = []
    pendingAdditionalFields = []

    submitHealthReport(
      data: imageData,
      filename: "health-report.jpg",
      mimeType: "image/jpeg"
    )
  }

  private func submitHealthReport(
    data: Data,
    filename: String,
    mimeType: String
  ) {
    isScanning = true
    showScanResult = false

    NetworkManager.shared.scanHealthReport(
      imageData: data,
      filename: filename,
      mimeType: mimeType
    ) { result in
      DispatchQueue.main.async {
        self.isScanning = false

        switch result {
        case .success(let response):
          self.handleOCRResponse(response)

        case .failure(let error):
          self.errorMsg =
            "Scan failed: \(error.localizedDescription)"
          self.showError = true
        }
      }
    }
  }

  //handles the OCR result returned by the backend
  private func handleOCRResponse(
    _ response: HealthOCRResponse
  ) {
    switch response.status {

    case .ok:
      do {
        // Store the extended fields for Confirm Scan.
        pendingAdditionalFields =
          response.additionalFields

        print(
          "✅ Extended OCR fields:",
          response.additionalFields.count
        )

        for field in response.additionalFields {
          print(
            "✅ Extended:",
            field.name,
            field.value?.displayText ?? "nil",
            field.unit ?? ""
          )
        }

        let encodedData =
          try JSONEncoder().encode(response)

        guard
          let json =
            try JSONSerialization.jsonObject(
              with: encodedData
            ) as? [String: Any]
        else {
          throw NSError(
            domain: "HealthOCR",
            code: -1,
            userInfo: [
              NSLocalizedDescriptionKey:
                "The OCR response had an invalid format."
            ]
          )
        }

        presentOCRConfirmation(json: json)

      } catch {
        pendingFields = []
        pendingAdditionalFields = []

        errorMsg =
          "Could not read the scan result: " + error.localizedDescription

        showError = true
      }

    case .noFields:
      pendingFields = []
      pendingAdditionalFields = []

      errorMsg =
        response.message ?? "No supported health values were found in this report."

      showError = true

    case .noText:
      pendingFields = []
      pendingAdditionalFields = []

      errorMsg =
        response.message ?? "No readable text was found. Try a clearer image."

      showError = true
    }
  }

  func presentOCRConfirmation(
    json: [String: Any]
  ) {
    let canonicalFields =
      parseOCRFields(json: json)

    guard
      !canonicalFields.isEmpty
        || !pendingAdditionalFields.isEmpty
    else {
      errorMsg =
        "No supported health values were found."

      showError = true
      return
    }

    pendingFields = canonicalFields
    // ocrStatus = json["status"] as? String
    ocrStatus = (json["status"] as? String) ?? "ok"
    ocrMessage = json["message"] as? String
    showOCRConfirm = true
  }

  func parseOCRResult(json: [String: Any]) -> OCRHealthResult {
    var result = OCRHealthResult()
    if let v = json["systolic_bp"] as? Int {
      result.systolicBP = v
    } else if let v = json["systolic_bp"] as? Double {
      result.systolicBP = Int(v)
    }
    if let v = json["diastolic_bp"] as? Int {
      result.diastolicBP = v
    } else if let v = json["diastolic_bp"] as? Double {
      result.diastolicBP = Int(v)
    }
    if let v = json["blood_sugar"] as? Double {
      result.bloodSugar = v
    } else if let v = json["blood_sugar"] as? Int {
      result.bloodSugar = Double(v)
    }
    if let v = json["cholesterol"] as? Double {
      result.cholesterol = v
    } else if let v = json["cholesterol"] as? Int {
      result.cholesterol = Double(v)
    }
    if let v = json["triglycerides"] as? Double {
      result.triglycerides = v
    } else if let v = json["triglycerides"] as? Int {
      result.triglycerides = Double(v)
    }
    if let v = json["height_cm"] as? Double {
      result.heightCm = v
    } else if let v = json["height_cm"] as? Int {
      result.heightCm = Double(v)
    }
    if let v = json["weight_kg"] as? Double {
      result.weightKg = v
    } else if let v = json["weight_kg"] as? Int {
      result.weightKg = Double(v)
    }
    if let v = json["hba1c"] as? Double {
      result.hba1c = v
    } else if let v = json["hba1c"] as? Int {
      result.hba1c = Double(v)
    }
    if let v = json["ldl"] as? Double {
      result.ldl = v
    } else if let v = json["ldl"] as? Int {
      result.ldl = Double(v)
    }
    if let v = json["hdl"] as? Double {
      result.hdl = v
    } else if let v = json["hdl"] as? Int {
      result.hdl = Double(v)
    }
    return result
  }

  func applyOCRResult(_ result: OCRHealthResult) {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
      if let h = result.heightCm, h >= 100 && h <= 220 { heightCm = h }
      if let w = result.weightKg, w >= 30 && w <= 250 { weightKg = w }
      if let s = result.systolicBP, let d = result.diastolicBP,
        s >= 80 && s <= 200 && d >= 40 && d <= 130
      {
        hasBP = true
        systolicBP = Double(s)
        diastolicBP = Double(d)
      }
      if let bs = result.bloodSugar, bs >= 2.0 && bs <= 15.0 {
        hasBloodSugar = true
        bloodSugar = bs
      }
      if let ch = result.cholesterol, ch >= 1.0 && ch <= 10.0 {
        hasCholesterol = true
        cholesterol = ch
      }
      if let tr = result.triglycerides, tr >= 0.2 && tr <= 8.0 {
        hasTriglycerides = true
        triglycerides = tr
      }
      if let a = result.hba1c, a >= 3.0 && a <= 18.0 {
        hasHbA1c = true
        hba1c = a
      }
      if let l = result.ldl, l >= 0.3 && l <= 10.0 {
        hasLDL = true
        ldl = l
      }
      if let hd = result.hdl, hd >= 0.3 && hd <= 5.0 {
        hasHDL = true
        hdl = hd
      }
    }
  }

  /// Build an OCRHealthResult from the user-confirmed fields, then apply it.
  func applyConfirmedFields(_ fields: [OCRField]) {
    // Confirm Scan passes every detected field so rejected rows can clear
    // values that may already be enabled from a previous scan or profile.
    // let rejectedFieldIDs = Set(
    //   fields.lazy
    //     .filter { !$0.accepted }
    //     .map(\.id)
    // )

    // withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
    //   if rejectedFieldIDs.contains("systolic_bp")
    //     || rejectedFieldIDs.contains("diastolic_bp")
    //   {
    //     hasBP = false
    //   }
    //   if rejectedFieldIDs.contains("blood_sugar") {
    //     hasBloodSugar = false
    //   }
    //   if rejectedFieldIDs.contains("cholesterol") {
    //     hasCholesterol = false
    //   }
    //   if rejectedFieldIDs.contains("triglycerides") {
    //     hasTriglycerides = false
    //   }
    //   if rejectedFieldIDs.contains("hba1c") {
    //     hasHbA1c = false
    //   }
    //   if rejectedFieldIDs.contains("ldl") {
    //     hasLDL = false
    //   }
    //   if rejectedFieldIDs.contains("hdl") {
    //     hasHDL = false
    //   }
    // }

    // The newest confirmed scan replaces clinical results from previous scans.
    // Any value missing or disabled in this scan remains switched off.
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
      hasBP = false
      hasBloodSugar = false
      hasCholesterol = false
      hasTriglycerides = false
      hasHbA1c = false
      hasLDL = false
      hasHDL = false
    }

    var r = OCRHealthResult()
    for f in fields where f.accepted {
      guard let v = Double(f.editedValue.trimmingCharacters(in: .whitespaces)) else { continue }
      switch f.id {
      case "systolic_bp": r.systolicBP = Int(v)
      case "diastolic_bp": r.diastolicBP = Int(v)
      case "blood_sugar": r.bloodSugar = v
      case "hba1c": r.hba1c = v
      case "cholesterol": r.cholesterol = v
      case "ldl": r.ldl = v
      case "hdl": r.hdl = v
      case "triglycerides": r.triglycerides = v
      case "height_cm": r.heightCm = v
      case "weight_kg": r.weightKg = v
      default: break  // bmi is derived from height/weight, not stored directly
      }
    }
    applyOCRResult(r)
    scanResult = r
    showScanResult = r.hasAnyResult
  }

  func applyPrefill() {
    guard let p = prefill else { return }
    heightCm = p.heightCm
    weightKg = p.weightKg
    age = p.age
    sex = p.sex
    if let s = p.systolicBP, let d = p.diastolicBP {
      hasBP = true
      systolicBP = Double(s)
      diastolicBP = Double(d)
    }
    if let bs = p.fastingBloodSugar {
      hasBloodSugar = true
      bloodSugar = bs
    }
    if let ch = p.totalCholesterol {
      hasCholesterol = true
      cholesterol = ch
    }
    if let tr = p.triglycerides {
      hasTriglycerides = true
      triglycerides = tr
    }
    if let a = p.hba1c {
      hasHbA1c = true
      hba1c = a
    }
    if let l = p.ldl {
      hasLDL = true
      ldl = l
    }
    if let hd = p.hdl {
      hasHDL = true
      hdl = hd
    }
    selectedDietary = Set(p.dietaryPreferences)
    selectedAllergens = Set(p.allergens)
    confirmedAdditionalFields =
      p.additionalFields ?? []
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
      hba1c: hasHbA1c ? hba1c : nil,
      ldl: hasLDL ? ldl : nil,
      hdl: hasHDL ? hdl : nil,
      dietaryPreferences: Array(selectedDietary),
      allergens: Array(selectedAllergens),
      // Save extended fields with the profile.
      additionalFields: confirmedAdditionalFields
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
          Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(
            themeManager.current.secondaryText)
        }
      }
      let items = buildDetectedItems(result: result)
      if !items.isEmpty {
        FlowLayout(items: items) { item in
          Text(item).font(.system(size: 11, weight: .medium)).foregroundColor(.green)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.green.opacity(0.08)).cornerRadius(8)
            .overlay(
              RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.2), lineWidth: 1))
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
    if let bs = result.bloodSugar { items.append("Glucose: \(String(format: "%.1f", bs)) mmol/L") }
    if let ch = result.cholesterol {
      items.append("Cholesterol: \(String(format: "%.1f", ch)) mmol/L")
    }
    if let l = result.ldl { items.append("LDL: \(String(format: "%.1f", l)) mmol/L") }
    if let hd = result.hdl { items.append("HDL: \(String(format: "%.1f", hd)) mmol/L") }
    if let tr = result.triglycerides {
      items.append("Triglycerides: \(String(format: "%.1f", tr)) mmol/L")
    }
    if let a = result.hba1c { items.append("HbA1c: \(String(format: "%.1f", a)) %") }
    if let h = result.heightCm { items.append("Height: \(Int(h)) cm") }
    if let w = result.weightKg { items.append("Weight: \(String(format: "%.1f", w)) kg") }
    return items
  }

  var scanningOverlay: some View {
    ZStack {
      Color.black.opacity(0.45).ignoresSafeArea()
      RoundedRectangle(cornerRadius: 20).fill(themeManager.current.cardBackground)
        .frame(width: 240, height: 180)
        .overlay(
          VStack(spacing: 16) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .blue)).scaleEffect(
              1.4)
            VStack(spacing: 6) {
              Text("Scanning…").font(.system(size: 16, weight: .bold)).foregroundColor(
                themeManager.current.primaryText)
              Text("Detecting health values").font(.system(size: 13)).foregroundColor(
                themeManager.current.secondaryText)
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
          Text("BMI").font(.system(size: 10, weight: .semibold)).foregroundColor(
            themeManager.current.secondaryText)
        }
      }
      Text(bmiLabel.0).font(.system(size: 12, weight: .bold)).foregroundColor(bmiLabel.1)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(bmiLabel.1.opacity(0.1)).cornerRadius(10)
    }
  }

  var sexPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Biological Sex").font(.system(size: 13, weight: .medium)).foregroundColor(
        themeManager.current.secondaryText)
      HStack(spacing: 10) {
        ForEach(["Male", "Female", "Other"], id: \.self) { opt in
          Button(action: { sex = opt.lowercased() }) {
            Text(opt)
              .font(.system(size: 13, weight: sex == opt.lowercased() ? .bold : .regular))
              .foregroundColor(
                sex == opt.lowercased()
                  ? (themeManager.current == .dark ? .black : .white)
                  : themeManager.current.primaryText
              )
              .frame(maxWidth: .infinity).padding(.vertical, 10)
              .background(
                RoundedRectangle(cornerRadius: 10)
                  .fill(
                    sex == opt.lowercased()
                      ? (themeManager.current == .dark ? Color.white : Color.black)
                      : themeManager.current.inputBackground)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(
                  themeManager.current.cardBorder, lineWidth: 1))
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
            if isSelected {
              selectedDietary.remove(option.id)
            } else {
              selectedDietary.insert(option.id)
            }
          }
        }) {
          HStack(spacing: 6) {
            Image(systemName: option.icon).font(.system(size: 12))
              .foregroundColor(
                isSelected ? (themeManager.current == .dark ? .black : .white) : .green
              ).frame(width: 18)
            Text(option.displayName).font(
              .system(size: 12, weight: isSelected ? .semibold : .regular)
            )
            .foregroundColor(
              isSelected
                ? (themeManager.current == .dark ? .black : .white)
                : themeManager.current.primaryText)
            Spacer()
          }
          .padding(.horizontal, 10).padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(
                isSelected
                  ? (themeManager.current == .dark ? Color.white : Color.black)
                  : themeManager.current.inputBackground)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(themeManager.current.cardBorder, lineWidth: 1)
          )
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
          if isSelected {
            selectedAllergens.remove(allergen.id)
          } else {
            selectedAllergens.insert(allergen.id)
          }
        }) {
          HStack(spacing: 6) {
            Image(systemName: isSelected ? "xmark.circle.fill" : "circle").font(.system(size: 13))
              .foregroundColor(isSelected ? .red : themeManager.current.secondaryText)
            Text(allergen.displayName).font(
              .system(size: 12, weight: isSelected ? .semibold : .regular)
            )
            .foregroundColor(themeManager.current.primaryText)
            Spacer()
          }
          .padding(.horizontal, 10).padding(.vertical, 9)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(isSelected ? Color.red.opacity(0.06) : themeManager.current.inputBackground)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(
                isSelected ? Color.red.opacity(0.3) : themeManager.current.cardBorder, lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - Redesigned Clinical Markers

  private var clinicalMarkersSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      if showScanResult,
        let result = scanResult,
        result.hasAnyResult
      {
        ocrResultBadge(result: result)
      }

      Text("Optional — Fill in if you have these values")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(themeManager.current.secondaryText)
        .padding(.horizontal, 4)

      healthMetricCard(
        title: "Blood Pressure",
        normalText: "Systolic 90–120 / Diastolic 60–80 mmHg",
        isOn: $hasBP
      ) {
        VStack(spacing: 16) {
          healthMetricSlider(
            label: "Systolic",
            value: $systolicBP,
            range: 80...200,
            step: 1,
            displayValue: "\(Int(systolicBP))",
            unit: "mmHg",
            warningRange: 120...139
          )

          Divider()
            .background(themeManager.current.cardBorder)

          healthMetricSlider(
            label: "Diastolic",
            value: $diastolicBP,
            range: 40...130,
            step: 1,
            displayValue: "\(Int(diastolicBP))",
            unit: "mmHg",
            warningRange: 80...89
          )
        }
      }

      healthMetricCard(
        title: "Fasting Blood Sugar",
        normalText: "3.9–5.5 mmol/L",
        isOn: $hasBloodSugar
      ) {
        healthMetricSlider(
          label: "Blood Sugar",
          value: $bloodSugar,
          range: 2.0...15.0,
          step: 0.1,
          displayValue: String(format: "%.1f", bloodSugar),
          unit: "mmol/L",
          warningRange: 5.6...6.9
        )
      }

      healthMetricCard(
        title: "Total Cholesterol",
        normalText: "< 5.2 mmol/L",
        isOn: $hasCholesterol
      ) {
        healthMetricSlider(
          label: "Cholesterol",
          value: $cholesterol,
          range: 1.0...10.0,
          step: 0.1,
          displayValue: String(format: "%.1f", cholesterol),
          unit: "mmol/L",
          warningRange: 5.2...6.2
        )
      }

      healthMetricCard(
        title: "Triglycerides",
        normalText: "< 1.7 mmol/L",
        isOn: $hasTriglycerides
      ) {
        healthMetricSlider(
          label: "Triglycerides",
          value: $triglycerides,
          range: 0.2...8.0,
          step: 0.1,
          displayValue: String(format: "%.1f", triglycerides),
          unit: "mmol/L",
          warningRange: 1.7...2.3
        )
      }

      healthMetricCard(
        title: "HbA1c",
        normalText: "< 5.7 %",
        isOn: $hasHbA1c
      ) {
        healthMetricSlider(
          label: "HbA1c",
          value: $hba1c,
          range: 3.0...18.0,
          step: 0.1,
          displayValue: String(format: "%.1f", hba1c),
          unit: "%",
          warningRange: 5.7...6.4
        )
      }

      healthMetricCard(
        title: "LDL Cholesterol",
        normalText: "< 3.4 mmol/L",
        isOn: $hasLDL
      ) {
        healthMetricSlider(
          label: "LDL",
          value: $ldl,
          range: 0.3...10.0,
          step: 0.1,
          displayValue: String(format: "%.1f", ldl),
          unit: "mmol/L",
          warningRange: 3.4...4.1
        )
      }

      healthMetricCard(
        title: "HDL Cholesterol",
        normalText: "> 1.0 mmol/L",
        isOn: $hasHDL
      ) {
        healthMetricSlider(
          label: "HDL",
          value: $hdl,
          range: 0.3...5.0,
          step: 0.1,
          displayValue: String(format: "%.1f", hdl),
          unit: "mmol/L"
        )
      }
    }
  }

  private func healthMetricCard<Content: View>(
    title: String,
    normalText: String,
    isOn: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 14) {

        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 7) {
            Text(title)
              .font(.system(size: 16, weight: .bold))
              .foregroundColor(themeManager.current.primaryText)

          }

          (Text("Normal: ")
            .foregroundColor(.green)
            + Text(normalText)
            .foregroundColor(themeManager.current.secondaryText))
            .font(.system(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        Toggle("", isOn: isOn)
          .toggleStyle(SwitchToggleStyle(tint: .green))
          .labelsHidden()
      }

      if isOn.wrappedValue {
        content()
          .padding(.top, 2)
          .transition(
            .opacity.combined(
              with: .scale(scale: 0.98, anchor: .top)
            )
          )
      }
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20)
        .fill(themeManager.current.cardBackground)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          isOn.wrappedValue
            ? Color.green.opacity(0.10)
            : themeManager.current.cardBorder.opacity(0.70),
          lineWidth: 1
        )
    }
    .shadow(
      color: Color.black.opacity(
        themeManager.current == .dark ? 0.20 : 0.055
      ),
      radius: 12,
      x: 0,
      y: 5
    )
    .animation(
      .spring(response: 0.34, dampingFraction: 0.84),
      value: isOn.wrappedValue
    )
  }

  private func healthMetricSlider(
    label: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    displayValue: String,
    unit: String,
    warningRange: ClosedRange<Double>? = nil
  ) -> some View {
    let isWarning =
      warningRange.map {
        value.wrappedValue >= $0.lowerBound && value.wrappedValue <= $0.upperBound
      } ?? false

    let isDanger =
      warningRange.map {
        value.wrappedValue > $0.upperBound
      } ?? false

    let statusColor: Color =
      isDanger ? .red : isWarning ? .orange : themeManager.current.primaryText

    let sliderColor: Color =
      isDanger ? .red : isWarning ? .orange : .green

    return VStack(spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(label)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(themeManager.current.secondaryText)

        Spacer()

        Text(displayValue)
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundColor(statusColor)

        Text(unit)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(themeManager.current.secondaryText)
      }

      Slider(
        value: value,
        in: range,
        step: step
      )
      .accentColor(sliderColor)
    }
  }

  // MARK: - Extended Health Results

  // MARK: - Additional Test Results Tab

  private var extendedHealthResultsSection: some View {

    VStack(spacing: 0) {

      // Collapsible tab header
      Button {
        withAnimation(
          .easeInOut(duration: 0.22)
        ) {
          isAdditionalResultsExpanded.toggle()
        }
      } label: {
        HStack(spacing: 14) {
          Image(
            systemName:
              "list.bullet.rectangle"
          )
          .font(
            .system(
              size: 20,
              weight: .semibold
            )
          )
          .foregroundColor(.blue)

          VStack(
            alignment: .leading,
            spacing: 4
          ) {
            Text("Additional Test Results")
              .font(
                .system(
                  size: 18,
                  weight: .bold
                )
              )
              .foregroundColor(
                themeManager.current.primaryText
              )

            Text(
              "\(confirmedAdditionalFields.count) tests found"
            )
            .font(.system(size: 13))
            .foregroundColor(
              themeManager.current.secondaryText
            )
          }

          Spacer()

          Image(
            systemName:
              isAdditionalResultsExpanded
              ? "chevron.up"
              : "chevron.down"
          )
          .font(
            .system(
              size: 15,
              weight: .semibold
            )
          )
          .foregroundColor(
            themeManager.current.secondaryText
          )
          .rotationEffect(
            .degrees(
              isAdditionalResultsExpanded
                ? 0
                : 0
            )
          )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        isAdditionalResultsExpanded
          ? "Hide additional test results"
          : "Show additional test results"
      )

      // Results appear only after the tab is opened
      if isAdditionalResultsExpanded {
        Divider()
          .padding(.horizontal, 18)

        VStack(spacing: 0) {
          ForEach(
            Array(
              confirmedAdditionalFields.enumerated()
            ),
            id: \.element.id
          ) { index, field in

            extendedHealthResultRow(field)
              .padding(.horizontal, 18)

            if index < confirmedAdditionalFields.count - 1 {

              Divider()
                .padding(.leading, 18)
            }
          }
        }
        .padding(.bottom, 6)

      }
    }
    .background(
      themeManager.current.cardBackground
    )
    .cornerRadius(20)
    .overlay {
      RoundedRectangle(
        cornerRadius: 20
      )
      .stroke(
        isAdditionalResultsExpanded
          ? Color.blue.opacity(0.35)
          : themeManager.current.cardBorder,
        lineWidth: 1
      )
    }
  }

  private func extendedHealthResultRow(
    _ field: HealthOCRAdditionalField
  ) -> some View {

    let valueText = (field.value?.displayText ?? "")
      .trimmingCharacters(
        in: .whitespacesAndNewlines
      )

    let unitText = (field.unit ?? "")
      .trimmingCharacters(
        in: .whitespacesAndNewlines
      )

    return HStack(
      alignment: .center,
      spacing: 12
    ) {
      VStack(
        alignment: .leading,
        spacing: 4
      ) {
        Text(field.name)
          .font(
            .system(
              size: 14,
              weight: .semibold
            )
          )
          .foregroundColor(
            themeManager.current.primaryText
          )

        // Text("Detected from health report")
        //     .font(.system(size: 11))
        //     .foregroundColor(
        //         themeManager.current.secondaryText
        //     )
      }

      Spacer()

      HStack(
        alignment: .firstTextBaseline,
        spacing: 5
      ) {
        Text(
          valueText.isEmpty
            ? "Not found"
            : valueText
        )
        .font(
          .system(
            size: 15,
            weight: .bold,
            design: .rounded
          )
        )
        .foregroundColor(
          valueText.isEmpty
            ? themeManager.current.secondaryText
            : themeManager.current.primaryText
        )
        .multilineTextAlignment(.trailing)
        .lineLimit(2)

        if !unitText.isEmpty {
          Text(unitText)
            .font(
              .system(
                size: 12,
                weight: .medium
              )
            )
            .foregroundColor(
              themeManager.current.secondaryText
            )
        }
      }
    }
    .padding(.vertical, 13)
    .padding(.horizontal, 2)
  }

  var saveButton: some View {
    VStack(spacing: 8) {
      Button(action: saveProfile) {
        HStack(spacing: 8) {
          if isSaving {
            ProgressView().progressViewStyle(
              CircularProgressViewStyle(
                tint: themeManager.current == .dark ? .black : .white)
            ).scaleEffect(0.85)
          } else if !hasChanges {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
          }
          Text(isSaving ? "Saving…" : hasChanges ? "Save Changes" : "No Changes")
            .font(.system(size: 16, weight: .bold))
        }
        .foregroundColor(
          hasChanges
            ? (themeManager.current == .dark ? .black : .white)
            : themeManager.current.secondaryText
        )
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
          hasChanges
            ? (themeManager.current == .dark ? Color.white : Color.black)
            : themeManager.current.inputBackground
        )
        .cornerRadius(16)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(hasChanges ? Color.clear : themeManager.current.cardBorder, lineWidth: 1))
      }
      .disabled(isSaving || sex.isEmpty || !hasChanges)
      if !hasChanges {
        Text("Make changes to enable saving").font(.system(size: 12)).foregroundColor(
          themeManager.current.secondaryText)
      }
    }
  }

  func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(
          themeManager.current.primaryText)
        Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(
          themeManager.current.primaryText)
      }
      content()
    }
    .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
    .overlay(
      RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
  }

  func inlineSlider(
    label: String, value: Binding<Double>, range: ClosedRange<Double>,
    step: Double, display: String, warningRange: ClosedRange<Double>? = nil
  ) -> some View {
    let isWarning =
      warningRange.map {
        value.wrappedValue >= $0.lowerBound && value.wrappedValue <= $0.upperBound
      } ?? false
    let isDanger = warningRange.map { value.wrappedValue > $0.upperBound } ?? false
    let accent: Color =
      isDanger ? .red : isWarning ? .orange : (themeManager.current == .dark ? .white : .black)
    return VStack(spacing: 6) {
      HStack {
        Text(label).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
        Spacer()
        Text(display).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(
          accent)
      }
      Slider(value: value, in: range, step: step).accentColor(accent)
    }
  }

  func clinicalRow<Content: View>(
    title: String, subtitle: String, isOn: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(
            themeManager.current.primaryText)
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
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    picker.allowsEditing = false
    return picker
  }
  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }
  class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onCapture: (UIImage) -> Void
    init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }
    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      picker.dismiss(animated: true)
      if let image = info[.originalImage] as? UIImage { onCapture(image) }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      picker.dismiss(animated: true)
    }
  }
}

// MARK: - FlowLayout (unchanged)

private struct _FlowLayout<Item: Hashable, Content: View>: View {
  let items: [Item]
  let content: (Item) -> Content
  @State private var totalHeight: CGFloat = .zero
  init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
    self.items = items
    self.content = content
  }
  var body: some View {
    GeometryReader { geo in generateContent(in: geo) }.frame(height: totalHeight)
  }
  private func generateContent(in geo: GeometryProxy) -> some View {
    var width = CGFloat.zero
    var height = CGFloat.zero
    return ZStack(alignment: .topLeading) {
      ForEach(items, id: \.self) { item in
        content(item).padding(.trailing, 8).padding(.bottom, 8)
          .alignmentGuide(.leading) { d in
            if abs(width - d.width) > geo.size.width {
              width = 0
              height -= d.height
            }
            let result = width
            if item == items.last { width = 0 } else { width -= d.width }
            return result
          }
          .alignmentGuide(.top) { _ in
            let result = height
            if item == items.last { height = 0 }
            return result
          }
      }
    }
    .background(
      GeometryReader { geo in
        Color.clear.preference(key: _HeightKey.self, value: geo.size.height)
      }
    )
    .onPreferenceChange(_HeightKey.self) { totalHeight = $0 }
  }
}
private struct _HeightKey: PreferenceKey {
  static var defaultValue: CGFloat = .zero
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

// MARK: - OCR field conversion details (structured tooltips)

private struct OCRTipContent {
  struct ConversionRule: Identifiable {
    let id = UUID()
    let label: String
    let formula: String
  }

  let title: String?
  let onReport: String?
  let formula: String?
  let calculation: String?
  let conversionNote: String?
  let noConversionNote: String?
  let savedValue: String
  let savedUnit: String
  let fromValue: String?
  let fromUnit: String?
  let footnote: String?
  let rules: [ConversionRule]

  static func overview() -> OCRTipContent {
    OCRTipContent(
      title: "How this works",
      onReport: nil,
      formula: nil,
      calculation: nil,
      conversionNote:
        "Read shows what's printed on your report. Value is the number we save in standard units.",
      noConversionNote: nil,
      savedValue: "",
      savedUnit: "",
      fromValue: nil,
      fromUnit: nil,
      footnote: "Tap ⓘ on any row for that field's math. Toggle off = won't save.",
      rules: [
        .init(label: "Glucose", formula: "mg/dL ÷ 18"),
        .init(label: "Lipids", formula: "mg/dL ÷ 38.67"),
        .init(label: "Triglycerides", formula: "mg/dL ÷ 88.57"),
        .init(label: "HbA1c (IFCC)", formula: "× 0.0915 + 2.15"),
        .init(label: "Height", formula: "in × 2.54"),
        .init(label: "Weight", formula: "lb × 0.4536"),
        .init(label: "BP", formula: "no change"),
      ]
    )
  }
}

private enum OCRFieldConversionTip {
  static func content(for field: OCRField) -> OCRTipContent {
    let rawLine = [field.rawName, field.rawValue, field.rawUnit]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    let rawUnit = (field.rawUnit ?? "").lowercased()
    let rawNum = parseNumber(field.rawValue)
    let procNum = parseNumber(field.editedValue)
    let procUnit = field.processedUnit
    let onReport = rawLine.isEmpty ? nil : rawLine

    switch field.id {
    case "systolic_bp", "diastolic_bp":
      return OCRTipContent(
        title: field.label,
        onReport: onReport,
        formula: nil,
        calculation: nil,
        conversionNote: nil,
        noConversionNote: "mmHg — kept as printed on the report.",
        savedValue: field.editedValue,
        savedUnit: "mmHg",
        fromValue: field.rawValue,
        fromUnit: normalizedUnit(field.rawUnit) ?? "mmHg",
        footnote: nil,
        rules: []
      )

    case "blood_sugar":
      return conversionTip(
        field: field, onReport: onReport, rawUnit: rawUnit,
        rawNum: rawNum, procNum: procNum, procUnit: procUnit,
        formula: "mg/dL ÷ 18 → mmol/L", factor: 18.0, divide: true
      )

    case "cholesterol", "ldl", "hdl":
      return conversionTip(
        field: field, onReport: onReport, rawUnit: rawUnit,
        rawNum: rawNum, procNum: procNum, procUnit: procUnit,
        formula: "mg/dL ÷ 38.67 → mmol/L", factor: 38.67, divide: true
      )

    case "triglycerides":
      return conversionTip(
        field: field, onReport: onReport, rawUnit: rawUnit,
        rawNum: rawNum, procNum: procNum, procUnit: procUnit,
        formula: "mg/dL ÷ 88.57 → mmol/L", factor: 88.57, divide: true
      )

    case "hba1c":
      if rawUnit.contains("mol") || rawUnit.contains("ifcc") {
        var calc: String?
        if let r = rawNum {
          calc = "\(trimNum(r)) × 0.0915 + 2.15 ≈ \(trimNum(r * 0.0915 + 2.15))%"
        }
        return OCRTipContent(
          title: field.label,
          onReport: onReport,
          formula: "IFCC mmol/mol → %",
          calculation: calc,
          conversionNote: "% = mmol/mol × 0.0915 + 2.15",
          noConversionNote: nil,
          savedValue: field.editedValue,
          savedUnit: procUnit,
          fromValue: field.rawValue,
          fromUnit: normalizedUnit(field.rawUnit),
          footnote: nil,
          rules: []
        )
      }
      return passthroughTip(field: field, onReport: onReport, procUnit: procUnit)

    case "height_cm":
      if rawUnit.contains("in") || rawUnit == "\"" || rawUnit == "in" {
        return conversionTip(
          field: field, onReport: onReport, rawUnit: rawUnit,
          rawNum: rawNum, procNum: procNum, procUnit: procUnit,
          formula: "in × 2.54 → cm", factor: 2.54, divide: false
        )
      }
      return passthroughTip(field: field, onReport: onReport, procUnit: procUnit)

    case "weight_kg":
      if rawUnit.contains("lb") {
        return conversionTip(
          field: field, onReport: onReport, rawUnit: rawUnit,
          rawNum: rawNum, procNum: procNum, procUnit: procUnit,
          formula: "lb × 0.4536 → kg", factor: 0.4536, divide: false
        )
      }
      return passthroughTip(field: field, onReport: onReport, procUnit: procUnit)

    case "bmi":
      return OCRTipContent(
        title: field.label,
        onReport: onReport,
        formula: nil,
        calculation: nil,
        conversionNote: nil,
        noConversionNote: "Usually taken straight from the report.",
        savedValue: field.editedValue,
        savedUnit: procUnit,
        fromValue: field.rawValue,
        fromUnit: normalizedUnit(field.rawUnit),
        footnote: nil,
        rules: []
      )

    default:
      return passthroughTip(field: field, onReport: onReport, procUnit: procUnit)
    }
  }

  private static func passthroughTip(field: OCRField, onReport: String?, procUnit: String)
    -> OCRTipContent
  {
    OCRTipContent(
      title: field.label,
      onReport: onReport,
      formula: nil,
      calculation: nil,
      conversionNote: nil,
      noConversionNote: "Already in \(procUnit) — no conversion needed.",
      savedValue: field.editedValue,
      savedUnit: procUnit,
      fromValue: field.rawValue,
      fromUnit: normalizedUnit(field.rawUnit) ?? procUnit,
      footnote: nil,
      rules: []
    )
  }

  private static func conversionTip(
    field: OCRField,
    onReport: String?,
    rawUnit: String,
    rawNum: Double?,
    procNum: Double?,
    procUnit: String,
    formula: String,
    factor: Double,
    divide: Bool
  ) -> OCRTipContent {
    let needsConversion =
      rawUnit.contains("mg") || rawUnit.contains("lb")
      || rawUnit.contains("in") || rawUnit == "\""
    guard needsConversion else {
      return passthroughTip(field: field, onReport: onReport, procUnit: procUnit)
    }

    var calculation: String?
    var note: String?
    if let r = rawNum {
      let calc = divide ? r / factor : r * factor
      let op = divide ? "÷" : "×"
      calculation = "\(trimNum(r)) \(op) \(trimNum(factor)) ≈ \(trimNum(calc))"
      if let p = procNum, abs(calc - p) > 0.15 {
        note = "Showing \(trimNum(p)) after rounding"
      }
    }

    return OCRTipContent(
      title: field.label,
      onReport: onReport,
      formula: formula,
      calculation: calculation,
      conversionNote: note,
      noConversionNote: nil,
      savedValue: field.editedValue,
      savedUnit: procUnit,
      fromValue: field.rawValue,
      fromUnit: normalizedUnit(field.rawUnit),
      footnote: nil,
      rules: []
    )
  }

  private static func normalizedUnit(_ unit: String?) -> String? {
    guard let unit, !unit.isEmpty else { return nil }
    return
      unit
      .replacingOccurrences(of: "mm[Hg]", with: "mmHg", options: .regularExpression)
      .replacingOccurrences(of: "kg/m2", with: "kg/m²", options: .caseInsensitive)
  }

  private static func parseNumber(_ text: String?) -> Double? {
    guard let text else { return nil }
    let cleaned =
      text
      .replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespaces)
    return Double(cleaned)
  }

  private static func trimNum(_ n: Double) -> String {
    n == n.rounded() && abs(n) < 1_000_000
      ? String(format: "%.0f", n)
      : String(format: "%.2f", n)
  }
}

// MARK: - OCR tooltip panel

private struct OCRTipPanelView: View {
  @EnvironmentObject var themeManager: ThemeManager
  let content: OCRTipContent

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let title = content.title {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(themeManager.current.primaryText)
      }

      if let onReport = content.onReport {
        tipSection(icon: "doc.text", label: "On report") {
          Text(onReport)
            .font(.system(size: 13))
            .foregroundColor(themeManager.current.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let conversionNote = content.conversionNote, content.formula == nil {
        tipSection(icon: "info.circle", label: "Note") {
          Text(conversionNote)
            .font(.system(size: 13))
            .foregroundColor(themeManager.current.secondaryText)
        }
      }

      if let formula = content.formula {
        tipSection(icon: "arrow.triangle.2.circlepath", label: "Conversion") {
          VStack(alignment: .leading, spacing: 8) {
            Text(formula)
              .font(.system(size: 12, weight: .semibold, design: .monospaced))
              .foregroundColor(themeManager.current.primaryText)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(themeManager.current.inputBackground)
              .cornerRadius(8)

            if let calculation = content.calculation {
              Text(calculation)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(themeManager.current.secondaryText)
            }

            if let note = content.conversionNote {
              Text(note)
                .font(.system(size: 11))
                .foregroundColor(themeManager.current.secondaryText)
            }
          }
        }
      }

      if let noConversion = content.noConversionNote {
        tipSection(icon: "checkmark.circle", label: "Conversion") {
          Text(noConversion)
            .font(.system(size: 13))
            .foregroundColor(themeManager.current.secondaryText)
        }
      }

      if !content.savedValue.isEmpty {
        tipSection(icon: "checkmark.seal.fill", label: "Saved value") {
          if let fromValue = content.fromValue,
            let fromUnit = content.fromUnit,
            content.formula != nil
          {
            conversionFlow(
              fromValue: fromValue,
              fromUnit: fromUnit,
              toValue: content.savedValue,
              toUnit: content.savedUnit
            )
          } else {
            Text("\(content.savedValue) \(content.savedUnit)")
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .foregroundColor(.green)
          }
        }
      }

      if !content.rules.isEmpty {
        tipSection(icon: "list.bullet.rectangle", label: "Common conversions") {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(content.rules) { rule in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rule.label)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundColor(themeManager.current.primaryText)
                  .frame(width: 92, alignment: .leading)
                Text(rule.formula)
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundColor(themeManager.current.secondaryText)
              }
            }
          }
        }
      }

      if let footnote = content.footnote {
        Text(footnote)
          .font(.system(size: 11))
          .foregroundColor(themeManager.current.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func tipSection<Content: View>(
    icon: String,
    label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.green)
        Text(label.uppercased())
          .font(.system(size: 10, weight: .bold))
          .tracking(0.6)
          .foregroundColor(themeManager.current.secondaryText)
      }
      content()
    }
  }

  private func conversionFlow(
    fromValue: String,
    fromUnit: String,
    toValue: String,
    toUnit: String
  ) -> some View {
    HStack(spacing: 12) {
      VStack(spacing: 2) {
        Text(fromValue)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundColor(themeManager.current.primaryText)
        Text(fromUnit)
          .font(.system(size: 10))
          .foregroundColor(themeManager.current.secondaryText)
      }
      .frame(maxWidth: .infinity)

      Image(systemName: "arrow.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.green)

      VStack(spacing: 2) {
        Text(toValue)
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundColor(.green)
        Text(toUnit)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.green.opacity(0.8))
      }
      .frame(maxWidth: .infinity)
    }
    .padding(12)
    .background(Color.green.opacity(0.08))
    .cornerRadius(12)
  }
}

// MARK: - OCR info tooltip

private struct InfoTipButton: View {
  @EnvironmentObject var themeManager: ThemeManager
  let content: OCRTipContent
  @State private var showTip = false

  private var isOverview: Bool { !content.rules.isEmpty }

  var body: some View {
    Button {
      showTip = true
    } label: {
      Image(systemName: "info.circle")
        .font(.system(size: 14))
        .foregroundColor(themeManager.current.secondaryText)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("More information")
    .fullScreenCover(isPresented: $showTip) {
      NavigationStack {
        ScrollView(showsIndicators: false) {
          // OCRTipPanelView(content: content)
          //     .padding(20)

          OCRTipPanelView(content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(themeManager.current.background)
        .navigationTitle(isOverview ? "Scan help" : content.title ?? "Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showTip = false }
              .font(.system(size: 16, weight: .semibold))
          }
        }
      }
      // .presentationDetents(isOverview ? [.medium, .large] : [.height(340), .medium])
      // .presentationDragIndicator(.visible)
      .environmentObject(themeManager)
    }
  }
}

// MARK: - OCR Confirmation Sheet (raw → processed review)

/// Shows each detected metric's RAW reading (what the model saw on the report)
/// next to the normalized PROCESSED value. The user confirms/edits before any
/// value is applied to the form, so only confirmed processed values get saved.
struct OCRConfirmView: View {
  @EnvironmentObject var themeManager: ThemeManager
  @Environment(\.dismiss) var dismiss

  @State var fields: [OCRField]
  @State private var additionalFields: [OCRField]
  let status: String  // "ok" / "no_fields" / "no_text"
  let message: String?
  let onConfirm:
    (
      [OCRField],
      [HealthOCRAdditionalField]
    ) -> Void
  @State private var isExtendedResultsExpanded = false

  init(
    fields: [OCRField],
    additionalFields: [HealthOCRAdditionalField],
    status: String,
    message: String?,
    onConfirm:
      @escaping (
        [OCRField],
        [HealthOCRAdditionalField]
      ) -> Void
  ) {
    _fields = State(initialValue: fields)
    _additionalFields = State(
      initialValue: additionalFields.enumerated().map { item in
        let (index, field) = item

        return OCRField(
          id: "additional_\(index)",
          label: field.name,
          rawName: field.name,
          rawValue: field.value?.displayText,
          rawUnit: field.unit,
          processedUnit: field.unit ?? "",
          editedValue: field.value?.displayText ?? "",
          accepted: true
        )
      }
    )
    self.status = status
    self.message = message
    self.onConfirm = onConfirm
  }

  private var hasFields: Bool {
    status == "ok" && (!fields.isEmpty || !additionalFields.isEmpty)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        themeManager.current.background.ignoresSafeArea()
        if hasFields { fieldList } else { emptyState }
      }
      .preferredColorScheme(themeManager.current.colorScheme)
      .navigationTitle("Confirm Scan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundColor(themeManager.current.primaryText)
        }
        ToolbarItem(placement: .confirmationAction) {
          if hasFields {
            Button("Use Values") {
              onConfirm(
                fields,
                confirmedAdditionalFields
              )
              dismiss()
            }
            .font(.system(size: 16, weight: .bold))
          }
        }
      }
    }
  }

  private var fieldList: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 14)).foregroundColor(.green)
            .padding(.top, 1)
          Text("Check what we read from your report. Edit any value, then confirm.")
            .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
          InfoTipButton(content: OCRTipContent.overview())
        }
        .padding(12)
        .background(Color.green.opacity(0.06)).cornerRadius(12)

        ForEach(fields.indices, id: \.self) { index in
          fieldRow($fields[index])
        }
        if !additionalFields.isEmpty {
          extendedResultsSection
        }
      }
      .padding(20)
    }
  }

  private func fieldRow(
    _ field: Binding<OCRField>
  ) -> some View {

    let f = field.wrappedValue

    let rawText = [
      f.rawName,
      f.rawValue,
      f.rawUnit,
    ]
    .compactMap { $0 }
    .map {
      $0.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
    }
    .filter { !$0.isEmpty }
    .joined(separator: " ")

    return VStack(
      alignment: .leading,
      spacing: 16
    ) {
      // Icon, title and switch
      HStack(spacing: 14) {

        HStack(spacing: 5) {
          Text(f.label)
            .font(
              .system(
                size: 18,
                weight: .bold
              )
            )
            .foregroundColor(
              themeManager.current.primaryText
            )

          InfoTipButton(
            content:
              OCRFieldConversionTip
              .content(for: f)
          )
        }

        Spacer()

        Toggle(
          "",
          isOn: field.accepted
        )
        .labelsHidden()
        .toggleStyle(
          SwitchToggleStyle(tint: .green)
        )
      }

      // Original OCR text
      // if !rawText.isEmpty {
      //     Text("Read: \(rawText)")
      //         .font(.system(size: 13))
      //         .foregroundColor(
      //             themeManager.current.secondaryText
      //         )
      // }

      // Editable processed value
      HStack(spacing: 10) {
        Text("Value")
          .font(.system(size: 15))
          .foregroundColor(
            themeManager.current.secondaryText
          )

        Spacer()

        TextField(
          "",
          text: field.editedValue
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(
          .system(
            size: 18,
            weight: .bold,
            design: .rounded
          )
        )
        .foregroundColor(
          themeManager.current.primaryText
        )
        .frame(width: 100)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
          themeManager.current.inputBackground
        )
        .cornerRadius(10)
        .disabled(!f.accepted)

        // if !f.processedUnit.isEmpty {
        //     Text(f.processedUnit)
        //         .font(
        //             .system(
        //                 size: 14,
        //                 weight: .medium
        //             )
        //         )
        //         .foregroundColor(
        //             themeManager.current.secondaryText
        //         )
        //         .fixedSize()
        // }

        Text(f.processedUnit)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(themeManager.current.secondaryText)
          .frame(width: 60, alignment: .leading)
      }
    }
    .padding(18)
    .background(
      themeManager.current.cardBackground
    )
    .cornerRadius(20)
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          f.accepted
            ? Color.green.opacity(0.22)
            : themeManager.current.cardBorder,
          lineWidth: 1
        )
    }
    .shadow(
      color: Color.black.opacity(0.035),
      radius: 10,
      x: 0,
      y: 4
    )
    .opacity(f.accepted ? 1 : 0.55)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: status == "no_text" ? "doc.text.magnifyingglass" : "questionmark.folder")
        .font(.system(size: 44))
        .foregroundColor(themeManager.current.secondaryText)
      Text(status == "no_text" ? "No text detected" : "No recognizable metrics")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(themeManager.current.primaryText)
      Text(message ?? "You can enter your values manually.")
        .font(.system(size: 14))
        .foregroundColor(themeManager.current.secondaryText)
        .multilineTextAlignment(.center)
      Button(action: { dismiss() }) {
        Text("Enter manually")
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(themeManager.current == .dark ? .black : .white)
          .frame(maxWidth: .infinity).padding(.vertical, 14)
          .background(themeManager.current == .dark ? Color.white : Color.black)
          .cornerRadius(14)
      }
      .padding(.top, 8)
    }
    .padding(32)
  }

  private var extendedResultsSection: some View {
    VStack(spacing: 0) {

      // Collapsible header
      Button {
        withAnimation(
          .easeInOut(duration: 0.22)
        ) {
          isExtendedResultsExpanded.toggle()
        }
      } label: {
        HStack(spacing: 14) {
          Image(
            systemName: "list.bullet.rectangle"
          )
          .font(
            .system(
              size: 20,
              weight: .semibold
            )
          )
          .foregroundStyle(.blue)

          VStack(
            alignment: .leading,
            spacing: 4
          ) {
            Text("Additional Test Results")
              .font(
                .system(
                  size: 18,
                  weight: .bold
                )
              )
              .foregroundStyle(.primary)

            Text(
              "\(additionalFields.count) tests found"
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }

          Spacer()

          Image(
            systemName:
              isExtendedResultsExpanded
              ? "chevron.up"
              : "chevron.down"
          )
          .font(
            .system(
              size: 15,
              weight: .semibold
            )
          )
          .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        isExtendedResultsExpanded
          ? "Hide additional test results"
          : "Show additional test results"
      )

      // Expanded results
      if isExtendedResultsExpanded {
        Divider()
          .padding(.horizontal, 18)

        VStack(spacing: 12) {
          ForEach(additionalFields.indices, id: \.self) { index in
            additionalFieldRow($additionalFields[index])
          }
        }
        .padding(18)
      }
    }
    .background(
      themeManager.current.cardBackground
    )
    .clipShape(
      RoundedRectangle(cornerRadius: 20)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          isExtendedResultsExpanded
            ? Color.blue.opacity(0.35)
            : Color.gray.opacity(0.18),
          lineWidth: 1
        )
    }
  }

  private func additionalFieldRow(
    _ field: Binding<OCRField>
  ) -> some View {

    let f = field.wrappedValue

    return HStack(spacing: 12) {
      Text(f.label)
        .font(
          .system(
            size: 15,
            weight: .semibold
          )
        )
        .foregroundColor(
          themeManager.current.primaryText
        )
        .frame(
          maxWidth: .infinity,
          alignment: .leading
        )

      TextField("", text: field.editedValue)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(
          .system(
            size: 16,
            weight: .bold,
            design: .rounded
          )
        )
        .foregroundColor(
          themeManager.current.primaryText
        )
        .frame(width: 85)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
          themeManager.current.inputBackground
        )
        .cornerRadius(9)
        .disabled(!f.accepted)

      // if !f.processedUnit.isEmpty {
      //     Text(f.processedUnit)
      //         .font(
      //             .system(
      //                 size: 13,
      //                 weight: .medium
      //             )
      //         )
      //         .foregroundColor(
      //             themeManager.current.secondaryText
      //         )
      //         .fixedSize()
      // }
      Text(f.processedUnit)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(themeManager.current.secondaryText)
        .frame(width: 45, alignment: .leading)

      Toggle("", isOn: field.accepted)
        .labelsHidden()
        .toggleStyle(
          SwitchToggleStyle(tint: .green)
        )
    }
    .padding(14)
    .background(
      themeManager.current.cardBackground
    )
    .cornerRadius(16)
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(
          f.accepted
            ? Color.green.opacity(0.22)
            : themeManager.current.cardBorder,
          lineWidth: 1
        )
    }
    .opacity(f.accepted ? 1 : 0.55)
  }

  private var confirmedAdditionalFields: [HealthOCRAdditionalField] {

    additionalFields
      .filter { $0.accepted }
      .map { field in
        let editedValue = field.editedValue
          .trimmingCharacters(
            in: .whitespacesAndNewlines
          )

        let value: HealthOCRRawValue?
        if editedValue.isEmpty {
          value = nil
        } else if let number = Double(editedValue) {
          value = .number(number)
        } else {
          value = .string(editedValue)
        }

        return HealthOCRAdditionalField(
          name: field.label,
          value: value,
          unit: field.processedUnit.isEmpty
            ? nil
            : field.processedUnit
        )
      }
  }
}
