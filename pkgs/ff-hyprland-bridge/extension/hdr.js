// Page-world matchMedia hook. Firefox's content process evaluates
// (video-)dynamic-range against the screen at (0,0), which on Wayland is
// always the first output; the host knows the real monitor and its EDID.
// Runs at document_start in every frame, before any page script. Installs
// with hdr=false (Firefox's own answer) and flips when the background
// replies or pushes a change; live MediaQueryList-like objects fire
// "change". Any failure leaves the native matchMedia alone.
"use strict";

(function () {
  let hdr = false;
  const records = new Set(); // {obj, media, native, high, standard, listeners}

  const RE_ANY = /(?:video-)?dynamic-range\s*:/i;
  const RE_HIGH = /(?:video-)?dynamic-range\s*:\s*high/i;
  const RE_STD = /(?:video-)?dynamic-range\s*:\s*standard/i;

  function computeMatches(rec) {
    if (rec.high) return hdr || rec.native.matches;
    if (rec.standard) return !hdr;
    return rec.native.matches;
  }

  let pageWin, origMatchMedia;
  try {
    pageWin = window.wrappedJSObject;
    origMatchMedia = pageWin.matchMedia;
    if (typeof origMatchMedia !== "function") return;
  } catch (e) {
    console.warn("ff-hyprland-bridge hdr.js: no page window", e);
    return;
  }

  function deliver(rec, ev) {
    for (const fn of Array.from(rec.listeners)) {
      try { fn.call(rec.obj, ev); } catch (e) {}
    }
    try {
      if (typeof rec.obj.onchange === "function") rec.obj.onchange.call(rec.obj, ev);
    } catch (e) {}
  }

  function makeList(query, native) {
    const rec = {obj: null, media: native.media, native, high: RE_HIGH.test(query), standard: RE_STD.test(query), listeners: new Set()};
    // Build the object in the page's compartment so the page owns it; only
    // primitives and exported functions cross the boundary.
    const obj = new pageWin.Object();
    obj.media = rec.media;
    obj.matches = computeMatches(rec);
    obj.onchange = null;
    obj.addEventListener = exportFunction(function (type, fn) {
      if (type === "change" && typeof fn === "function") rec.listeners.add(fn);
    }, pageWin);
    obj.removeEventListener = exportFunction(function (type, fn) {
      if (type === "change") rec.listeners.delete(fn);
    }, pageWin);
    obj.addListener = exportFunction(function (fn) {
      if (typeof fn === "function") rec.listeners.add(fn);
    }, pageWin);
    obj.removeListener = exportFunction(function (fn) {
      rec.listeners.delete(fn);
    }, pageWin);
    obj.dispatchEvent = exportFunction(function (ev) {
      deliver(rec, ev);
      return true;
    }, pageWin);
    rec.obj = obj;
    records.add(rec);
    return obj;
  }

  function update(next) {
    if (next === hdr) return;
    hdr = next;
    for (const rec of records) {
      const m = computeMatches(rec);
      if (rec.obj.matches === m) continue;
      rec.obj.matches = m;
      try {
        const ev = new pageWin.MediaQueryListEvent("change", cloneInto({matches: m, media: rec.media}, pageWin));
        deliver(rec, ev);
      } catch (e) {}
    }
  }

  const wrapped = function (query) {
    const q = String(query);
    const native = origMatchMedia.call(pageWin, q);
    if (!RE_ANY.test(q)) return native;
    try {
      return makeList(q, native);
    } catch (e) {
      console.warn("ff-hyprland-bridge hdr.js: makeList failed", e);
      return native;
    }
  };

  try {
    pageWin.matchMedia = exportFunction(wrapped, pageWin);
  } catch (e) {
    console.warn("ff-hyprland-bridge hdr.js: install failed", e);
    return;
  }

  browser.runtime.onMessage.addListener((m) => {
    if (m && m.type === "hdr" && typeof m.hdr === "boolean") update(m.hdr);
  });
  try {
    browser.runtime.sendMessage({type: "hdr-hello"}).then((m) => {
      if (m && typeof m.hdr === "boolean") update(m.hdr);
    }, () => {});
  } catch (e) {}
})();
