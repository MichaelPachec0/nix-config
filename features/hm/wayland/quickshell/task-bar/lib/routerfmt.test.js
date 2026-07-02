// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/routerfmt.test.js  (--allow-read is needed for the readTextFile below)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./routerfmt.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("quality bands", () => {
  assertEquals(quality("rsrp", -73), "good");
  assertEquals(quality("rsrp", -100), "fair");
  assertEquals(quality("rsrp", -110), "poor");
  assertEquals(quality("rsrq", -10), "good");
  assertEquals(quality("rsrq", -14), "fair");
  assertEquals(quality("rsrq", -20), "poor");
  assertEquals(quality("sinr", 30), "good");
  assertEquals(quality("sinr", 5), "fair");
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
