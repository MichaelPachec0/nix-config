// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/weathercond.test.js  (--allow-read needed for readTextFile)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./weathercond.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("urgency: nws/thunder critical, others normal", () => {
  assertEquals(urgency("nws", "severe"), "critical");
  assertEquals(urgency("thunder", "severe"), "critical");
  assertEquals(urgency("uv", "warn"), "normal");
});

Deno.test("urgency: any kind escalates to critical at severe sev", () => {
  assertEquals(urgency("heat", "severe"), "critical");
  assertEquals(urgency("wind", "info"), "normal");
});

Deno.test("sortBySeverity: severe first", () => {
  const out = sortBySeverity([{ sev: "info" }, { sev: "severe" }, { sev: "warn" }]);
  assertEquals(out.map((c) => c.sev), ["severe", "warn", "info"]);
});

Deno.test("sortBySeverity: unranked sev sorts last, empty/null input safe", () => {
  const out = sortBySeverity([{ sev: "warn" }, { sev: "bogus" }, { sev: "severe" }]);
  assertEquals(out.map((c) => c.sev), ["severe", "warn", "bogus"]);
  assertEquals(sortBySeverity([]), []);
  assertEquals(sortBySeverity(null), []);
});

Deno.test("notifBody: uses label when present, falls back otherwise", () => {
  assertEquals(notifBody({ label: "Heat advisory" }), "Heat advisory");
  assertEquals(notifBody({}), "Weather condition");
  assertEquals(notifBody(null), "Weather condition");
});

Deno.test("color: rain/snow are fixed hex, others resolve via theme tokens", () => {
  const theme = {
    accentRed: "R",
    accentBlue: "B",
    accentYellow: "Y",
    accentPurple: "P",
    accentOrange: "O",
    textSecondary: "T",
  };
  assertEquals(color(theme, "rain", "info"), "#4d8fd6");
  assertEquals(color(theme, "snow", "info"), "#a9d5e5");
  assertEquals(color(theme, "heat", "severe"), "R");
  assertEquals(color(theme, "heat", "warn"), "O");
  assertEquals(color(theme, "cold", "info"), "B");
  assertEquals(color(theme, "wind", "info"), "Y");
  assertEquals(color(theme, "uv", "warn"), "P");
  assertEquals(color(theme, "uv", "severe"), "P");
  assertEquals(color(theme, "fog", "info"), "T");
  assertEquals(color(theme, "thunder", "info"), "R");
  assertEquals(color(theme, "nws", "info"), "R");
});
