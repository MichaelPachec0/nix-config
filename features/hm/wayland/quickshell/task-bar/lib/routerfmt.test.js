// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/routerfmt.test.js  (--allow-read is needed for the readTextFile below)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./routerfmt.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("quality bands", () => {
  // RSRP: excellent >= -100, good >= -105, fair >= -110, else poor (boundaries inclusive).
  assertEquals(quality("rsrp", -73), "excellent");
  assertEquals(quality("rsrp", -100), "excellent");
  assertEquals(quality("rsrp", -103), "good");
  assertEquals(quality("rsrp", -105), "good");
  assertEquals(quality("rsrp", -108), "fair");
  assertEquals(quality("rsrp", -110), "fair");
  assertEquals(quality("rsrp", -111), "poor");
  // RSRQ: excellent >= -12, good >= -16, fair >= -20, else poor.
  assertEquals(quality("rsrq", -10), "excellent");
  assertEquals(quality("rsrq", -12), "excellent");
  assertEquals(quality("rsrq", -14), "good");
  assertEquals(quality("rsrq", -16), "good");
  assertEquals(quality("rsrq", -18), "fair");
  assertEquals(quality("rsrq", -20), "fair");
  assertEquals(quality("rsrq", -21), "poor");
  // SINR: excellent >= 12, good >= 6, fair >= 0, else poor.
  assertEquals(quality("sinr", 30), "excellent");
  assertEquals(quality("sinr", 12), "excellent");
  assertEquals(quality("sinr", 6), "good");
  assertEquals(quality("sinr", 5), "fair");
  assertEquals(quality("sinr", 0), "fair");
  assertEquals(quality("sinr", -2), "poor");
});

Deno.test("barFill clamps", () => {
  assertEquals(barFill(4), 4);
  assertEquals(barFill(9), 5);
  assertEquals(barFill(-1), 0);
  assertEquals(barFill(null), 0);
});

Deno.test("fmtRate bits", () => {
  assertEquals(fmtRate(0), "0 b/s");
  assertEquals(fmtRate(125000), "1.0 Mb/s");   // 125000 B/s * 8 = 1e6 b/s
});

Deno.test("fmtBytes", () => {
  assertEquals(fmtBytes(0), "0 B");
  assertEquals(fmtBytes(4700000000), "4.4 GB");
});

Deno.test("fmtDuration picks two units, largest first", () => {
  assertEquals(fmtDuration(276164), "3d 4h");   // router uptime
  assertEquals(fmtDuration(12663), "3h 31m");   // modem uptime since dial
  assertEquals(fmtDuration(2700), "45m");
  assertEquals(fmtDuration(12), "12s");
});

Deno.test("fmtDuration drops a zero smaller unit", () => {
  assertEquals(fmtDuration(172800), "2d");      // not "2d 0h"
  assertEquals(fmtDuration(7200), "2h");        // not "2h 0m"
});

Deno.test("fmtDuration reports no reading, not a fresh boot", () => {
  // "0s" here would read as a device that just came up, which is the opposite
  // of "we have not been told". The two uptimes share a line, so a missing one
  // must be visibly missing.
  assertEquals(fmtDuration(null), "--");
  assertEquals(fmtDuration(undefined), "--");
  assertEquals(fmtDuration(-1), "--");
  assertEquals(fmtDuration("nope"), "--");
  assertEquals(fmtDuration(0), "0s");           // a real zero IS a fresh boot
});
