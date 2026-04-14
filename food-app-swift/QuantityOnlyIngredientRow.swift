import SwiftUI
import Combine

struct QuantityOnlyIngredientRow: View {
    @Binding var ingredient: EditableIngredient
    let onDelete: (() -> Void)?

    @State private var localQuantity: String = ""
    @FocusState private var isFocused: Bool

    init(ingredient: Binding<EditableIngredient>, onDelete: (() -> Void)? = nil) {
        self._ingredient = ingredient
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: 12) {
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red).font(.title3)
                }
            }

            // Name (read-only)
            HStack {
                Text(ingredient.name)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            )

            
            TextField("0", text: $localQuantity)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(width: 70)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1))
                )
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .onAppear {
                    localQuantity = ingredient.quantity
                }
               
                .onChange(of: localQuantity) { _, newValue in
                    let sanitized = sanitize(newValue)
                  
                    if sanitized != newValue {
                        localQuantity = sanitized
                    }
                    ingredient.quantity = sanitized.isEmpty ? "0" : sanitized
                }
          
                .onChange(of: ingredient.quantity) { _, newValue in
                    if !isFocused && newValue != localQuantity {
                        localQuantity = newValue
                    }
                }

            // Unit (read-only)
            Text(displayUnit)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 60)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                )
        }
    }


    private func sanitize(_ value: String) -> String {
        let filtered = value.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            return String(parts[0]) + "." + parts[1...].joined(separator: "")
        }
        return filtered
    }

    private var displayUnit: String {
        let u = ingredient.unit.trimmingCharacters(in: .whitespaces)
        if Double(u) != nil || u.isEmpty { return guessUnit(for: ingredient.name) }
        return u
    }

    private func guessUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("bread") || n.contains("egg") || n.contains("slice") { return "pcs" }
        if n.contains("salt") || n.contains("pepper") || n.contains("spice") || n.contains("powder") { return "tsp" }
        if n.contains("oil") || n.contains("sauce") || n.contains("milk") { return "ml" }
        return "g"
    }
}

struct NumericTextFieldModifier: ViewModifier {
    @Binding var text: String
    let allowDecimal: Bool
    func body(content: Content) -> some View {
        content.onReceive(Just(text)) { newValue in
            var filtered = newValue.filter { $0.isNumber || (allowDecimal && $0 == ".") }
            if allowDecimal {
                let parts = filtered.split(separator: ".")
                if parts.count > 2 { filtered = String(parts[0]) + "." + parts[1...].joined() }
            }
            if filtered != newValue { text = filtered }
        }
    }
}

extension View {
    func numericOnly(_ text: Binding<String>, allowDecimal: Bool = true) -> some View {
        self.modifier(NumericTextFieldModifier(text: text, allowDecimal: allowDecimal))
    }
}
