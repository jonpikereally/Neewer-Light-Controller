//  ContentView.swift — the menu bar popover.

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var light: LightController
    @ObservedObject var updater: Updater
    @StateObject private var loginItem = LoginItem()
    @State private var showLog = false
    @State private var contentHeight: CGFloat = 0

    // A popover taller than the space under the menu bar gets shoved up over it,
    // so cap it at the screen and scroll the rest.
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 40
    }

    var body: some View {
        ScrollView {
            controls
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeightKey.self, value: geo.size.height)
                })
        }
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        .frame(width: 340, height: min(max(contentHeight, 1), maxHeight))
    }

    private struct HeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if case .needsMAC = light.status {
                macPrompt
                Divider()
            }

            powerRow

            Picker("", selection: $light.mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch light.mode {
                case .cct: whiteControls
                case .colour: colourControls
                case .scene: sceneControls
                }
            }
            .disabled(!light.isOn)
            .opacity(light.isOn ? 1 : 0.4)

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(light.status.isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(light.status.text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Neewer HS60C")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { light.rescan() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Scan again")
        }
    }

    private var macPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("macOS didn't report the light's Bluetooth address.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("AA:BB:CC:DD:EE:FF", text: $light.manualMAC)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11).monospaced())
        }
    }

    // MARK: - Power

    private var powerRow: some View {
        HStack {
            Label("Power", systemImage: light.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle("", isOn: $light.isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .disabled(!light.status.isReady)
    }

    // MARK: - White

    private var whiteControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(title: "Brightness", readout: brightnessReadout(light.brightness)) {
                GradientSlider(value: $light.brightness, range: 0...100,
                               gradient: Palette.brightness(), limit: light.maxBrightness)
            }
            SliderRow(title: "Temperature", readout: "\(Int(light.kelvin) * 100) K") {
                GradientSlider(value: $light.kelvin, range: 27...65, gradient: Palette.cct)
            }
            SliderRow(title: "Green / Magenta", readout: gmReadout) {
                GradientSlider(value: $light.gm, range: -50...50, gradient: Palette.greenMagenta)
            }
            presetRow
        }
    }

    private func brightnessReadout(_ v: Double) -> String {
        let pct = "\(Int(v))%"
        return v >= light.maxBrightness && light.maxBrightness < 100 ? "\(pct) · max" : pct
    }

    private var gmReadout: String {
        let v = Int(light.gm)
        return v == 0 ? "0" : (v > 0 ? "+\(v)" : "\(v)")
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            preset("Candle", k: 27, b: 45)
            preset("Tungsten", k: 32, b: 80)
            preset("Neutral", k: 45, b: 85)
            preset("Daylight", k: 56, b: 100)
            preset("Shade", k: 65, b: 90)
        }
    }

    private func preset(_ name: String, k: Double, b: Double) -> some View {
        Button(name) {
            light.gm = 0
            light.kelvin = k
            light.brightness = min(b, light.maxBrightness)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 10))
    }

    // MARK: - Colour

    private var colourControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hue: light.hue / 360,
                                saturation: light.saturation / 100,
                                brightness: max(0.25, light.colourBrightness / 100)))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(light.hue))°  ·  \(Int(light.saturation))%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text("Hue and saturation")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            SliderRow(title: "Hue", readout: "\(Int(light.hue))°") {
                GradientSlider(value: $light.hue, range: 0...360, gradient: Palette.hue)
            }
            SliderRow(title: "Saturation", readout: "\(Int(light.saturation))%") {
                GradientSlider(value: $light.saturation, range: 0...100,
                               gradient: Palette.saturation(light.hue))
            }
            SliderRow(title: "Brightness", readout: brightnessReadout(light.colourBrightness)) {
                GradientSlider(value: $light.colourBrightness, range: 0...100,
                               gradient: Palette.brightness(
                                Color(hue: light.hue / 360, saturation: light.saturation / 100, brightness: 1)),
                               limit: light.maxBrightness)
            }
            swatchRow
        }
    }

    private var swatchRow: some View {
        HStack(spacing: 6) {
            ForEach([0, 30, 60, 120, 180, 210, 270, 320], id: \.self) { h in
                Button {
                    light.saturation = 100
                    light.hue = Double(h)
                } label: {
                    Circle()
                        .fill(Color(hue: Double(h) / 360, saturation: 1, brightness: 1))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Scene

    private var sceneControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $light.effect) {
                ForEach(Effect.all) { fx in
                    Label(fx.name, systemImage: fx.symbol).tag(fx)
                }
            }
            .labelsHidden()

            ForEach(light.effect.params, id: \.self) { param in
                paramRow(param)
            }
        }
    }

    @ViewBuilder
    private func paramRow(_ p: FXParam) -> some View {
        let fx = light.effect
        if p == .colorway {
            Picker(p.label, selection: binding(p)) {
                ForEach(Array(fx.colorways.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(Double(i))
                }
            }
            .font(.system(size: 11))
        } else {
            SliderRow(title: p.label, readout: readout(p)) {
                GradientSlider(value: binding(p), range: fx.range(for: p), gradient: gradient(p),
                               limit: (p == .brightness || p == .brightness2) ? light.maxBrightness : nil)
            }
        }
    }

    private func gradient(_ p: FXParam) -> LinearGradient {
        switch p {
        case .kelvin, .kelvin2: return Palette.cct
        case .hue, .hue2: return Palette.hue
        case .gm: return Palette.greenMagenta
        case .brightness, .brightness2: return Palette.brightness()
        case .saturation: return Palette.saturation(Double(light.fx.hue))
        default: return Palette.neutral
        }
    }

    private func readout(_ p: FXParam) -> String {
        let v = Int(binding(p).wrappedValue)
        switch p {
        case .kelvin, .kelvin2: return "\(v * 100) K"
        case .hue, .hue2: return "\(v)°"
        case .brightness, .brightness2, .saturation, .gm: return "\(v)%"
        default: return "\(v)"
        }
    }

    private func binding(_ p: FXParam) -> Binding<Double> {
        Binding(
            get: {
                let v = light.fx
                switch p {
                case .brightness: return Double(v.brightness)
                case .brightness2: return Double(v.brightness2)
                case .kelvin: return Double(v.kelvin)
                case .kelvin2: return Double(v.kelvin2)
                case .gm: return Double(v.gm)
                case .hue: return Double(v.hue)
                case .hue2: return Double(v.hue2)
                case .saturation: return Double(v.saturation)
                case .speed: return Double(v.speed)
                case .sparks: return Double(v.sparks)
                case .colorway: return Double(v.colorway)
                }
            },
            set: { newValue in
                let n = Int(newValue.rounded())
                switch p {
                case .brightness: light.fx.brightness = n
                case .brightness2: light.fx.brightness2 = n
                case .kelvin: light.fx.kelvin = n
                case .kelvin2: light.fx.kelvin2 = n
                case .gm: light.fx.gm = n
                case .hue: light.fx.hue = n
                case .hue2: light.fx.hue2 = n
                case .saturation: light.fx.saturation = n
                case .speed: light.fx.speed = n
                case .sparks: light.fx.sparks = n
                case .colorway: light.fx.colorway = n
                }
            })
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SliderRow(title: "Brightness limit", readout: "\(Int(light.maxBrightness))%") {
                GradientSlider(value: $light.maxBrightness, range: 10...100,
                               gradient: Palette.brightness(.orange), step: 5)
            }
            Text("Caps every brightness the app sends, so a weak supply can't brown the light out.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled || loginItem.needsApproval },
                set: { loginItem.set($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onAppear { loginItem.refresh() }
            if loginItem.needsApproval {
                Button("Allow in System Settings › Login Items") { loginItem.openSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
            if let error = loginItem.error {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Check the Errors section of the README for what this code means.")
            }

            updateRow

            HStack {
                Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
            if showLog {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(light.log.suffix(40).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Updates

    private var updateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(BuildInfo.current.summary)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                switch updater.state {
                case .available(let release):
                    Button("Install update") { updater.install(release) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                case .checking, .installing:
                    ProgressView().controlSize(.mini)
                default:
                    Button("Check for updates") { updater.check() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            switch updater.state {
            case .upToDate:
                Text("You're on the latest version.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            case .available(let release):
                Text("New: \(release.build.map { "build \($0) · " } ?? "")\(release.message)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            case .installing(let step):
                Text(step)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            case .failed(let error):
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Check the Errors section of the README for what this code means.")
            case .idle, .checking:
                EmptyView()
            }
        }
    }
}
