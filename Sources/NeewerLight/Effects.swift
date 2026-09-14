//  Effects.swift — the HS60C's 17 built-in scene effects and their parameters.
//
//  Each effect takes a different ordered payload; `Effect.payload(from:)` serialises
//  the shared parameter set in the order that effect expects.

import Foundation

enum FXParam: String, CaseIterable {
    case brightness, brightness2, kelvin, kelvin2, gm, hue, hue2, saturation, speed, sparks, colorway

    var label: String {
        switch self {
        case .brightness: return "Brightness"
        case .brightness2: return "Brightness (low)"
        case .kelvin: return "Temperature"
        case .kelvin2: return "Temperature (to)"
        case .gm: return "G/M shift"
        case .hue: return "Hue"
        case .hue2: return "Hue (to)"
        case .saturation: return "Saturation"
        case .speed: return "Speed"
        case .sparks: return "Sparks"
        case .colorway: return "Colours"
        }
    }
}

/// Mutable parameter bag shared across effects; each effect reads only what it needs.
struct FXValues {
    var brightness = 80
    var brightness2 = 20
    var kelvin = 56
    var kelvin2 = 32
    var gm = 50
    var hue = 0
    var hue2 = 240
    var saturation = 100
    var speed = 5
    var sparks = 5
    var colorway = 0
}

struct Effect: Identifiable, Hashable {
    let id: UInt8
    let name: String
    let symbol: String
    let params: [FXParam]
    /// Labels for the `colorway` parameter, when the effect has one.
    var colorways: [String] = []

    static func == (a: Effect, b: Effect) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func payload(from v: FXValues) -> [UInt8] {
        var out: [UInt8] = []
        for p in params {
            switch p {
            case .brightness: out.append(UInt8(v.brightness.clamped(0, 100)))
            case .brightness2: out.append(UInt8(v.brightness2.clamped(0, 100)))
            case .kelvin: out.append(UInt8(v.kelvin.clamped(29, 70)))
            case .kelvin2: out.append(UInt8(v.kelvin2.clamped(29, 70)))
            case .gm: out.append(UInt8(v.gm.clamped(0, 100)))
            case .saturation: out.append(UInt8(v.saturation.clamped(0, 100)))
            case .speed: out.append(UInt8(v.speed.clamped(1, 10)))
            case .sparks: out.append(UInt8(v.sparks.clamped(1, 10)))
            case .colorway: out.append(UInt8(v.colorway.clamped(0, max(0, colorways.count - 1))))
            case .hue:
                let h = v.hue.clamped(0, 360)
                out.append(UInt8(h & 0xFF)); out.append(UInt8((h >> 8) & 0xFF))
            case .hue2:
                let h = v.hue2.clamped(0, 360)
                out.append(UInt8(h & 0xFF)); out.append(UInt8((h >> 8) & 0xFF))
            }
        }
        return out
    }

    func range(for p: FXParam) -> ClosedRange<Double> {
        switch p {
        case .brightness, .brightness2, .saturation, .gm: return 0...100
        case .kelvin, .kelvin2: return 29...70
        case .hue, .hue2: return 0...360
        case .speed, .sparks: return 1...10
        case .colorway: return 0...Double(max(0, colorways.count - 1))
        }
    }

    static let all: [Effect] = [
        Effect(id: 0x01, name: "Lightning", symbol: "bolt.fill",
               params: [.brightness, .kelvin, .speed]),
        Effect(id: 0x02, name: "Paparazzi", symbol: "camera.fill",
               params: [.brightness, .kelvin, .gm, .speed]),
        Effect(id: 0x03, name: "Defective Bulb", symbol: "lightbulb.slash.fill",
               params: [.brightness, .kelvin, .gm, .speed]),
        Effect(id: 0x04, name: "Explosion", symbol: "burst.fill",
               params: [.brightness, .kelvin, .gm, .speed, .sparks]),
        Effect(id: 0x05, name: "Welding", symbol: "flame.fill",
               params: [.brightness, .brightness2, .kelvin, .gm, .speed]),
        Effect(id: 0x06, name: "CCT Flash", symbol: "sun.max.fill",
               params: [.brightness, .kelvin, .gm, .speed]),
        Effect(id: 0x07, name: "Hue Flash", symbol: "paintpalette.fill",
               params: [.brightness, .hue, .saturation, .speed]),
        Effect(id: 0x08, name: "CCT Pulse", symbol: "waveform.path",
               params: [.brightness, .kelvin, .gm, .speed]),
        Effect(id: 0x09, name: "Hue Pulse", symbol: "waveform.path.ecg",
               params: [.brightness, .hue, .saturation, .speed]),
        Effect(id: 0x0A, name: "Cop Car", symbol: "car.fill",
               params: [.brightness, .colorway, .speed],
               colorways: ["Red", "Blue", "Red and Blue", "White and Blue", "Red Blue White"]),
        Effect(id: 0x0B, name: "Candlelight", symbol: "flame",
               params: [.brightness, .brightness2, .kelvin, .gm, .speed, .sparks]),
        Effect(id: 0x0C, name: "Hue Loop", symbol: "arrow.triangle.2.circlepath",
               params: [.brightness, .hue, .hue2, .speed]),
        Effect(id: 0x0D, name: "CCT Loop", symbol: "thermometer.medium",
               params: [.brightness, .kelvin, .kelvin2, .speed]),
        Effect(id: 0x0E, name: "Intensity Loop", symbol: "circle.lefthalf.filled",
               params: [.brightness, .brightness2, .hue, .speed]),
        Effect(id: 0x0F, name: "TV Screen", symbol: "tv.fill",
               params: [.brightness, .kelvin, .gm, .speed]),
        Effect(id: 0x10, name: "Firework", symbol: "sparkles",
               params: [.brightness, .colorway, .speed, .sparks],
               colorways: ["Single colour", "Colour", "Combined"]),
        Effect(id: 0x11, name: "Party", symbol: "party.popper.fill",
               params: [.brightness, .colorway, .speed],
               colorways: ["Single colour", "Colour", "Combined"])
    ]
}
