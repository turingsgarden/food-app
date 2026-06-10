//
//  DraggableTipFloatingWidget.swift
//  food-app-swift
//
//  Minimized Daily Tip chip: draggable with magnetic snap to nearest screen edge.
//

import SwiftUI

struct DraggableTipFloatingWidget: View {
    var showHint: Bool = false
    var onHintSeen: () -> Void = {}
    var onRestore: () -> Void

    private let storageXKey = "daily_tip_floating_norm_x"
    private let storageYKey = "daily_tip_floating_norm_y"

    private let chipSize = CGSize(width: 72, height: 34)
    private let edgeMargin: CGFloat = 14
    /// Keep chip below status bar / clock (iOS often does not deliver touches there).
    private let topClearanceBelowSafeArea: CGFloat = 56
    private let bottomReserved: CGFloat = 110
    /// Drag only starts after this distance so taps / double-taps are not swallowed.
    private let dragStartThreshold: CGFloat = 14

    @State private var centerX: CGFloat = 0
    @State private var centerY: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var didLoadPosition = false
    @State private var isDragging = false
    /// Ignore taps briefly after a drag so lift-off is not treated as double-tap.
    @State private var ignoreTapsUntil = Date.distantPast
    @State private var isHintVisible = false
    @State private var hintDismissed = false

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let bounds = bounds(in: geo.size, safe: safe)
            let currentCenter = CGPoint(
                x: clampedX(centerX + dragOffset.width, bounds: bounds),
                y: clampedY(centerY + dragOffset.height, bounds: bounds)
            )
            let hintOnLeft = currentCenter.x > geo.size.width / 2

            ZStack {
                chip
                    .contentShape(Capsule())
                    .position(x: currentCenter.x, y: currentCenter.y)

                if isHintVisible {
                    hintBubble(pointingLeft: hintOnLeft)
                        .position(
                            x: currentCenter.x + (hintOnLeft ? -105 : 105),
                            y: currentCenter.y - 2
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .zIndex(2)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(count: 2) {
                    guard Date() >= ignoreTapsUntil else { return }
                    dismissHintIfNeeded()
                    restoreBanner()
                }
                .gesture(
                    DragGesture(minimumDistance: dragStartThreshold)
                        .onChanged { value in
                            dismissHintIfNeeded()
                            if !isDragging { isDragging = true }
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            isDragging = false
                            ignoreTapsUntil = Date().addingTimeInterval(0.35)

                            let proposed = CGPoint(
                                x: centerX + value.translation.width,
                                y: centerY + value.translation.height
                            )
                            let snapped = snapToNearestEdge(
                                center: proposed,
                                bounds: bounds
                            )

                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                centerX = snapped.x
                                centerY = snapped.y
                                dragOffset = .zero
                            }

                            persistPosition(
                                center: snapped,
                                containerSize: geo.size,
                                safe: safe,
                                bounds: bounds
                            )
                        }
                )
                .scaleEffect(isDragging ? 1.06 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
                .onAppear {
                    guard !didLoadPosition else { return }
                    loadInitialPosition(containerSize: geo.size, safe: safe, bounds: bounds)
                    didLoadPosition = true
                    showHintIfNeeded()
                }
        }
        .ignoresSafeArea()
    }

    private var chip: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Tip")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.white)
        .frame(width: chipSize.width, height: chipSize.height)
        .background(Capsule().fill(Color.orange))
        .shadow(color: .black.opacity(isDragging ? 0.22 : 0.14), radius: isDragging ? 8 : 4, x: 0, y: 3)
    }

    private func restoreBanner() {
        dragOffset = .zero
        isDragging = false
        onRestore()
    }

    private func showHintIfNeeded() {
        guard showHint, !hintDismissed else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            isHintVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            dismissHintIfNeeded()
        }
    }

    private func dismissHintIfNeeded() {
        guard isHintVisible || (showHint && !hintDismissed) else { return }
        hintDismissed = true
        withAnimation(.easeOut(duration: 0.2)) {
            isHintVisible = false
        }
        onHintSeen()
    }

    private struct PositionBounds {
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
    }

    private func bounds(in size: CGSize, safe: EdgeInsets) -> PositionBounds {
        let halfW = chipSize.width / 2
        let halfH = chipSize.height / 2
        return PositionBounds(
            minX: edgeMargin + halfW,
            maxX: size.width - edgeMargin - halfW,
            minY: safe.top + topClearanceBelowSafeArea + halfH,
            maxY: size.height - safe.bottom - bottomReserved - halfH
        )
    }

    private func clampedX(_ x: CGFloat, bounds: PositionBounds) -> CGFloat {
        min(max(x, bounds.minX), bounds.maxX)
    }

    private func clampedY(_ y: CGFloat, bounds: PositionBounds) -> CGFloat {
        min(max(y, bounds.minY), bounds.maxY)
    }

    /// Snap to the nearest screen edge (left / right / top / bottom), keeping Y or X free along that edge.
    private func snapToNearestEdge(center: CGPoint, bounds: PositionBounds) -> CGPoint {
        let x = clampedX(center.x, bounds: bounds)
        let y = clampedY(center.y, bounds: bounds)

        let distLeft = x - bounds.minX
        let distRight = bounds.maxX - x
        let distTop = y - bounds.minY
        let distBottom = bounds.maxY - y

        let minDist = min(distLeft, distRight, distTop, distBottom)

        var snappedX = x
        var snappedY = y

        if minDist == distLeft {
            snappedX = bounds.minX
        } else if minDist == distRight {
            snappedX = bounds.maxX
        } else if minDist == distTop {
            snappedY = bounds.minY
        } else {
            snappedY = bounds.maxY
        }

        return CGPoint(x: snappedX, y: snappedY)
    }

    private func defaultPosition(bounds: PositionBounds) -> CGPoint {
        CGPoint(x: bounds.maxX, y: bounds.minY + 36)
    }

    private func loadInitialPosition(containerSize: CGSize, safe: EdgeInsets, bounds: PositionBounds) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: storageXKey) != nil,
           defaults.object(forKey: storageYKey) != nil {
            let normX = defaults.double(forKey: storageXKey)
            let normY = defaults.double(forKey: storageYKey)

            if normY < 0.12 {
                applyDefaultPosition(bounds: bounds)
                return
            }

            centerX = CGFloat(normX) * containerSize.width
            centerY = safe.top + CGFloat(normY) * (containerSize.height - safe.top - safe.bottom)
            centerX = clampedX(centerX, bounds: bounds)
            centerY = clampedY(centerY, bounds: bounds)

            if centerY <= safe.top + topClearanceBelowSafeArea {
                applyDefaultPosition(bounds: bounds)
            }
            return
        }

        applyDefaultPosition(bounds: bounds)
    }

    private func applyDefaultPosition(bounds: PositionBounds) {
        let def = defaultPosition(bounds: bounds)
        centerX = def.x
        centerY = def.y
    }

    private func persistPosition(
        center: CGPoint,
        containerSize: CGSize,
        safe: EdgeInsets,
        bounds: PositionBounds
    ) {
        let safeCenter = CGPoint(
            x: clampedX(center.x, bounds: bounds),
            y: clampedY(center.y, bounds: bounds)
        )
        let normX = Double(safeCenter.x / max(containerSize.width, 1))
        let usableHeight = max(containerSize.height - safe.top - safe.bottom, 1)
        let normY = Double((safeCenter.y - safe.top) / usableHeight)
        UserDefaults.standard.set(normX, forKey: storageXKey)
        UserDefaults.standard.set(normY, forKey: storageYKey)
    }

    @ViewBuilder
    private func hintBubble(pointingLeft: Bool) -> some View {
        HStack(spacing: 0) {
            if pointingLeft {
                hintContent
                triangle(directionLeft: true)
            } else {
                triangle(directionLeft: false)
                hintContent
            }
        }
    }

    private var hintContent: some View {
        Text("Double-tap to open tip")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(themeText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(themeStroke, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)
    }

    private func triangle(directionLeft: Bool) -> some View {
        TriangleShape(pointingLeft: directionLeft)
            .fill(themeFill)
            .frame(width: 8, height: 10)
            .overlay(
                TriangleShape(pointingLeft: directionLeft)
                    .stroke(themeStroke, lineWidth: 1)
            )
            .offset(x: directionLeft ? -0.5 : 0.5)
    }

    private var themeFill: Color {
        Color(UIColor.systemBackground)
    }

    private var themeStroke: Color {
        Color.orange.opacity(0.28)
    }

    private var themeText: Color {
        Color(UIColor.label)
    }
}

private struct TriangleShape: Shape {
    let pointingLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingLeft {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()
        DraggableTipFloatingWidget(showHint: true, onHintSeen: {}, onRestore: {})
    }
}
