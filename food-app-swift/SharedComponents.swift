import SwiftUI

// MARK: - Shared Data Models

struct EditableIngredient: Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: String
    var unit: String
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: EditableIngredient, rhs: EditableIngredient) -> Bool { lhs.id == rhs.id }
}

// MARK: - Shared View Components

struct EditableIngredientRow: View {
    @Binding var ingredient: EditableIngredient
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill").foregroundColor(.red).font(.title3)
            }
            TextField("Ingredient", text: $ingredient.name)
                .font(.subheadline).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            TextField("Qty", text: $ingredient.quantity)
                .font(.subheadline).foregroundColor(.white).multilineTextAlignment(.center)
                .frame(width: 60).padding(.horizontal, 8).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            TextField("Unit", text: $ingredient.unit)
                .font(.subheadline).foregroundColor(.white)
                .frame(width: 80).padding(.horizontal, 8).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        }
    }
}

struct IngredientDisplay: View {
    let text: String
    var isHidden: Bool = false
    
    var cleanedText: String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        HStack {
            Circle()
                .fill(isHidden ? Color.pink.opacity(0.2) : Color.green.opacity(0.2))
                .frame(width: 8, height: 8)
            Text(cleanedText).font(.subheadline).foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil
    var actionIcon: String? = nil
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.headline).foregroundColor(.white)
            }
            Spacer()
            if let action = action, let actionIcon = actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon).foregroundColor(color)
                }
            }
        }
    }
}

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(GraphicalDatePickerStyle()).padding()
                Spacer()
            }
            .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.orange)
            Text(message).font(.subheadline).foregroundColor(.white).multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - 食材表格（方案A极简风）

struct IngredientTableView: View {
    let ingredients: [EditableIngredient]
    @State private var isExpanded = false

    var displayedIngredients: [EditableIngredient] {
        isExpanded ? ingredients : Array(ingredients.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader
            columnHeaders
            Divider().background(Color.white.opacity(0.06)).padding(.bottom, 4)
            tableRows
            if ingredients.count > 6 { expandButton }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }

    var tableHeader: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 14).cornerRadius(2)
            Text("INGREDIENTS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).kerning(3)
            Spacer()
            Text("\(ingredients.count) items")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("QTY").frame(width: 44, alignment: .trailing)
            Text("UNIT").frame(width: 90, alignment: .center)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(.white.opacity(0.2)).kerning(1)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    var tableRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                IngredientRow(index: index, ingredient: ingredient)
            }
        }
    }

    var expandButton: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.06)).padding(.top, 4)
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Text(isExpanded ? "Show less" : "Show \(ingredients.count - 6) more")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
        }
    }
}

// 单独一行，避免 body 太复杂
struct IngredientRow: View {
    let index: Int
    let ingredient: EditableIngredient

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.15))
                .frame(width: 20, alignment: .leading)
            Text(ingredient.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(ingredient.quantity)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 44, alignment: .trailing)
            Text(ingredient.unit.lowercased())
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 90, alignment: .center)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(index % 2 == 0 ? Color.clear : Color.white.opacity(0.025))
    }
}
