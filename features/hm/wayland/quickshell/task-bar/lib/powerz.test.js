// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run from <tb>/lib: deno test --allow-read powerz.test.js   (or: deno task test)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./powerz.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

const r3 = (x) => Math.round(x * 1000) / 1000; // avoid float-repr flakiness

Deno.test("active: converts milli-units, computes power, available=true", () => {
  const r = parsePowerz("state: active\nvbus: 20157\nibus: 1889\ncc1: 1690\ncc2: 504\n");
  assertEquals(r.state, "active");
  assertEquals(r.available, true);
  assertEquals(r3(r.vbus), 20.157);
  assertEquals(r3(r.ibus), 1.889);
  assertEquals(r3(r.cc1), 1.69);
  assertEquals(r3(r.cc2), 0.504);
  assertEquals(Math.round(r.power * 100) / 100, 38.08); // 20.157 * 1.889
});

Deno.test("active: missing channel defaults to 0, still available", () => {
  const r = parsePowerz("state: active\nvbus: 5000\nibus: 1000\n");
  assertEquals(r.available, true);
  assertEquals(r3(r.vbus), 5);
  assertEquals(r3(r.ibus), 1);
  assertEquals(r.cc1, 0);
  assertEquals(r.cc2, 0);
  assertEquals(r3(r.power), 5);
});

Deno.test("busy: zeroed readings, not available", () => {
  const r = parsePowerz("state: busy\n");
  assertEquals(r.state, "busy");
  assertEquals(r.available, false);
  assertEquals(r.vbus, 0);
  assertEquals(r.ibus, 0);
  assertEquals(r.power, 0);
});

Deno.test("absent: explicit", () => {
  assertEquals(parsePowerz("state: absent\n").state, "absent");
});

Deno.test("no state line or garbage -> absent", () => {
  assertEquals(parsePowerz("").state, "absent");
  assertEquals(parsePowerz("garbage\nvbus: 5000\n").state, "absent");
  assertEquals(parsePowerz(null).state, "absent");
});

Deno.test("busy/absent ignore stray readings", () => {
  const r = parsePowerz("state: busy\nvbus: 20000\n");
  assertEquals(r.state, "busy");
  assertEquals(r.vbus, 0);
});
