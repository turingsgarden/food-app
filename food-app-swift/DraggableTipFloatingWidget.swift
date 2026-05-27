//
//  DraggableTipFloatingWidget.swift
//  food-app-swift
//
//  Minimized Daily Tip chip: draggable with magnetic snap to nearest screen edge.
//

import SwiftUI

struct DraggableTipFloatingWidget: View {
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

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let bounds = bounds(in: geo.size, safe: safe)

            chip
                .contentShape(Capsule())
                .position(
                    x: clampedX(centerX + dragOffset.width, bounds: bounds),
                    y: clampedY(centerY + dragOffset.height, bounds: bounds)
                )
                .onTapGesture(count: 2) {
                    guard Date() >= ignoreTapsUntil else { return }
                    restoreBanner()
                }
                .gesture(
                    DragGesture(minimumDistance: dragStartThreshold)
                        .onChanged { value in
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
}

#Preview {
    ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()
        DraggableTipFloatingWidget(onRestore: {})
    }
}
