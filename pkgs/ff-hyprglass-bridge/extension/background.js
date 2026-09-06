// Aggregates per-frame media reports into a per-WINDOW state (playing, and
// in rect mode the visible video rects) and forwards transitions to the
// native host, which tags the Hyprland window.
// Config (playbackAction, playSignal, pauseGraceMs, rectRateHz) arrives FROM
// the host on connect: the host reads the HM-written json so there is
// exactly one config file. rectRateHz is relayed to the content scripts.
"use strict";

const HOST = "ff_hyprglass_bridge";

let config = {playbackAction: "rect", playSignal: "activeTab", pauseGraceMs: 3000, rectRateHz: 10};
let port = null;
let portRetryMs = 1000;

// tabId -> { frames: Map<frameId, {playing, audible, rects, outer}>, windowId }
const tabs = new Map();
// windowId -> {playing: bool, sent: string, clearTimer: id|null}
const windows = new Map();

function broadcastConfig() {
  browser.tabs.query({}).then((all) => {
    for (const t of all) {
      try {
        browser.tabs.sendMessage(t.id, {type: "config", rectRateHz: config.rectRateHz}).catch(() => {});
      } catch (e) {}
    }
  }, () => {});
}

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
      if (m.playbackAction) config.playbackAction = m.playbackAction;
      if (m.playSignal) config.playSignal = m.playSignal;
      if (Number.isFinite(m.pauseGraceMs)) config.pauseGraceMs = m.pauseGraceMs;
      if (Number.isFinite(m.rectRateHz)) config.rectRateHz = m.rectRateHz;
      broadcastConfig();
      // The host restarted (or just started): it has no memory of what was
      // applied, so replay every window's current state.
      for (const [windowId, w] of windows) {
        w.sent = "";
        refreshWindow(windowId);
      }
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
  if (!t) return {playing: false, audible: false, rects: [], outer: null};
  let playing = false, audible = false, outer = null;
  const rects = [];
  for (const f of t.frames.values()) {
    if (f.playing > 0) playing = true;
    if (f.audible) audible = true;
    if (Array.isArray(f.rects)) rects.push(...f.rects);
    if (f.outer) outer = f.outer;
  }
  return {playing, audible, rects, outer};
}

// Returns {playing, rects, outer} for the window under the configured
// playSignal. Rects come only from tabs that count; a hidden tab reports
// none anyway (content.js empties them on visibilitychange).
async function windowState(windowId) {
  const mode = config.playSignal;
  if (mode === "activeTab") {
    const active = await browser.tabs.query({windowId, active: true});
    if (!active.length) return {playing: false, rects: [], outer: null};
    const s = tabState(active[0].id);
    return {playing: s.playing, rects: s.rects, outer: s.outer};
  }
  let playing = false, outer = null;
  const rects = [];
  for (const [tabId, t] of tabs) {
    if (t.windowId !== windowId) continue;
    const s = tabState(tabId);
    if (mode === "audible" ? s.playing && s.audible : s.playing) {
      playing = true;
      rects.push(...s.rects);
      if (s.outer) outer = s.outer;
    }
  }
  return {playing, rects, outer};
}

async function sendState(windowId, playing, rects, outer) {
  if (!port) return; // degrade: host down, R2-only behaviour
  let title = "";
  try {
    title = (await browser.windows.get(windowId)).title || "";
  } catch (e) {
    return; // window gone
  }
  port.postMessage({type: "state", windowId, playing, title, rects, outer});
}

async function refreshWindow(windowId) {
  if (windowId === undefined || windowId < 0) return;
  const s = await windowState(windowId);
  let w = windows.get(windowId);
  if (!w) windows.set(windowId, (w = {playing: false, sent: "", clearTimer: null}));

  const rectMode = config.playbackAction === "rect";
  const rects = rectMode ? s.rects : [];
  const outer = rectMode ? s.outer : null;

  if (s.playing) {
    if (w.clearTimer) {
      clearTimeout(w.clearTimer);
      w.clearTimer = null;
    }
    // Rect changes ship immediately (the content script already throttled
    // them); a playing -> playing report with identical rects is a no-op.
    const key = JSON.stringify([true, rects, outer]);
    if (!w.playing || w.sent !== key) {
      w.playing = true;
      w.sent = key;
      sendState(windowId, true, rects, outer);
    }
  } else if (w.playing && !w.clearTimer) {
    // Pause grace: seeks and buffering flap play/pause; only a pause that
    // SURVIVES the grace period clears the tags. Reports arriving during the
    // grace carry no playing video, so their (empty) rects are ignored and
    // the last applied holes stay put.
    w.clearTimer = setTimeout(() => {
      w.clearTimer = null;
      w.playing = false;
      w.sent = JSON.stringify([false, [], null]);
      sendState(windowId, false, [], null);
    }, config.pauseGraceMs);
  }
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || !sender.tab) return;
  if (msg.type === "hello")
    return Promise.resolve({type: "config", rectRateHz: config.rectRateHz});
  if (msg.type !== "media") return;
  const tabId = sender.tab.id;
  const frameId = sender.frameId ?? 0;
  let t = tabs.get(tabId);
  if (!t) tabs.set(tabId, (t = {frames: new Map(), windowId: sender.tab.windowId}));
  t.windowId = sender.tab.windowId;
  t.frames.set(frameId, {
    playing: msg.playing,
    audible: msg.audible,
    rects: Array.isArray(msg.rects) ? msg.rects : [],
    outer: msg.outer || null,
  });
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
