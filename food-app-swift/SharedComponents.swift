import SwiftUI

// MARK: - Shared Data Models

struct EditableIngredient: Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: String
    var unit: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: EditableIngredient, rhs: EditableIngredient) -> Bool {
        lhs.id == rhs.id
    }
}

// Computed accessors for min/max to keep compatibility with existing `quantity` string
extension EditableIngredient {
    var minQuantity: String {
        get {
            let qty = quantity.trimmingCharacters(in: .whitespaces)
            if qty.contains("-") {
                let parts = qty.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 1 { return String(parts[0]) }
            }
            return qty
        }
        set {
            let maxQ = maxQuantity
            quantity = "\(newValue)-\(maxQ)"
        }
    }

    var maxQuantity: String {
        get {
            let qty = quantity.trimmingCharacters(in: .whitespaces)
            if qty.contains("-") {
                let parts = qty.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 { return String(parts[1]) }
                if parts.count == 1 { return String(parts[0]) }
            }
            return qty
        }
        set {
            let minQ = minQuantity
            quantity = "\(minQ)-\(newValue)"
        }
    }
}

// MARK: - Shared View Components

struct EditableIngredientRow: View {
    @Binding var ingredient: EditableIngredient
    let onDelete: () -> Void
    @State private var minQuantity: String = ""
    @State private var maxQuantity: String = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            
            // Name field
            TextField("Ingredient", text: $ingredient.name)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
            
            // Quantity: split into min - max with non-editable dash
            HStack(spacing: 6) {
                TextField("min", text: $minQuantity)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    )

                // Non-editable separator
                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.white)

                TextField("max", text: $maxQuantity)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .onAppear {
                // initialize min/max from legacy quantity string
                let qty = ingredient.quantity.trimmingCharacters(in: .whitespaces)
                if qty.contains("-") {
                    let parts = qty.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 2 {
                        minQuantity = String(parts[0])
                        maxQuantity = String(parts[1])
                    } else {
                        minQuantity = qty
                        maxQuantity = qty
                    }
                } else if !qty.isEmpty {
                    minQuantity = qty
                    maxQuantity = qty
                } else {
                    minQuantity = ""
                    maxQuantity = ""
                }
            }
            .onChange(of: minQuantity) { newVal in
                let minTrim = newVal.trimmingCharacters(in: .whitespaces)
                var minVal = minTrim
                var maxVal = maxQuantity.trimmingCharacters(in: .whitespaces)
                if minVal.isEmpty && maxVal.isEmpty {
                    minVal = "0"
                    maxVal = "0"
                } else if minVal.isEmpty {
                    minVal = maxVal
                } else if maxVal.isEmpty {
                    maxVal = minVal
                }
                // write back normalized values to state and model
                minQuantity = minVal
                maxQuantity = maxVal
                ingredient.minQuantity = minVal
                ingredient.maxQuantity = maxVal
            }
            .onChange(of: maxQuantity) { newVal in
                let maxTrim = newVal.trimmingCharacters(in: .whitespaces)
                var maxVal = maxTrim
                var minVal = minQuantity.trimmingCharacters(in: .whitespaces)
                if minVal.isEmpty && maxVal.isEmpty {
                    minVal = "0"
                    maxVal = "0"
                } else if maxVal.isEmpty {
                    maxVal = minVal
                } else if minVal.isEmpty {
                    minVal = maxVal
                }
                minQuantity = minVal
                maxQuantity = maxVal
                ingredient.minQuantity = minVal
                ingredient.maxQuantity = maxVal
            }
            
            // Unit field
            TextField("Unit", text: $ingredient.unit)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 80)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

struct IngredientDisplay: View {
    let text: String
    var isHidden: Bool = false
    
    // Clean the text by removing asterisks
    var cleanedText: String {
        // Remove asterisks from the text
        var cleaned = text.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        HStack {
            Circle()
                .fill(isHidden ? Color.pink.opacity(0.2) : Color.green.opacity(0.2))
                .frame(width: 8, height: 8)
            
            Text(cleanedText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
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
                Image(systemName: icon)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            if let action = action, let actionIcon = actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .foregroundColor(color)
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
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(GraphicalDatePickerStyle())
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Button(action: retry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}
