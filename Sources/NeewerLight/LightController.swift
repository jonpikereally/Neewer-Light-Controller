//  LightController.swift — discovery, connection and command dispatch for the HS60C.

import Combine
import CoreBluetooth
import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case cct = "White"
    case colour = "Colour"
    case scene = "Scene"
    var id: String { rawValue }
}

enum Status: Equatable {
    case bluetoothOff
    case unauthorized
    case scanning
    case connecting(String)
    case connected(String)
    case needsMAC(String)
    case disconnected

    var text: String {
        switch self {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .scanning: return "Looking for your light…"
        case .connecting(let n): return "Connecting to \(n)…"
        case .connected(let n): return n
        case .needsMAC(let n): return "\(n) — MAC address needed"
        case .disconnected: return "Disconnected"
        }
    }

    var isReady: Bool { if case .connected = self { return true }; return false }
}

final class LightController: NSObject, ObservableObject {

    @Published private(set) var status: Status = .scanning
    @Published private(set) var log: [String] = []

    @Published var isOn = true { didSet { if isOn != oldValue { sendPower() } } }
    @Published var mode: Mode = .cct { didSet { if mode != oldValue { pushCurrentMode() } } }

    /// Hard ceiling on every brightness value the app will send. The HS60C browns out
    /// and cuts power if the supply can't deliver what the panel asks for, and recovering
    /// needs a physical power cycle — so this is enforced on the way out, not just in the UI.
    ///
    /// Careful: unlike plain properties, assigning a `@Published` property inside its own
    /// `didSet` DOES fire `didSet` again. Every clamp below therefore reassigns only when the
    /// value actually changes and returns, letting the re-entrant call do the real work.
    @Published var maxBrightness: Double = LightController.storedMaxBrightness {
        didSet {
            let clamped = maxBrightness.clamped(1, 100)
            if clamped != maxBrightness { maxBrightness = clamped; return }
            guard maxBrightness != oldValue else { return }
            UserDefaults.standard.set(maxBrightness, forKey: "maxBrightness")
            applyCeiling()
        }
    }

    private static var storedMaxBrightness: Double {
        let stored = UserDefaults.standard.double(forKey: "maxBrightness")
        return stored > 0 ? stored : 50
    }

    // White mode
    @Published var brightness: Double = min(80, LightController.storedMaxBrightness) {
        didSet {
            if brightness > maxBrightness { brightness = maxBrightness; return }
            throttled { self.sendCCT() }
        }
    }
    @Published var kelvin: Double = 56 { didSet { throttled { self.sendCCT() } } }
    @Published var gm: Double = 0 { didSet { throttled { self.sendCCT() } } }

    // Colour mode
    @Published var hue: Double = 0 { didSet { throttled { self.sendHSI() } } }
    @Published var saturation: Double = 100 { didSet { throttled { self.sendHSI() } } }
    @Published var colourBrightness: Double = min(80, LightController.storedMaxBrightness) {
        didSet {
            if colourBrightness > maxBrightness { colourBrightness = maxBrightness; return }
            throttled { self.sendHSI() }
        }
    }

    // Scene mode
    @Published var effect: Effect = Effect.all[0] { didSet { sendEffect() } }
    @Published var fx = FXValues() {
        didSet {
            let cap = Int(maxBrightness)
            if fx.brightness > cap || fx.brightness2 > cap {
                var clamped = fx
                clamped.brightness = min(clamped.brightness, cap)
                clamped.brightness2 = min(clamped.brightness2, cap)
                fx = clamped
                return
            }
            throttled { self.sendEffect() }
        }
    }

    /// Pulls every brightness value back under the ceiling and re-sends the active mode.
    private func applyCeiling() {
        if brightness > maxBrightness { brightness = maxBrightness }
        if colourBrightness > maxBrightness { colourBrightness = maxBrightness }
        let cap = Int(maxBrightness)
        if fx.brightness > cap || fx.brightness2 > cap {
            var clamped = fx
            clamped.brightness = min(clamped.brightness, cap)
            clamped.brightness2 = min(clamped.brightness2, cap)
            fx = clamped
        }
        pushCurrentMode()
    }

    /// Last line of defence: nothing reaches the light above the ceiling, whatever the caller did.
    private func capped(_ value: Double) -> Int { Int(value.clamped(0, maxBrightness)) }

    /// Manually entered MAC, used when macOS won't hand one over. Persisted.
    @Published var manualMAC: String = UserDefaults.standard.string(forKey: "manualMAC") ?? "" {
        didSet {
            UserDefaults.standard.set(manualMAC, forKey: "manualMAC")
            if let m = Self.parseMAC(manualMAC) { mac = m; note("Using manual MAC \(manualMAC)"); markConnected() }
        }
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlChar: CBCharacteristic?
    private var mac: [UInt8]?
    private var lightName = "Neewer HS60C"
    private var pendingWrite: DispatchWorkItem?
    private var macLookupTries = 0
    private var wantsReconnect = true
    private var candidates: [UUID: (CBPeripheral, String)] = [:]
    private var fallbackArmed = false

    override init() {
        super.init()
        if let m = Self.parseMAC(manualMAC) { mac = m }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Sending

    /// Sliders fire continuously; BLE jams if written faster than ~every 15 ms.
    private func throttled(_ block: @escaping () -> Void) {
        pendingWrite?.cancel()
        let item = DispatchWorkItem(block: block)
        pendingWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: item)
    }

    private func write(_ data: Data) {
        guard let p = peripheral, let c = controlChar, p.state == .connected else { return }
        let type: CBCharacteristicWriteType =
            c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(data, for: c, type: type)
        note("→ \(data.hex)")
    }

    private func sendPower() {
        guard let mac else { return }
        write(Command.power(isOn, mac: mac))
    }

    private func sendCCT() {
        guard let mac, isOn else { return }
        write(Command.cct(brightness: capped(brightness), kelvin: Int(kelvin), gm: Int(gm), mac: mac))
    }

    private func sendHSI() {
        guard let mac, isOn else { return }
        write(Command.hsi(hue: Int(hue), saturation: Int(saturation),
                          brightness: capped(colourBrightness), mac: mac))
    }

    private func sendEffect() {
        guard let mac, isOn else { return }
        var safe = fx
        safe.brightness = capped(Double(safe.brightness))
        safe.brightness2 = capped(Double(safe.brightness2))
        write(Command.effect(id: effect.id, payload: effect.payload(from: safe), mac: mac))
    }

    /// Re-asserts whichever mode is showing, so switching tabs actually changes the light.
    func pushCurrentMode() {
        switch mode {
        case .cct: sendCCT()
        case .colour: sendHSI()
        case .scene: sendEffect()
        }
    }

    // MARK: - Connection lifecycle

    func rescan() {
        wantsReconnect = true
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; controlChar = nil
        startScan()
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        status = .scanning
        candidates.removeAll()
        fallbackArmed = false
        note("Scanning…")
        // Neewer lights don't advertise their service UUID, so scan broadly and filter by name.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func markConnected() {
        guard controlChar != nil else { return }
        if mac != nil {
            status = .connected(lightName)
            sendPower()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.pushCurrentMode() }
        } else {
            status = .needsMAC(lightName)
        }
    }

    func note(_ s: String) {
        log.append(s)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    // MARK: - MAC address

    static func parseMAC(_ s: String) -> [UInt8]? {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? bytes : nil
    }

    /// CoreBluetooth hides MAC addresses, but the HS60C's command set requires one.
    /// `system_profiler` lists it for devices the system currently has connected.
    private func lookUpMAC() {
        guard mac == nil, macLookupTries < 6 else { return }
        macLookupTries += 1
        let name = lightName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.macFromSystemProfiler(matching: name)
            DispatchQueue.main.async {
                guard let self else { return }
                if let found, let bytes = Self.parseMAC(found) {
                    self.mac = bytes
                    self.note("Found MAC \(found)")
                    self.markConnected()
                } else {
                    self.note("MAC lookup attempt \(self.macLookupTries) found nothing")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.lookUpMAC() }
                }
            }
        }
    }

    private static func macFromSystemProfiler(matching name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["-xml", "SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let top = plist as? [[String: Any]] else { return nil }

        var fallback: String?
        for dict in top {
            guard let items = dict["_items"] as? [[String: Any]] else { continue }
            for item in items {
                for (key, value) in item {
                    guard key.hasPrefix("device_"), let devices = value as? [Any] else { continue }
                    for dev in devices {
                        guard let devDict = dev as? [String: Any] else { continue }
                        for (devName, info) in devDict {
                            guard let info = info as? [String: Any],
                                  let address = info["device_address"] as? String else { continue }
                            if devName == name { return address }
                            if LightID.looksLikeNeewer(devName) { fallback = address }
                        }
                    }
                }
            }
        }
        return fallback
    }
}

// MARK: - CBCentralManagerDelegate

extension LightController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: startScan()
        case .poweredOff: status = .bluetoothOff
        case .unauthorized: status = .unauthorized
        default: status = .disconnected
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard !name.isEmpty, LightID.looksLikeNeewer(name) else { return }
        guard candidates[p.identifier] == nil else { return }
        candidates[p.identifier] = (p, name)
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            note("Found \(name) (RSSI \(rssi)) mfg \(mfg.hex)")
        } else {
            note("Found \(name) (RSSI \(rssi))")
        }

        // An HS60C is what we came for; anything else Neewer-shaped is a fallback,
        // taken only if no HS60C turns up within a couple of seconds.
        if LightID.isHS60C(name) {
            connect(to: p, named: name)
        } else if !fallbackArmed {
            fallbackArmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.peripheral == nil,
                      let (per, nm) = self.candidates.values.first else { return }
                self.connect(to: per, named: nm)
            }
        }
    }

    private func connect(to p: CBPeripheral, named name: String) {
        guard peripheral == nil else { return }
        central.stopScan()
        lightName = name
        peripheral = p
        p.delegate = self
        status = .connecting(name)
        central.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        note("Connected to \(lightName)")
        macLookupTries = 0
        p.discoverServices([BLE.service])
        // The system needs a moment before it reports the device as connected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.lookUpMAC() }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        note("Connect failed: \(error?.localizedDescription ?? "unknown")")
        status = .disconnected
        if wantsReconnect { startScan() }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        note("Disconnected")
        controlChar = nil
        status = .disconnected
        if wantsReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.startScan() }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension LightController: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == BLE.service {
            p.discoverCharacteristics([BLE.control, BLE.notify], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == BLE.control { controlChar = ch }
            if ch.uuid == BLE.notify { p.setNotifyValue(true, for: ch) }
        }
        if controlChar != nil { note("Control characteristic ready"); markConnected() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let d = ch.value, !d.isEmpty { note("← \(d.hex)") }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { note("Write error: \(e.localizedDescription)") }
    }
}
