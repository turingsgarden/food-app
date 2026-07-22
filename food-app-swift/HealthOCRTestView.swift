import SwiftUI
import PhotosUI
import UIKit

struct HealthOCRTestView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?

    @State private var message =
        "Select a medical-report image."

    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Health OCR Test")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .multilineTextAlignment(.center)
                .padding()

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                Label(
                    "Select Report Image",
                    systemImage: "photo"
                )
            }
            .buttonStyle(.bordered)

            Button {
                runOCR()
            } label: {
                if isScanning {
                    ProgressView()
                } else {
                    Text("Run OCR")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(imageData == nil || isScanning)

            Spacer()
        }
        .padding()
        .onChange(of: selectedPhoto) { selectedPhoto in
            loadImage(selectedPhoto)
        }
    }

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

    private func runOCR() {
        guard let imageData else {
            message = "Select an image first."
            return
        }

        isScanning = true
        message = "Scanning report..."

        NetworkManager.shared.scanHealthReport(
            imageData: imageData,
            filename: "test-report.jpg",
            mimeType: "image/jpeg"
        ) { result in
            isScanning = false

            switch result {
            case .success(let response):
                handleSuccess(response)

            case .failure(let error):
                message =
                    "OCR failed: " +
                    error.localizedDescription
            }
        }
    }

    private func handleSuccess(
        _ response: HealthOCRResponse
    ) {
        switch response.status {
        case .ok:
            message = """
            OCR completed successfully.

            Systolic BP: \(show(response.systolicBP)) mmHg
            Diastolic BP: \(show(response.diastolicBP)) mmHg
            Height: \(show(response.heightCM)) cm
            Weight: \(show(response.weightKG)) kg
            BMI: \(show(response.bmi)) kg/m²
            Blood sugar: \(show(response.bloodSugar)) mmol/L
            HbA1c: \(show(response.hba1c)) %
            Cholesterol: \(show(response.cholesterol)) mmol/L
            LDL: \(show(response.ldl)) mmol/L
            HDL: \(show(response.hdl)) mmol/L
            Triglycerides: \(show(response.triglycerides)) mmol/L
            """

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
            print("Triglycerides:", response.triglycerides as Any)

            

        case .noFields:
            message =
                response.message
                ?? "The report contains no supported health fields."

        case .noText:
            message =
                response.message
                ?? "No readable text was found."
        }
    }

    private func show(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "Not found"
        }

        return value.formatted()
    }
}

#Preview {
    HealthOCRTestView()
}
