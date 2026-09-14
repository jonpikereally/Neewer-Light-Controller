//  GradientSlider.swift — a slider whose track shows the value it controls.

import SwiftUI

struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var gradient: LinearGradient
    var step: Double = 1
    /// Upper bound the knob won't cross. The track beyond it is shaded out.
    var limit: Double?

    private func fraction(_ v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? ((v - range.lowerBound) / span).clamped(0, 1) : 0
    }

    private var ceiling: Double { min(limit ?? range.upperBound, range.upperBound) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 18
            let travel = max(0, w - knob)
            let limitFraction = fraction(ceiling)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(gradient)
                    if limitFraction < 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .padding(.leading, w * limitFraction)
                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .frame(width: 1.5)
                            .padding(.leading, w * limitFraction)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: travel * fraction(min(value, ceiling)))
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = ((g.location.x - knob / 2) / max(travel, 1)).clamped(0, 1)
                        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        let snapped = (raw / step).rounded() * step
                        value = snapped.clamped(range.lowerBound, ceiling)
                    }
            )
        }
        .frame(height: 18)
    }
}

/// Label / value row above a slider.
struct SliderRow<Content: View>: View {
    let title: String
    let readout: String
    @ViewBuilder var slider: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(readout)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            slider
        }
    }
}

enum Palette {
    /// Approximate visual ramp for 2700 K → 6500 K.
    static let cct = LinearGradient(
        colors: [Color(red: 1.00, green: 0.68, blue: 0.38),
                 Color(red: 1.00, green: 0.85, blue: 0.70),
                 Color(red: 1.00, green: 1.00, blue: 1.00),
                 Color(red: 0.83, green: 0.90, blue: 1.00)],
        startPoint: .leading, endPoint: .trailing)

    static let hue = LinearGradient(
        colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
            .map { Color(hue: $0, saturation: 1, brightness: 1) },
        startPoint: .leading, endPoint: .trailing)

    static let greenMagenta = LinearGradient(
        colors: [Color(red: 0.35, green: 0.95, blue: 0.45), .white,
                 Color(red: 1.00, green: 0.40, blue: 0.85)],
        startPoint: .leading, endPoint: .trailing)

    static func brightness(_ tint: Color = .white) -> LinearGradient {
        LinearGradient(colors: [.black.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing)
    }

    static func saturation(_ hue: Double) -> LinearGradient {
        LinearGradient(colors: [.white, Color(hue: hue / 360, saturation: 1, brightness: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    static let neutral = LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor],
                                        startPoint: .leading, endPoint: .trailing)
}
