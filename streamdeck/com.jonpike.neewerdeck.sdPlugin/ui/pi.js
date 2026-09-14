// Minimal Property Inspector plumbing — no CDN, no build step.
// Any <input>/<select> with a name attribute is bound to the setting of that name.

let socket, uuid, settings = {};

window.connectElgatoStreamDeckSocket = (port, inUUID, registerEvent, info, actionInfo) => {
  uuid = inUUID;
  try { settings = JSON.parse(actionInfo).payload.settings || {}; } catch { settings = {}; }
  socket = new WebSocket(`ws://127.0.0.1:${port}`);
  socket.onopen = () => {
    socket.send(JSON.stringify({ event: registerEvent, uuid }));
    hydrate();
  };
  socket.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.event === "didReceiveSettings") {
      settings = msg.payload.settings || {};
      hydrate();
    }
  };
};

function save() {
  socket?.send(JSON.stringify({ event: "setSettings", context: uuid, payload: settings }));
}

function hydrate() {
  for (const el of document.querySelectorAll("[name]")) {
    const v = settings[el.name];
    if (v !== undefined && v !== null) {
      if (el.type === "checkbox") el.checked = !!v;
      else el.value = v;
    } else if (el.dataset.default !== undefined) {
      // First run: seed the control and the stored settings from the declared default.
      if (el.type === "checkbox") el.checked = el.dataset.default === "true";
      else el.value = el.dataset.default;
      settings[el.name] = el.type === "checkbox" ? el.checked : coerce(el);
    }
    sync(el);
  }
  save();
}

function coerce(el) {
  return el.type === "number" || el.type === "range" ? Number(el.value) : el.value;
}

/// Mirrors a range input's value into the <output> next to it, and repaints swatches.
function sync(el) {
  const out = el.parentElement?.querySelector("output");
  if (out) out.textContent = el.dataset.suffix ? `${el.value}${el.dataset.suffix}` : el.value;
  const preview = document.getElementById("preview");
  if (preview) {
    preview.style.background =
      `hsl(${settings.hue ?? 210} ${settings.saturation ?? 100}% ` +
      `${Math.min(70, Math.max(20, (settings.brightness ?? 50) * 0.6 + 20))}%)`;
  }
}

document.addEventListener("input", (e) => {
  const el = e.target;
  if (!el.name) return;
  settings[el.name] = el.type === "checkbox" ? el.checked : coerce(el);
  sync(el);
  save();
});
