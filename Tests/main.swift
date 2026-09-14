let mac: [UInt8] = [0xF7, 0xAC, 0x16, 0xF1, 0x58, 0x96]
func check(_ label: String, _ got: String, _ want: String) {
    print((got == want ? "PASS  " : "FAIL  ") + label)
    if got != want { print("        got  \(got)\n        want \(want)") }
}
check("power on ", Command.power(true,  mac: mac).hex, "78 8D 08 F7 AC 16 F1 58 96 81 01 27")
check("power off", Command.power(false, mac: mac).hex, "78 8D 08 F7 AC 16 F1 58 96 81 02 28")
check("hsi h=69 s=92 b=50", Command.hsi(hue: 0x45, saturation: 0x5C, brightness: 0x32, mac: mac).hex,
      "78 8F 0C F7 AC 16 F1 58 96 86 45 00 5C 32 00 04")

// Structural checks for the two commands with no published capture.
let cct = Command.cct(brightness: 100, kelvin: 56, gm: 0, mac: mac)
check("cct size/tags", "\(cct.count) \(String(format: "%02X", cct[1])) \(String(format: "%02X", cct[2])) \(String(format: "%02X", cct[9]))", "15 90 0B 87")
print("      cct 100% 5600K gm0 -> \(cct.hex)")
let lightning = Command.effect(id: 0x01, payload: Effect.all[0].payload(from: FXValues()), mac: mac)
check("fx size/tags", "\(lightning.count) \(String(format: "%02X", lightning[1])) \(String(format: "%02X", lightning[2])) \(String(format: "%02X", lightning[9]))", "15 91 0B 8B")
print("      fx Lightning -> \(lightning.hex)")

// Checksum must be the low byte of the sum of all preceding bytes, for every effect.
var bad = 0
for fx in Effect.all {
    let d = Command.effect(id: fx.id, payload: fx.payload(from: FXValues()), mac: mac)
    let sum = UInt8(d.dropLast().reduce(0) { $0 + Int($1) } & 0xFF)
    if sum != d.last! || Int(d[2]) != d.count - 4 { bad += 1; print("FAIL  \(fx.name) \(d.hex)") }
}
check("all 17 effects well-formed", "\(bad)", "0")
