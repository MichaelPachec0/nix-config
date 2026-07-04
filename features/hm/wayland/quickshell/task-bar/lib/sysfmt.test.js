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
