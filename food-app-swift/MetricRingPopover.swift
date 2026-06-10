import SwiftUI

// MARK: - Metric Ring Popover

/// Compact ring entry that expands into metric focus circles.
struct MetricRingPopover: View {
    @EnvironmentObject var themeManager: ThemeManager
    let evidence: [DailyMetricEvidence]
    @Binding var selectedMetricID: String?
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ringEntryButton
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            metricRingSheet
        }
    }

    private var ringEntryButton: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )

            if !evidence.isEmpty {
                Text("\(evidence.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Color.red.opacity(0.9)))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel("Health metrics")
    }

    private var metricRingSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a health focus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)

                overallCircle

                if evidence.isEmpty {
                    Text("No flagged metrics yet. Showing your overall plan.")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.current.secondaryText)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(evidence) { item in
                            metricCircle(item)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(themeManager.current.background.ignoresSafeArea())
            .navigationTitle("Health Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var overallCircle: some View {
        Button {
            selectedMetricID = nil
            isPresented = false
        } label: {
            focusCircle(
                title: "Overall",
                subtitle: "Combined plan",
                color: .orange,
                isSelected: selectedMetricID == nil
            )
        }
        .buttonStyle(.plain)
    }

    private func metricCircle(_ item: DailyMetricEvidence) -> some View {
        Button {
            selectedMetricID = item.id
            isPresented = false
        } label: {
            focusCircle(
                title: item.shortTabTitle,
                subtitle: item.status.capitalized,
                color: item.statusColor,
                isSelected: selectedMetricID == item.id
            )
        }
        .buttonStyle(.plain)
    }

    private func focusCircle(title: String, subtitle: String, color: Color, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color.opacity(isSelected ? 0.28 : 0.14))
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(isSelected ? color : color.opacity(0.35), lineWidth: isSelected ? 3 : 1.5)
                )
                .overlay(
                    Text(String(title.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(color)
                )

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(themeManager.current.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Evidence Helpers

extension DailyMetricEvidence {
    var shortTabTitle: String {
        if metric.count <= 14 { return metric }
        if metric.lowercased().contains("blood sugar") || metric.lowercased().contains("glucose") {
            return "Blood Sugar"
        }
        if metric.lowercased().contains("blood pressure") || metric.lowercased().contains("systolic") {
            return "Blood Pressure"
        }
        if metric.lowercased().contains("cholesterol") || metric.lowercased().contains("lipid") {
            return "Cholesterol"
        }
        if metric.lowercased().contains("bmi") || metric.lowercased().contains("weight") {
            return "Weight"
        }
        return metric
    }

    var statusColor: Color {
        switch status.lowercased() {
        case "high", "elevated":
            return .red
        case "borderline", "low":
            return .orange
        default:
            return .gray
        }
    }
}
