// Reports this frame's playing <video> elements to the background script:
// how many play, whether any is audible, and (rect mode) where each visible
// one sits, in window-relative CSS px. Media events do not bubble, but
// capture-phase listeners on the document see them, so no per-element wiring
// or MutationObserver is needed. all_frames:true means embedded players
// (YouTube iframes) report from their own frame; the background sums per tab.
//
// Coordinates: mozInnerScreenX/Y give this frame's viewport origin in screen
// CSS px, per frame, so an iframe's rects come out toplevel-relative with no
// frame-offset bookkeeping. On Wayland Firefox cannot learn its window's
// screen position, so screenX/Y read 0 and the values are already relative
// to the window's top-left. The top frame also sends outerWidth/Height so the
// host can scale CSS px to compositor logical px without knowing the monitor
// scale.
"use strict";

let config = {rectRateHz: 10};

let lastPayload = "";
let flushPending = false;
let throttleTimer = null;
let lastSentAt = -1e9;
let pollTimer = null;

const sizeObserver = typeof ResizeObserver === "function" ? new ResizeObserver(() => schedule()) : null;

function isPlaying(v) {
  return !v.paused && !v.ended && v.readyState >= 2;
}

function collect() {
  let playing = 0;
  let audible = false;
  const rects = [];
  const hidden = document.hidden;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  for (const v of document.querySelectorAll("video")) {
    if (!isPlaying(v))
      continue;
    playing++;
    if (!v.muted && v.volume > 0)
      audible = true;
    if (sizeObserver) {
      try { sizeObserver.observe(v); } catch (e) {}
    }
    if (hidden)
      continue; // a hidden tab has no visible rects by definition
    const r = v.getBoundingClientRect();
    const x1 = Math.max(0, r.left);
    const y1 = Math.max(0, r.top);
    const x2 = Math.min(vw, r.right);
    const y2 = Math.min(vh, r.bottom);
    if (x2 - x1 < 1 || y2 - y1 < 1)
      continue; // scrolled out of view
    rects.push({
      x: Math.round(window.mozInnerScreenX + x1),
      y: Math.round(window.mozInnerScreenY + y1),
      w: Math.round(x2 - x1),
      h: Math.round(y2 - y1),
    });
  }
  let outer = null;
  try {
    if (window.top === window)
      outer = {w: window.outerWidth, h: window.outerHeight};
  } catch (e) {}
  return {type: "media", playing, audible, rects, outer};
}

function send(payload) {
  const s = JSON.stringify(payload);
  if (s === lastPayload)
    return;
  lastPayload = s;
  try {
    browser.runtime.sendMessage(payload);
  } catch (e) {
    // Extension context gone (reload/uninstall); nothing to do.
  }
  // A playing video can move without scroll/resize/size events (layout
  // shifts, in-page theater toggles); a slow poll catches those. It only
  // runs while something plays and only sends on change.
  if (payload.playing > 0) {
    if (!pollTimer)
      pollTimer = setInterval(schedule, 1000);
  } else if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

// Leading + trailing edge throttle at rectRateHz, coalesced to one collect
// per frame. rAF does not fire in hidden tabs, so the hidden path uses a
// zero timeout; that report is what empties the rects on tab switch.
function flush() {
  flushPending = false;
  const now = performance.now();
  const minGap = 1000 / Math.max(1, config.rectRateHz);
  const wait = lastSentAt + minGap - now;
  if (wait > 0) {
    if (!throttleTimer) {
      throttleTimer = setTimeout(() => {
        throttleTimer = null;
        lastSentAt = performance.now();
        send(collect());
      }, wait);
    }
    return;
  }
  lastSentAt = now;
  send(collect());
}

function schedule() {
  if (flushPending)
    return;
  flushPending = true;
  if (document.hidden)
    setTimeout(flush, 0);
  else
    requestAnimationFrame(flush);
}

for (const ev of ["play", "playing", "pause", "ended", "emptied", "volumechange", "loadeddata"])
  document.addEventListener(ev, schedule, true);
document.addEventListener("scroll", schedule, {capture: true, passive: true});
document.addEventListener("visibilitychange", schedule);
document.addEventListener("fullscreenchange", schedule);
window.addEventListener("resize", schedule);

// Page teardown must clear the frame's contribution, immediately.
window.addEventListener("pagehide", () => {
  if (throttleTimer) {
    clearTimeout(throttleTimer);
    throttleTimer = null;
  }
  send({type: "media", playing: 0, audible: false, rects: [], outer: null});
});

browser.runtime.onMessage.addListener((m) => {
  if (m && m.type === "config" && Number.isFinite(m.rectRateHz))
    config.rectRateHz = m.rectRateHz;
});
try {
  browser.runtime.sendMessage({type: "hello"}).then((m) => {
    if (m && Number.isFinite(m.rectRateHz))
      config.rectRateHz = m.rectRateHz;
  }, () => {});
} catch (e) {}

schedule();
