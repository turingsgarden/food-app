import SwiftUI
import PhotosUI
import UIKit

// MARK: - One table row

struct OCRResultRow: Identifiable {
    var id: String { name }

    let name: String
    let value: String
    let unit: String
    let isMissing: Bool
}

// MARK: - Health OCR screen

struct HealthOCRTestView: View {

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?

    // Save the full OCR response here.
    @State private var ocrResponse: HealthOCRResponse?

    @State private var message = "Select a medical-report image."
    @State private var isScanning = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {

                // MARK: Title

                Text("Health Report OCR")
                    .font(.system(size: 26, weight: .bold))

                // MARK: Status message

                HStack(spacing: 10) {
                    if isScanning {
                        ProgressView()
                            .tint(.orange)
                    } else {
                        Image(
                            systemName: ocrResponse == nil
                                ? "doc.text.viewfinder"
                                : "checkmark.circle.fill"
                        )
                        .foregroundColor(
                            ocrResponse == nil ? .orange : .green
                        )
                    }

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )

                // MARK: Selected image preview

                if let imageData,
                   let selectedImage = UIImage(data: imageData) {

                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 230)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    Color.gray.opacity(0.2),
                                    lineWidth: 1
                                )
                        }
                }

                // MARK: Select report button

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17))

                        Text(
                            imageData == nil
                                ? "Select Report Image"
                                : "Choose Another Image"
                        )
                        .font(.system(size: 15, weight: .semibold))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                Color.orange.opacity(0.6),
                                lineWidth: 1.2
                            )
                    }
                }
                .buttonStyle(.plain)

                // MARK: Run OCR button

                Button {
                    runOCR()
                } label: {
                    HStack(spacing: 10) {
                        if isScanning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "doc.text.viewfinder")
                        }

                        Text(
                            isScanning
                                ? "Scanning Report..."
                                : "Run OCR"
                        )
                        .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                imageData == nil || isScanning
                                    ? Color.gray
                                    : Color.orange
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(imageData == nil || isScanning)

                // MARK: Extracted results table

                if !resultRows.isEmpty {
                    extractedResultsSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
        .background(Color(.systemBackground))
        .onChange(of: selectedPhoto) { selectedPhoto in
            loadImage(selectedPhoto)
        }
    }

    // MARK: - Results section

    private var extractedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Extracted Results")
                        .font(.system(size: 20, weight: .bold))

                    Text("Values detected from the report.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(detectedFieldCount) detected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    )
            }

            VStack(spacing: 0) {

                // Table header
                HStack(spacing: 8) {
                    Text("Health field")
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                    Text("Result")
                        .frame(width: 80, alignment: .trailing)

                    Text("Unit")
                        .frame(width: 70, alignment: .leading)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemBackground))

                Divider()

                ForEach(Array(resultRows.enumerated()), id: \.element.id) {
                    index,
                    row in

                    OCRResultTableRow(row: row)

                    if index < resultRows.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.gray.opacity(0.18),
                        lineWidth: 1
                    )
            }
        }
    }

    // MARK: - Table data

    private var resultRows: [OCRResultRow] {
        guard let response = ocrResponse else {
            return []
        }

        return [
            createRow(
                name: "Systolic BP",
                value: response.systolicBP,
                unit: "mmHg"
            ),
            createRow(
                name: "Diastolic BP",
                value: response.diastolicBP,
                unit: "mmHg"
            ),
            createRow(
                name: "Height",
                value: response.heightCM,
                unit: "cm"
            ),
            createRow(
                name: "Weight",
                value: response.weightKG,
                unit: "kg"
            ),
            createRow(
                name: "BMI",
                value: response.bmi,
                unit: "kg/m²"
            ),
            createRow(
                name: "Blood Sugar",
                value: response.bloodSugar,
                unit: "mmol/L"
            ),
            createRow(
                name: "HbA1c",
                value: response.hba1c,
                unit: "%"
            ),
            createRow(
                name: "Cholesterol",
                value: response.cholesterol,
                unit: "mmol/L"
            ),
            createRow(
                name: "LDL Cholesterol",
                value: response.ldl,
                unit: "mmol/L"
            ),
            createRow(
                name: "HDL Cholesterol",
                value: response.hdl,
                unit: "mmol/L"
            ),
            createRow(
                name: "Triglycerides",
                value: response.triglycerides,
                unit: "mmol/L"
            )
        ]
    }

    private var detectedFieldCount: Int {
        resultRows.filter { !$0.isMissing }.count
    }

    private func createRow(
        name: String,
        value: Double?,
        unit: String
    ) -> OCRResultRow {
        OCRResultRow(
            name: name,
            value: formatValue(value),
            unit: unit,
            isMissing: value == nil
        )
    }

    private func formatValue(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "Not found"
        }

        return value.formatted(
            .number.precision(
                .fractionLength(0...2)
            )
        )
    }

    // MARK: - Image loading

    private func loadImage(
        _ photo: PhotosPickerItem?
    ) {
        guard let photo else {
            return
        }

        Task {
            do {
                guard
                    let originalData =
                        try await photo.loadTransferable(
                            type: Data.self
                        ),
                    let image = UIImage(data: originalData),
                    let jpegData = image.jpegData(
                        compressionQuality: 0.9
                    )
                else {
                    await MainActor.run {
                        message =
                            "Could not read the selected image."
                    }
                    return
                }

                await MainActor.run {
                    imageData = jpegData

                    // Remove previous results when selecting a new image.
                    ocrResponse = nil

                    message =
                        "Image selected. Press Run OCR."
                }
            } catch {
                await MainActor.run {
                    message =
                        "Image loading failed: " +
                        error.localizedDescription
                }
            }
        }
    }

    // MARK: - OCR request

    private func runOCR() {
        guard let imageData else {
            message = "Select an image first."
            return
        }

        isScanning = true
        ocrResponse = nil
        message = "Scanning the selected health report..."

        NetworkManager.shared.scanHealthReport(
            imageData: imageData,
            filename: "health-report.jpg",
            mimeType: "image/jpeg"
        ) { result in

            // Make sure all SwiftUI state changes happen on the main thread.
            DispatchQueue.main.async {
                isScanning = false

                switch result {
                case .success(let response):
                    handleSuccess(response)

                case .failure(let error):
                    ocrResponse = nil
                    message =
                        "OCR failed: " +
                        error.localizedDescription
                }
            }
        }
    }

    // MARK: - OCR response

    private func handleSuccess(
        _ response: HealthOCRResponse
    ) {
        switch response.status {
        case .ok:
            ocrResponse = response
            message = "OCR completed successfully."

            print("OCR status:", response.status.rawValue)
            print("Systolic BP:", response.systolicBP as Any)
            print("Diastolic BP:", response.diastolicBP as Any)
            print("Height:", response.heightCM as Any)
            print("Weight:", response.weightKG as Any)
            print("BMI:", response.bmi as Any)
            print("Blood sugar:", response.bloodSugar as Any)
            print("HbA1c:", response.hba1c as Any)
            print("Cholesterol:", response.cholesterol as Any)
            print("LDL:", response.ldl as Any)
            print("HDL:", response.hdl as Any)
            print(
                "Triglycerides:",
                response.triglycerides as Any
            )

        case .noFields:
            ocrResponse = nil
            message =
                response.message
                ?? "The report contains no supported health fields."

        case .noText:
            ocrResponse = nil
            message =
                response.message
                ?? "No readable text was found."
        }
    }
}

// MARK: - Individual table row

private struct OCRResultTableRow: View {
    let row: OCRResultRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            Text(row.value)
                .font(
                    .system(
                        size: 13,
                        weight: row.isMissing
                            ? .regular
                            : .semibold
                    )
                )
                .foregroundColor(
                    row.isMissing ? .secondary : .primary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 80, alignment: .trailing)

            Text(row.unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 70, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

#Preview {
    NavigationStack {
        HealthOCRTestView()
    }
}