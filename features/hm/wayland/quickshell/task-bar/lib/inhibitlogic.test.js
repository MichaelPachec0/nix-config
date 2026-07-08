// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/inhibitlogic.test.js  (from the task-bar dir)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./inhibitlogic.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("formatCountdown pads and rolls up", () => {
  assertEquals(formatCountdown(0), "00:00:00");
  assertEquals(formatCountdown(999), "00:00:00");        // sub-second floors to 0
  assertEquals(formatCountdown(59 * 1000), "00:00:59");
  assertEquals(formatCountdown(60 * 1000), "00:01:00");
  assertEquals(formatCountdown(3600 * 1000), "01:00:00");
  assertEquals(formatCountdown((3 * 3600 + 59 * 60 + 59) * 1000), "03:59:59");
  assertEquals(formatCountdown(-5000), "00:00:00");      // negative clamps
});

Deno.test("infinityGlyph is U+221E", () => {
  assertEquals(infinityGlyph().codePointAt(0), 0x221E);
  assertEquals(infinityGlyph().length, 1);
});

Deno.test("sanitizeState fills defaults", () => {
  const s = sanitizeState({ idleOn: true }); // wrong shape/keys -> defaults
  assertEquals(s.idle.on, false);
  assertEquals(s.sleep.expiry, 0);
  assertEquals(s.locked, false);
  assertEquals(s.lastDurationMs, 3600000);
});

Deno.test("reconcileOnLoad expires elapsed, keeps live + indefinite", () => {
  const now = 1000000;
  const s = {
    idle: { on: true, expiry: now - 1 },   // elapsed -> off
    sleep: { on: true, expiry: now + 60000 }, // live -> kept
    locked: false, lastDurationMs: 3600000,
  };
  reconcileOnLoad(s, now);
  assertEquals(s.idle.on, false);
  assertEquals(s.idle.expiry, 0);
  assertEquals(s.sleep.on, true);
  assertEquals(s.sleep.expiry, now + 60000);

  const ind = { idle: { on: true, expiry: 0 }, sleep: { on: false, expiry: 0 }, locked: false, lastDurationMs: 0 };
  reconcileOnLoad(ind, now);
  assertEquals(ind.idle.on, true); // indefinite never expires
});

Deno.test("coupledState: indefinite wins, else max live expiry", () => {
  assertEquals(coupledState({ idle: { on: false, expiry: 0 }, sleep: { on: false, expiry: 0 } }),
    { on: false, expiry: 0 });
  assertEquals(coupledState({ idle: { on: true, expiry: 500 }, sleep: { on: true, expiry: 900 } }),
    { on: true, expiry: 900 }); // max
  assertEquals(coupledState({ idle: { on: true, expiry: 0 }, sleep: { on: true, expiry: 900 } }),
    { on: true, expiry: 0 });   // indefinite wins
  assertEquals(coupledState({ idle: { on: false, expiry: 0 }, sleep: { on: true, expiry: 700 } }),
    { on: true, expiry: 700 }); // only sleep on
});

Deno.test("applyLock couples both; applyUnlock just clears the flag", () => {
  const s = { idle: { on: true, expiry: 500 }, sleep: { on: false, expiry: 0 }, locked: false, lastDurationMs: 3600000 };
  applyLock(s);
  assertEquals(s.locked, true);
  assertEquals(s.idle, { on: true, expiry: 500 });
  assertEquals(s.sleep, { on: true, expiry: 500 }); // sleep adopts idle's live timer
  applyUnlock(s);
  assertEquals(s.locked, false);
  assertEquals(s.idle, { on: true, expiry: 500 }); // unchanged on split
  assertEquals(s.sleep, { on: true, expiry: 500 });
});

Deno.test("defaultState exposes per-concern defaults", () => {
  const d = defaultState();
  assertEquals(d.idleDefaultMs, 0);
  assertEquals(d.sleepDefaultMs, 0);
});

Deno.test("sanitizeState carries and coerces per-concern defaults", () => {
  const s = sanitizeState({ idleDefaultMs: 3600000, sleepDefaultMs: "bad" });
  assertEquals(s.idleDefaultMs, 3600000);   // valid kept
  assertEquals(s.sleepDefaultMs, 0);        // invalid -> 0
  const empty = sanitizeState({});
  assertEquals(empty.idleDefaultMs, 0);     // missing -> 0
  assertEquals(empty.sleepDefaultMs, 0);
});
