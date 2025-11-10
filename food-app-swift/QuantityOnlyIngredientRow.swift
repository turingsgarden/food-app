import SwiftUI
import Combine

// MARK: - Quantity-Only Editable Row for Meal Editing
struct QuantityOnlyIngredientRow: View {
    @Binding var ingredient: EditableIngredient
    let onDelete: (() -> Void)?
    @State private var quantityText: String = ""
    @FocusState private var isFocused: Bool
    
    init(ingredient: Binding<EditableIngredient>, onDelete: (() -> Void)? = nil) {
        self._ingredient = ingredient
        self.onDelete = onDelete
        self._quantityText = State(initialValue: ingredient.wrappedValue.quantity)
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
            
            // Quantity field (editable with numeric validation)
            TextField("0", text: $quantityText)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(width: 70)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .onChange(of: quantityText) { oldValue, newValue in
                    // Allow only numbers and decimal point
                    let filtered = newValue.filter { $0.isNumber || $0 == "." }
                    
                    // Ensure only one decimal point
                    let decimalCount = filtered.filter { $0 == "." }.count
                    if decimalCount > 1 {
                        quantityText = oldValue
                        return
                    }
                    
                    // Prevent starting with decimal point
                    if filtered.first == "." {
                        quantityText = "0."
                        return
                    }
                    
                    // Update if valid
                    if filtered != newValue {
                        quantityText = filtered
                    } else {
                        ingredient.quantity = filtered.isEmpty ? "0" : filtered
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
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
