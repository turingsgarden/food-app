//
//  EapandableMealCard.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/12/26.
//

// ExpandableMealCard.swift
// Diet Plan 餐食卡片：
// - 展开/收起食物列表
// - 拍照 or 从相册选择

import SwiftUI
import PhotosUI

struct ExpandableMealCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: PlannedMeal
    let day: DayMealPlan
    let plan: WeeklyMealPlan
    let today: String
    var onPhotoSelected: ((Data) -> Void)?

    @State private var isExpanded = false
    @State private var showImageSourceSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var canLog: Bool { day.date >= today }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                HStack(spacing: 10) {
                    // Meal type badge
                    Text(meal.mealType.capitalized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(mealTypeColor(meal.mealType))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(mealTypeColor(meal.mealType).opacity(0.12))
                        .cornerRadius(20)

                    // Meal name — full text, no truncation
                    if let name = meal.name {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeManager.current.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    // Calories
                    Text("\(meal.totalCalories) kcal")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                        .fixedSize()

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, isExpanded ? 10 : 14)
            }
            .buttonStyle(.plain)

            // ── Expanded content ──
            if isExpanded {
                Divider()
                    .background(themeManager.current.cardBorder)
                    .padding(.horizontal, 16)

                // Food items
                VStack(spacing: 8) {
                    ForEach(meal.items) { item in
                        HStack {
                            Text(item.food)
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.current.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(String(format: "%.0fg", item.amountG))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeManager.current.secondaryText)
                                .fixedSize()
                            Text("·  \(item.calories) kcal")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.current.secondaryText)
                                .fixedSize()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Macro pills + Log button
                HStack(spacing: 8) {
                    macroPill("P", "\(meal.totalProtein)g", Color(red: 0.93, green: 0.36, blue: 0.36))
                    macroPill("C", "\(meal.totalCarbs)g", Color(red: 0.95, green: 0.61, blue: 0.20))
                    macroPill("F", "\(meal.totalFat)g", Color(red: 0.35, green: 0.62, blue: 0.93))
                    Spacer()

                    if canLog {
                        Button(action: { showImageSourceSheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11))
                                Text("Log")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(themeManager.current == .dark ? Color.white : Color.black)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else {
                // Collapsed: show macro pills + log in one line
                HStack(spacing: 8) {
                    macroPill("P", "\(meal.totalProtein)g", Color(red: 0.93, green: 0.36, blue: 0.36))
                    macroPill("C", "\(meal.totalCarbs)g", Color(red: 0.95, green: 0.61, blue: 0.20))
                    macroPill("F", "\(meal.totalFat)g", Color(red: 0.35, green: 0.62, blue: 0.93))
                    Spacer()
                    if canLog {
                        Button(action: { showImageSourceSheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11))
                                Text("Log")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(themeManager.current == .dark ? Color.white : Color.black)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))

        // ── Image source action sheet ──
        .confirmationDialog("Add Photo", isPresented: $showImageSourceSheet, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }

        // ── Camera ──
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                guard let img = image,
                      let data = HealthAPIManager.shared.compressImage(img)
                else { return }
                onPhotoSelected?(data)
            }
        }

        // ── Photo Library (PhotosPickerItem) ──
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $selectedPhotoItem,
                      matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data),
                   let compressed = HealthAPIManager.shared.compressImage(ui) {
                    await MainActor.run { onPhotoSelected?(compressed) }
                }
            }
        }
    }

    func macroPill(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    func mealTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "breakfast": return Color(red: 0.95, green: 0.61, blue: 0.20)
        case "lunch":     return Color(red: 0.35, green: 0.62, blue: 0.93)
        case "dinner":    return Color(red: 0.55, green: 0.35, blue: 0.85)
        default:          return .gray
        }
    }
}

// MARK: - UIImagePickerController wrapper (Camera support)

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onCapture: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onCapture(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
            parent.dismiss()
        }
    }
}
