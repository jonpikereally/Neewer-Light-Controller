//  ControlServer.swift — a loopback HTTP control surface for the Stream Deck plugin.
//
//  The HS60C accepts exactly one BLE connection, so nothing else may talk to the light
//  directly while this app holds it. Everything external drives the light through here.
//  Bound to 127.0.0.1 only — it is not reachable from the network.

import Foundation
import Network

final class ControlServer {

    static let port: UInt16 = 8765

    private var listener: NWListener?
    private unowned let light: LightController

    init(light: LightController) {
        self.light = light
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                 port: NWEndpoint.Port(rawValue: Self.port)!)
        do {
            listener = try NWListener(using: params)
        } catch {
            DispatchQueue.main.async { self.light.note("Control server failed: \(error.localizedDescription)") }
            return
        }
        listener?.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                DispatchQueue.main.async { self.light.note("Control server on 127.0.0.1:\(Self.port)") }
            }
            if case .failed(let e) = state {
                DispatchQueue.main.async { self.light.note("Control server error: \(e.localizedDescription)") }
            }
        }
        listener?.start(queue: .main)
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, done, _ in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }

            // Wait for the full request: headers, plus a body if Content-Length says so.
            if let (head, body, complete) = Self.parse(buf), complete {
                self.respond(to: head, body: body, on: conn)
            } else if done {
                conn.cancel()
            } else if buf.count < 1 << 20 {
                self.receive(conn, buffer: buf)
            } else {
                conn.cancel()
            }
        }
    }

    /// Splits a request into its start line + headers and its body.
    private static func parse(_ data: Data) -> (head: String, body: Data, complete: Bool)? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self)
        let body = data[sep.upperBound...]
        var expected = 0
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            expected = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return (head, Data(body), body.count >= expected)
    }

    private func respond(to head: String, body: Data, on conn: NWConnection) {
        let startLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = startLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : "/"
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

        let payload = handle(method: method, path: path, json: json)
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)

        var response = Data("""
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r\n
        """.utf8)
        response.append(data)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Routes

    private func handle(method: String, path: String, json: [String: Any]) -> [String: Any] {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        let num = { (key: String) -> Double? in (json[key] as? NSNumber)?.doubleValue }

        switch route {
        case "/", "/state":
            break

        case "/power":
            if json["toggle"] as? Bool == true { light.isOn.toggle() }
            else if let on = json["on"] as? Bool { light.isOn = on }

        case "/brightness":
            let current = light.mode == .colour ? light.colourBrightness : light.brightness
            // The app's own ceiling still applies; the setter clamps.
            let target = num("set") ?? (current + (num("delta") ?? 0))
            if light.mode == .colour { light.colourBrightness = target.clamped(0, 100) }
            else { light.brightness = target.clamped(0, 100) }

        case "/temperature":
            if light.mode != .cct { light.mode = .cct }
            let target = num("set") ?? (light.kelvin + (num("delta") ?? 0))
            light.kelvin = target.clamped(27, 65)

        case "/colour", "/color":
            light.mode = .colour
            if let h = num("hue") { light.hue = h.clamped(0, 360) }
            if let s = num("saturation") { light.saturation = s.clamped(0, 100) }
            if let b = num("brightness") { light.colourBrightness = b.clamped(0, 100) }

        case "/scene":
            light.mode = .scene
            if let id = num("id"), let fx = Effect.all.first(where: { $0.id == UInt8(id.clamped(1, 17)) }) {
                light.effect = fx
            }
            if let s = num("speed") { light.fx.speed = Int(s.clamped(1, 10)) }

        case "/mode":
            switch json["mode"] as? String {
            case "white", "cct": light.mode = .cct
            case "colour", "color": light.mode = .colour
            case "scene": light.mode = .scene
            default: break
            }

        default:
            return ["error": "unknown route \(route)"]
        }
        return state()
    }

    private func state() -> [String: Any] {
        [
            "connected": light.status.isReady,
            "status": light.status.text,
            "on": light.isOn,
            "mode": light.mode == .cct ? "white" : (light.mode == .colour ? "colour" : "scene"),
            "brightness": Int(light.mode == .colour ? light.colourBrightness : light.brightness),
            "maxBrightness": Int(light.maxBrightness),
            "kelvin": Int(light.kelvin),
            "gm": Int(light.gm),
            "hue": Int(light.hue),
            "saturation": Int(light.saturation),
            "scene": Int(light.effect.id),
            "sceneName": light.effect.name
        ]
    }
}
