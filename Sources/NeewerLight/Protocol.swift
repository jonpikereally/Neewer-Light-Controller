//  Protocol.swift — Neewer HS60C BLE command construction.
//
//  Every command is:  0x78 <tag> <size> <mac 6 bytes> <subtag> <payload…> <checksum>
//  where <size> counts everything after the size byte except the checksum, and
//  <checksum> is the low byte of the sum of all preceding bytes.
//
//  The HS60C (light type 87, project code NW-20230042) uses the "new" MAC-addressed
//  command set: power 0x8D, CCT+GM 0x90, HSI 0x8F, FX 0x91.

import CoreBluetooth
import Foundation

enum BLE {
    static let service = CBUUID(string: "69400001-B5A3-F393-E0A9-E50E24DCCA99")
    static let control = CBUUID(string: "69400002-B5A3-F393-E0A9-E50E24DCCA99")
    static let notify = CBUUID(string: "69400003-B5A3-F393-E0A9-E50E24DCCA99")
}

enum Tag {
    static let prefix: UInt8 = 0x78
    static let power: UInt8 = 0x8D
    static let powerSub: UInt8 = 0x81
    static let cct: UInt8 = 0x90
    static let cctSub: UInt8 = 0x87
    static let hsi: UInt8 = 0x8F
    static let hsiSub: UInt8 = 0x86
    static let fx: UInt8 = 0x91
    static let fxSub: UInt8 = 0x8B
}

/// The HS60C's advertised name is `NW-20230042&…`; the Neewer app may rename it to
/// something containing "HS60C".
enum LightID {
    static func looksLikeNeewer(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("nw-") || n.hasPrefix("nh-") || n.hasPrefix("neewer")
            || n.contains("neewer") || n.contains("nwr") || n.contains("nee")
    }

    static func isHS60C(_ name: String) -> Bool {
        let n = name.uppercased()
        return n.contains("HS60C") || n.hasPrefix("NW-20230042")
    }
}

struct Command {
    /// Builds `78 <tag> <size> <mac> <subtag> <payload> <checksum>`.
    static func build(tag: UInt8, mac: [UInt8], subtag: UInt8, payload: [UInt8]) -> Data {
        var mac6 = mac
        while mac6.count < 6 { mac6.append(0) }
        var bytes: [UInt8] = [Tag.prefix, tag, UInt8(payload.count + 7)]
        bytes.append(contentsOf: mac6.prefix(6))
        bytes.append(subtag)
        bytes.append(contentsOf: payload)
        bytes.append(checksum(bytes))
        return Data(bytes)
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8(bytes.reduce(0) { ($0 + Int($1)) } & 0xFF)
    }

    // 78 8D 08 <mac> 81 01|02 <ck>
    static func power(_ on: Bool, mac: [UInt8]) -> Data {
        build(tag: Tag.power, mac: mac, subtag: Tag.powerSub, payload: [on ? 0x01 : 0x02])
    }

    /// 78 90 0B <mac> 87 <brightness> <cct> <gm+50> <curve> <ck>
    /// - brightness: 0…100
    /// - cct: 27…65 (hundreds of kelvin)
    /// - gm: -50…50 green/magenta shift, sent offset by +50
    static func cct(brightness: Int, kelvin: Int, gm: Int, mac: [UInt8]) -> Data {
        let brr = UInt8(clamping: brightness.clamped(0, 100))
        let cct = UInt8(clamping: kelvin.clamped(27, 65))
        let gmm = UInt8(clamping: (gm.clamped(-50, 50)) + 50)
        let dimmingCurve: UInt8 = 0x04
        return build(tag: Tag.cct, mac: mac, subtag: Tag.cctSub, payload: [brr, cct, gmm, dimmingCurve])
    }

    /// 78 8F 0C <mac> 86 <hue lo> <hue hi> <sat> <brightness> 00 <ck>
    /// - hue: 0…360, sat: 0…100, brightness: 0…100
    static func hsi(hue: Int, saturation: Int, brightness: Int, mac: [UInt8]) -> Data {
        let h = hue.clamped(0, 360)
        let payload: [UInt8] = [
            UInt8(h & 0xFF),
            UInt8((h >> 8) & 0xFF),
            UInt8(clamping: saturation.clamped(0, 100)),
            UInt8(clamping: brightness.clamped(0, 100)),
            0
        ]
        return build(tag: Tag.hsi, mac: mac, subtag: Tag.hsiSub, payload: payload)
    }

    /// 78 91 <size> <mac> 8B <fx id> <fx payload…> <ck>
    static func effect(id: UInt8, payload: [UInt8], mac: [UInt8]) -> Data {
        build(tag: Tag.fx, mac: mac, subtag: Tag.fxSub, payload: [id] + payload)
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
