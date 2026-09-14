// Neewer Deck — Stream Deck plugin for the Neewer Light menu bar app.
//
// The HS60C only accepts one Bluetooth connection, and the menu bar app holds it.
// So this plugin never touches BLE; it drives the app's loopback control server
// (127.0.0.1:8765) and mirrors the state it reports back onto the keys.

const WebSocket = require("ws");

const BASE = "http://127.0.0.1:8765";
const POLL_MS = 1000;

// --- Stream Deck registration -------------------------------------------------

const argv = {};
for (let i = 2; i < process.argv.length; i += 2) {
  argv[process.argv[i].replace(/^-+/, "")] = process.argv[i + 1];
}
const ws = new WebSocket(`ws://127.0.0.1:${argv.port}`);
const send = (obj) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(obj));
ws.on("open", () => send({ event: argv.registerEvent, uuid: argv.pluginUUID }));

const log = (msg) => send({ event: "logMessage", payload: { message: `[neewerdeck] ${msg}` } });

// --- App control surface ------------------------------------------------------

let light = null;        // last known state, or null when the app isn't reachable
const contexts = new Map();

async function call(path, body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  try {
    const res = await fetch(BASE + path, {
      method: body ? "POST" : "GET",
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    light = await res.json();
    return light;
  } catch {
    light = null;                      // app quit, or hasn't started its server yet
    return null;
  } finally {
    clearTimeout(timer);
  }
}

setInterval(() => { if (contexts.size) call("/state").then(renderAll); }, POLL_MS);

// --- Rendering ----------------------------------------------------------------

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
const kelvinText = (k) => `${k * 100}K`;

/// A flat SVG swatch, used for the Colour key so it shows what it will set.
function swatch(hue, sat, bri) {
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144">` +
    `<rect width="144" height="144" rx="20" fill="hsl(${hue} ${sat}% ${clamp(bri * 0.6 + 20, 20, 70)}%)"/>` +
    `</svg>`;
  return `data:image/svg+xml;charset=utf8,${svg}`;
}

function renderAll() {
  for (const [context, entry] of contexts) render(context, entry);
}

function render(context, entry) {
  const { action, settings, controller } = entry;
  const reachable = light && light.connected;
  const short = action.split(".").pop();

  if (controller === "Encoder") {
    const isBrightness = short === "brightness";
    const value = !light ? "—"
      : isBrightness ? `${light.brightness}%`
      : kelvinText(light.kelvin);
    const indicator = !light ? 0
      : isBrightness ? light.brightness
      : ((light.kelvin - 27) / (65 - 27)) * 100;
    send({
      event: "setFeedback",
      context,
      payload: {
        title: !light ? "App not running" : isBrightness ? "Brightness" : "Temperature",
        value,
        indicator: { value: Math.round(indicator) },
      },
    });
    return;
  }

  switch (short) {
    case "power":
      send({ event: "setState", context, payload: { state: reachable && light.on ? 1 : 0 } });
      send({ event: "setTitle", context, payload: { title: light ? "" : "no app" } });
      break;

    case "brightness":
      if (settings.showValue !== false) {
        send({ event: "setTitle", context, payload: { title: light ? `${light.brightness}%` : "—" } });
      }
      break;

    case "temperature":
      if (settings.showValue !== false) {
        send({ event: "setTitle", context, payload: { title: light ? kelvinText(light.kelvin) : "—" } });
      }
      break;

    case "colour":
      send({
        event: "setImage",
        context,
        payload: {
          image: swatch(
            settings.hue ?? 210,
            settings.saturation ?? 100,
            settings.brightness ?? 50
          ),
        },
      });
      break;

    case "scene": {
      const active = reachable && light.mode === "scene" && light.scene === Number(settings.scene ?? 1);
      send({ event: "setState", context, payload: { state: active ? 1 : 0 } });
      break;
    }
  }
}

// --- Input --------------------------------------------------------------------

async function act(context, path, body) {
  const result = await call(path, body);
  if (!result) {
    send({ event: "showAlert", context });   // app isn't running
    renderAll();
    return;
  }
  renderAll();
}

ws.on("message", async (raw) => {
  let msg;
  try { msg = JSON.parse(raw); } catch { return; }
  const { event, context, action, payload = {} } = msg;
  const settings = payload.settings || {};

  switch (event) {
    case "willAppear":
      contexts.set(context, { action, settings, controller: payload.controller || "Keypad" });
      await call("/state");
      renderAll();
      break;

    case "willDisappear":
      contexts.delete(context);
      break;

    case "didReceiveSettings": {
      const entry = contexts.get(context);
      if (entry) entry.settings = settings;
      renderAll();
      break;
    }

    case "keyDown": {
      const short = (action || "").split(".").pop();
      const step = Number(settings.step ?? (short === "temperature" ? 2 : 10));
      if (short === "power") {
        const mode = settings.mode || "toggle";
        await act(context, "/power",
          mode === "toggle" ? { toggle: true } : { on: mode === "on" });
      } else if (short === "brightness") {
        await act(context, "/brightness",
          settings.mode === "set" ? { set: Number(settings.value ?? 40) } : { delta: step });
      } else if (short === "temperature") {
        await act(context, "/temperature",
          settings.mode === "set" ? { set: Number(settings.value ?? 56) } : { delta: step });
      } else if (short === "colour") {
        await act(context, "/colour", {
          hue: Number(settings.hue ?? 210),
          saturation: Number(settings.saturation ?? 100),
          brightness: Number(settings.brightness ?? 50),
        });
      } else if (short === "scene") {
        await act(context, "/scene", {
          id: Number(settings.scene ?? 1),
          speed: Number(settings.speed ?? 5),
        });
      }
      break;
    }

    case "dialRotate": {
      const short = (action || "").split(".").pop();
      const ticks = payload.ticks || 0;
      const step = Number(settings.step ?? (short === "temperature" ? 1 : 5));
      await act(context, short === "temperature" ? "/temperature" : "/brightness",
        { delta: ticks * step });
      break;
    }

    case "dialDown":
    case "touchTap": {
      const short = (action || "").split(".").pop();
      if (short === "temperature") await act(context, "/temperature", { set: 56 });
      else await act(context, "/power", { toggle: true });
      break;
    }
  }
});

ws.on("error", (e) => log(`socket error: ${e.message}`));
