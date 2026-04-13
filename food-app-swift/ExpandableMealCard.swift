//
//  EapandableMealCard.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/12/26.
//
//
//  ExpandableMealCard.swift
//  food-app-swift
//
//  修复：加入 onViewResult 回调
//  - 已分析过的 meal，点击分数徽章（紫色 "85%" 按钮）重新显示对比结果
//  - 未分析的 meal，正常显示 Log 按钮拍照

import SwiftUI
import PhotosUI

struct ExpandableMealCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: PlannedMeal
    let day: DayMealPlan
    let plan: WeeklyMealPlan
    let today: String
    var complianceScore: Int? = nil
    var onViewResult: (() -> Void)? = nil      // ✅ 新增：点击已分析徽章时回调
    var onPhotoSelected: ((Data) -> Void)?

    @State private var isExpanded = false
    @State private var showImageSourceSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var canLog: Bool { day.date >= today }
    var isLogged: Bool { complianceScore != nil }

    var scoreColor: Color {
        guard let score = complianceScore else { return .gray }
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(meal.mealType.capitalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(mealTypeColor(meal.mealType))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(mealTypeColor(meal.mealType).opacity(0.12))
                            .cornerRadius(20)

                        Spacer()

                        Text("\(meal.totalCalories) kcal")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)

                        // ✅ 分数徽章 — 点击重新查看对比结果
                        if let score = complianceScore {
                            Button(action: { onViewResult?() }) {
                                HStack(spacing: 3) {
                                    Text("\(score)%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(scoreColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(themeManager.current.secondaryText)
                    }

                    if let name = meal.name {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeManager.current.primaryText)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, isExpanded ? 8 : 12)
            }
            .buttonStyle(.plain)

            // ── Expanded ──
            if isExpanded {
                Divider().background(themeManager.current.cardBorder).padding(.horizontal, 16)

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
                .padding(.horizontal, 16).padding(.vertical, 10)

                bottomBar
                    .padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                bottomBar
                    .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .background(
            themeManager.current.cardBackground
                // ✅ 已分析的 meal 加一个细边框提示
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isLogged ? scoreColor.opacity(0.3) : themeManager.current.cardBorder, lineWidth: isLogged ? 1.5 : 1)
                )
        )
        .cornerRadius(18)

        .confirmationDialog("Add Photo", isPresented: $showImageSourceSheet, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                guard let img = image,
                      let data = HealthAPIManager.shared.compressImage(img) else { return }
                onPhotoSelected?(data)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
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

    // ── Macro pills + action button ──
    var bottomBar: some View {
        HStack(spacing: 8) {
            macroPill("P", "\(meal.totalProtein)g", Color(red: 0.93, green: 0.36, blue: 0.36))
            macroPill("C", "\(meal.totalCarbs)g", Color(red: 0.95, green: 0.61, blue: 0.20))
            macroPill("F", "\(meal.totalFat)g", Color(red: 0.35, green: 0.62, blue: 0.93))
            Spacer()

            if isLogged {
                // ✅ 已分析：显示"View Result"按钮
                Button(action: { onViewResult?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11))
                        Text("View Result")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(scoreColor)
                    .cornerRadius(20)
                }
            } else if canLog {
                // 未分析：显示"Log"拍照按钮
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

// MARK: - UIImagePickerController wrapper

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
