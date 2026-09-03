// Reports this frame's count of playing <video> elements to the background
// script. Media events do not bubble, but capture-phase listeners on the
// document see them, so no per-element wiring or MutationObserver is needed.
// all_frames:true means embedded players (YouTube iframes) report from their
// own frame; the background sums per tab.
"use strict";

let playing = 0;
let reported = -1;

function recount() {
  let n = 0;
  for (const v of document.querySelectorAll("video")) {
    if (!v.paused && !v.ended && v.readyState >= 2)
      n++;
  }
  playing = n;
  if (playing !== reported) {
    reported = playing;
    // Muted state rides along for the "audible" signal mode; a frame counts
    // as audible when any playing video is unmuted with volume > 0.
    let audible = false;
    for (const v of document.querySelectorAll("video")) {
      if (!v.paused && !v.ended && !v.muted && v.volume > 0) {
        audible = true;
        break;
      }
    }
    try {
      browser.runtime.sendMessage({type: "media", playing, audible});
    } catch (e) {
      // Extension context gone (reload/uninstall); nothing to do.
    }
  }
}

for (const ev of ["play", "playing", "pause", "ended", "emptied", "volumechange"])
  document.addEventListener(ev, recount, true);
// Page teardown must clear the frame's contribution.
window.addEventListener("pagehide", () => {
  playing = 0;
  if (reported !== 0) {
    reported = 0;
    try { browser.runtime.sendMessage({type: "media", playing: 0, audible: false}); } catch (e) {}
  }
});
recount();
