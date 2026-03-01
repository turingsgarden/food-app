import SwiftUI
import Combine

// MARK: - Quantity-Only Editable Row for Meal Editing
struct QuantityOnlyIngredientRow: View {
    @Binding var ingredient: EditableIngredient
    let onDelete: (() -> Void)?
    @State private var minText: String = ""
    @State private var maxText: String = ""
    @FocusState private var isFocused: Bool
    
    init(ingredient: Binding<EditableIngredient>, onDelete: (() -> Void)? = nil) {
        self._ingredient = ingredient
        self.onDelete = onDelete
        // Initialize min/max from existing quantity (support "min-max" or single value)
        let qty = ingredient.wrappedValue.quantity.trimmingCharacters(in: .whitespaces)
        var initMin = ""
        var initMax = ""
        if qty.contains("-") {
            let parts = qty.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                initMin = String(parts[0])
                initMax = String(parts[1])
            } else {
                initMin = qty
                initMax = qty
            }
        } else if !qty.isEmpty {
            initMin = qty
            initMax = qty
        }
        self._minText = State(initialValue: initMin)
        self._maxText = State(initialValue: initMax)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Delete button (optional - only for new ingredients)
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
            
            // Name field (read-only)
            HStack {
                Text(ingredient.name)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            
            // Quantity: edit min and max separately with fixed dash between
            HStack(spacing: 8) {
                TextField("min", text: $minText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .focused($isFocused)
                    .onChange(of: minText) { oldValue in
                        var filtered = minText.filter { $0.isNumber || $0 == "." }
                        let dotCount = filtered.filter { $0 == "." }.count
                        if dotCount > 1 { minText = oldValue; return }
                        if filtered.first == "." { filtered = "0." + filtered.dropFirst() }
                        if filtered != minText { minText = filtered }
                        var minVal = filtered.trimmingCharacters(in: .whitespaces)
                        var maxVal = maxText.trimmingCharacters(in: .whitespaces)
                        if minVal.isEmpty && maxVal.isEmpty { minVal = "0"; maxVal = "0" }
                        else if minVal.isEmpty { minVal = maxVal }
                        else if maxVal.isEmpty { maxVal = minVal }
                        minText = minVal
                        maxText = maxVal
                        ingredient.minQuantity = minVal
                        ingredient.maxQuantity = maxVal
                    }

                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.white)

                TextField("max", text: $maxText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .onChange(of: maxText) { oldValue in
                        var filtered = maxText.filter { $0.isNumber || $0 == "." }
                        let dotCount = filtered.filter { $0 == "." }.count
                        if dotCount > 1 { maxText = oldValue; return }
                        if filtered.first == "." { filtered = "0." + filtered.dropFirst() }
                        if filtered != maxText { maxText = filtered }
                        var maxVal = filtered.trimmingCharacters(in: .whitespaces)
                        var minVal = minText.trimmingCharacters(in: .whitespaces)
                        if minVal.isEmpty && maxVal.isEmpty { minVal = "0"; maxVal = "0" }
                        else if maxVal.isEmpty { maxVal = minVal }
                        else if minVal.isEmpty { minVal = maxVal }
                        minText = minVal
                        maxText = maxVal
                        ingredient.minQuantity = minVal
                        ingredient.maxQuantity = maxVal
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isFocused = false
                            }
                        }
                    }
            }
            
            // Unit field (read-only)
            Text(ingredient.unit)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 60)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Numeric Text Field Modifier
struct NumericTextFieldModifier: ViewModifier {
    @Binding var text: String
    let allowDecimal: Bool
    
    func body(content: Content) -> some View {
        content
            .onReceive(Just(text)) { newValue in
                var filtered = newValue.filter {
                    $0.isNumber || (allowDecimal && $0 == ".")
                }
                
                // Ensure only one decimal point
                if allowDecimal {
                    let parts = filtered.split(separator: ".")
                    if parts.count > 2 {
                        filtered = String(parts[0]) + "." + parts[1...].joined()
                    }
                }
                
                if filtered != newValue {
                    text = filtered
                }
            }
    }
}

extension View {
    func numericOnly(_ text: Binding<String>, allowDecimal: Bool = true) -> some View {
        self.modifier(NumericTextFieldModifier(text: text, allowDecimal: allowDecimal))
    }
}
