// Aggregates per-frame media reports into a per-WINDOW playing state and
// forwards transitions to the native host, which tags the Hyprland window.
// Config (playSignal, pauseGraceMs) arrives FROM the host on connect: the
// host reads the HM-written json so there is exactly one config file.
"use strict";

const HOST = "ff_hyprglass_bridge";

let config = {playSignal: "activeTab", pauseGraceMs: 3000};
let port = null;
let portRetryMs = 1000;

// tabId -> { frames: Map<frameId, {playing, audible}>, windowId }
const tabs = new Map();
// windowId -> {playing: bool, clearTimer: id|null}
const windows = new Map();

function connect() {
  try {
    port = browser.runtime.connectNative(HOST);
  } catch (e) {
    port = null;
    setTimeout(connect, (portRetryMs = Math.min(portRetryMs * 2, 60000)));
    return;
  }
  portRetryMs = 1000;
  port.onMessage.addListener((m) => {
    if (m && m.type === "config") {
      if (m.playSignal) config.playSignal = m.playSignal;
      if (Number.isFinite(m.pauseGraceMs)) config.pauseGraceMs = m.pauseGraceMs;
    }
  });
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, (portRetryMs = Math.min(portRetryMs * 2, 60000)));
  });
}
connect();

function tabState(tabId) {
  const t = tabs.get(tabId);
  if (!t) return {playing: false, audible: false};
  let playing = false, audible = false;
  for (const f of t.frames.values()) {
    if (f.playing > 0) playing = true;
    if (f.audible) audible = true;
  }
  return {playing, audible};
}

async function windowPlaying(windowId) {
  const mode = config.playSignal;
  if (mode === "activeTab") {
    const active = await browser.tabs.query({windowId, active: true});
    if (!active.length) return false;
    const s = tabState(active[0].id);
    return s.playing;
  }
  let any = false;
  for (const [tabId, t] of tabs) {
    if (t.windowId !== windowId) continue;
    const s = tabState(tabId);
    if (mode === "audible" ? s.playing && s.audible : s.playing) {
      any = true;
      break;
    }
  }
  return any;
}

async function sendState(windowId, playing) {
  if (!port) return; // degrade: host down, R2-only behaviour
  let title = "";
  try {
    title = (await browser.windows.get(windowId)).title || "";
  } catch (e) {
    return; // window gone
  }
  port.postMessage({type: "state", windowId, playing, title});
}

async function refreshWindow(windowId) {
  if (windowId === undefined || windowId < 0) return;
  const playing = await windowPlaying(windowId);
  let w = windows.get(windowId);
  if (!w) windows.set(windowId, (w = {playing: false, clearTimer: null}));

  if (playing) {
    if (w.clearTimer) {
      clearTimeout(w.clearTimer);
      w.clearTimer = null;
    }
    if (!w.playing) {
      w.playing = true;
      sendState(windowId, true);
    }
  } else if (w.playing && !w.clearTimer) {
    // Pause grace: seeks and buffering flap play/pause; only a pause that
    // SURVIVES the grace period clears the tags.
    w.clearTimer = setTimeout(() => {
      w.clearTimer = null;
      w.playing = false;
      sendState(windowId, false);
    }, config.pauseGraceMs);
  }
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.type !== "media" || !sender.tab) return;
  const tabId = sender.tab.id;
  const frameId = sender.frameId ?? 0;
  let t = tabs.get(tabId);
  if (!t) tabs.set(tabId, (t = {frames: new Map(), windowId: sender.tab.windowId}));
  t.windowId = sender.tab.windowId;
  t.frames.set(frameId, {playing: msg.playing, audible: msg.audible});
  refreshWindow(t.windowId);
});

browser.tabs.onRemoved.addListener((tabId, info) => {
  const t = tabs.get(tabId);
  tabs.delete(tabId);
  if (t) refreshWindow(t.windowId);
});
browser.tabs.onActivated.addListener((info) => refreshWindow(info.windowId));
browser.tabs.onAttached.addListener((tabId, info) => {
  const t = tabs.get(tabId);
  if (t) {
    const old = t.windowId;
    t.windowId = info.newWindowId;
    refreshWindow(old);
    refreshWindow(info.newWindowId);
  }
});
browser.windows.onRemoved.addListener((windowId) => windows.delete(windowId));
