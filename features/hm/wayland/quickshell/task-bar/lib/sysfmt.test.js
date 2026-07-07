// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/sysfmt.test.js  (--allow-read needed for readTextFile)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./sysfmt.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("severity bands", () => {
  assertEquals(severity("cpu", 20), "good");
  assertEquals(severity("cpu", 80), "fair");
  assertEquals(severity("cpu", 95), "poor");
  assertEquals(severity("mem", 41), "good");
  assertEquals(severity("mem", 90), "poor");
  assertEquals(severity("swap", 5), "good");
  assertEquals(severity("swap", 30), "fair");
  assertEquals(severity("swap", 70), "poor");
  assertEquals(severity("temp", 62), "good");
  assertEquals(severity("temp", 78), "fair");
  assertEquals(severity("temp", 90), "poor");
  assertEquals(severity("psi", 0), "good");
  assertEquals(severity("psi", 10), "fair");
  assertEquals(severity("psi", 25), "poor");
  assertEquals(severity("cpu", null), "good");
  assertEquals(severity("bogus", 999), "good");
});

Deno.test("fmtKB", () => {
  assertEquals(fmtKB(0), "0K");
  assertEquals(fmtKB(824234), "805M");
  assertEquals(fmtKB(6488064), "6.2G");
});

Deno.test("fmtRate scales bytes/s", () => {
  assertEquals(fmtRate(0), "0 B/s");
  assertEquals(fmtRate(512), "512 B/s");
  assertEquals(fmtRate(1024), "1.0 K/s");
  assertEquals(fmtRate(1536 * 1024), "1.5 M/s");
});

Deno.test("parseTopology groups by CCX then core", () => {
  // cpu0/1->core0, cpu2/3->core1 (CCX A = L3 "0-3"); cpu4/5->core2,
  // cpu6/7->core3 (CCX B = L3 "4-7").
  const text =
    "0 0 0-3\n1 0 0-3\n2 1 0-3\n3 1 0-3\n" +
    "4 2 4-7\n5 2 4-7\n6 3 4-7\n7 3 4-7\n";
  const t = parseTopology(text);
  assertEquals(t.length, 2);
  assertEquals(t[0].ccx, 0);
  assertEquals(t[0].cores.length, 2);
  assertEquals(t[0].cores[0].coreId, 0);
  assertEquals(t[0].cores[0].threads, [0, 1]);
  assertEquals(t[1].cores[1].coreId, 3);
  assertEquals(t[1].cores[1].threads, [6, 7]);
});

Deno.test("parseTopology collapses to one CCX when L3 absent", () => {
  const text = "0 0\n1 0\n2 1\n3 1\n";       // no L3 column
  const t = parseTopology(text);
  assertEquals(t.length, 1);
  assertEquals(t[0].ccx, 0);
  assertEquals(t[0].cores.length, 2);
});

Deno.test("parseTopology empty input", () => {
  assertEquals(parseTopology("").length, 0);
});
