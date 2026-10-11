# Neewer Light

A macOS menu bar app for the **Neewer HS60C** (and HS60C Pro). Native Swift + SwiftUI,
talks to the light directly over Bluetooth LE. No Xcode required to build.

## Install

```
./install.sh
```

This builds and copies the app to `~/Applications/Neewer Light.app`, and installs the
Stream Deck plugin (restarting Stream Deck so it loads). It has to live outside
Dropbox — apps in CloudStorage folders get killed by macOS on launch.

Launch it from Spotlight. macOS will ask for Bluetooth permission the first time.

**Quit the Neewer app on your phone first.** The light accepts one BLE connection at a time.

## What it does

- **Power** on/off
- **White** — brightness 0–100%, 2700–6500 K, green/magenta shift ±50, plus five presets
- **Colour** — hue, saturation, brightness, with eight quick swatches
- **Scene** — all 17 built-in effects (Lightning, Paparazzi, Cop Car, Candlelight, Firework…),
  each with its own parameter set
- **Brightness limit** — a hard ceiling (50% by default) on every brightness the app will send
- **Open at login** — checkbox at the bottom of the popover; mirrors System Settings › General ›
  Login Items, so turning it off there unticks it here

## The brightness limit

The light browns out and cuts power if the supply can't deliver what the panel asks for, and
recovering from that means physically power-cycling it. So the ceiling is enforced on the way
out, not just in the UI: sliders won't drag past it, presets clamp to it, scene effects clamp
to it, and the command builders clamp again before anything hits the wire. The shaded part of
a brightness track is the part that's off limits. Change it at the bottom of the popover.

The status line at the top shows the connection state; **Show log** reveals the raw BLE
traffic, which is the first place to look if something misbehaves.

## The MAC address

This is the one fiddly part. The HS60C's command set embeds the light's Bluetooth MAC in
every packet, but CoreBluetooth deliberately hides MAC addresses from apps. The workaround
is to shell out to `system_profiler SPBluetoothDataType` once connected and read the address
back out — the same trick NeewerLite uses.

If that comes up empty the header says **"MAC address needed"** and a text field appears.
Type the address in as `AA:BB:CC:DD:EE:FF`; it's saved and reused. You can find it in the
Neewer phone app under the light's device info.

## Stream Deck

`streamdeck/com.jonpike.neewerdeck.sdPlugin` — actions for On/Off, Brightness, Temperature,
Colour and Scene. Brightness and Temperature work as both keys and dials.

Keys mirror the real state: the power key lights up when the light is on and reads “no app”
when the menu bar app isn't running, a scene key lights up while its scene is running, and a
colour key is painted with the colour it will set.

The plugin does **not** speak Bluetooth. The light accepts only one BLE connection and the
menu bar app holds it, so the plugin drives the app instead, over a loopback HTTP server on
`127.0.0.1:8765` (bound to loopback only — not reachable from the network). That also means
the brightness ceiling applies to Stream Deck presses for free.

| Route | Body | Does |
|---|---|---|
| `GET /state` | — | current state as JSON |
| `POST /power` | `{"toggle":true}` or `{"on":false}` | power |
| `POST /brightness` | `{"set":40}` or `{"delta":-5}` | brightness, capped |
| `POST /temperature` | `{"set":56}` or `{"delta":2}` | kelvin ÷ 100, switches to white mode |
| `POST /colour` | `{"hue":210,"saturation":100,"brightness":40}` | colour mode |
| `POST /scene` | `{"id":10,"speed":5}` | scene mode |
| `POST /mode` | `{"mode":"white"}` | switch tab |

Handy for scripting anything else too:

```
curl -s 127.0.0.1:8765/state
curl -s -X POST 127.0.0.1:8765/power -d '{"toggle":true}'
```

Icons are built from the SVGs in `imgs/` — edit those and run `streamdeck/render-icons.sh`.

## Protocol notes

Frame layout: `78 <tag> <size> <MAC 6 bytes> <subtag> <payload…> <checksum>`, where `size`
counts every byte after itself except the checksum, and the checksum is the low byte of the
sum of everything before it.

| Command | Tag | Subtag | Payload |
|---|---|---|---|
| Power   | `8D` | `81` | `01` on / `02` off |
| White   | `90` | `87` | brightness 0–100, kelvin 27–65, G/M +50 offset, dimming curve `04` |
| Colour  | `8F` | `86` | hue uint16-LE 0–360, saturation 0–100, brightness 0–100, `00` |
| Scene   | `91` | `8B` | effect id 1–17, then that effect's parameters |

Service `69400001-B5A3-F393-E0A9-E50E24DCCA99`, write to `…0002`, notify on `…0003`.

The power and colour builders are verified byte-for-byte against published packet captures;
run `./test.sh` to re-check them.

## Errors

| Code | Meaning | Fix |
|---|---|---|
| `NL-LOGIN-01` | macOS refused to add or remove the login item. | Make sure the app is running from `~/Applications` (run `install.sh`), not from Dropbox or the build folder, then toggle again. If it still fails, add or remove it by hand in System Settings › General › Login Items. |

## Build

```
./build.sh     # compiles NeewerLight.app in place
./install.sh   # build + copy to ~/Applications
```

Protocol reference: the light database and command formats were derived from
[NeewerLite](https://github.com/keefo/NeewerLite) (HS60C is light type 87, project `NW-20230042`).
