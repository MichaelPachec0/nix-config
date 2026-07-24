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

Deno.test("keyOf: nws keyed by title, others keyed by kind", () => {
  assertEquals(keyOf({ kind: "heat", sev: "warn", label: "Heat 96F" }), "heat");
  assertEquals(keyOf({ kind: "nws", sev: "severe", label: "Heat Advisory" }), "nws:Heat Advisory");
  assertEquals(keyOf({ kind: "nws", sev: "severe", label: "Flood Warning" }), "nws:Flood Warning");
});

Deno.test("diffConditions: a new condition is started, next holds it by key", () => {
  const heat = { kind: "heat", sev: "warn", label: "Heat 96F" };
  const d = diffConditions({}, [heat]);
  assertEquals(d.started, [heat]);
  assertEquals(d.cleared, []);
  assertEquals(d.next, { heat: heat });
});

Deno.test("diffConditions: a persisted condition now absent is cleared", () => {
  const heat = { kind: "heat", sev: "warn", label: "Heat 96F" };
  const d = diffConditions({ heat: heat }, []);
  assertEquals(d.started, []);
  assertEquals(d.cleared, [heat]);
  assertEquals(d.next, {});
});

Deno.test("diffConditions: an unchanged condition is neither started nor cleared", () => {
  const heat = { kind: "heat", sev: "warn", label: "Heat 96F" };
  const fresh = { kind: "heat", sev: "warn", label: "Heat 97F" }; // same key, updated label
  const d = diffConditions({ heat: heat }, [fresh]);
  assertEquals(d.started, []);
  assertEquals(d.cleared, []);
  assertEquals(d.next, { heat: fresh }); // next carries the fresh cond for its label
});

Deno.test("diffConditions: two distinct nws titles are tracked independently by key", () => {
  const heatAlert = { kind: "nws", sev: "severe", label: "Heat Advisory" };
  const floodAlert = { kind: "nws", sev: "severe", label: "Flood Warning" };
  // Previously only the heat advisory was active; now the flood warning appears
  // and the heat advisory persists.
  const d = diffConditions({ "nws:Heat Advisory": heatAlert }, [heatAlert, floodAlert]);
  assertEquals(d.started, [floodAlert]);
  assertEquals(d.cleared, []);
  assertEquals(d.next, {
    "nws:Heat Advisory": heatAlert,
    "nws:Flood Warning": floodAlert,
  });
});

Deno.test("diffConditions: simultaneous start and clear across distinct nws keys", () => {
  const heatAlert = { kind: "nws", sev: "severe", label: "Heat Advisory" };
  const floodAlert = { kind: "nws", sev: "severe", label: "Flood Warning" };
  const d = diffConditions({ "nws:Heat Advisory": heatAlert }, [floodAlert]);
  assertEquals(d.started, [floodAlert]);
  assertEquals(d.cleared, [heatAlert]);
  assertEquals(d.next, { "nws:Flood Warning": floodAlert });
});

Deno.test("diffConditions: null/undefined inputs are safe", () => {
  assertEquals(diffConditions(null, null), { started: [], cleared: [], next: {} });
  assertEquals(diffConditions(undefined, undefined), { started: [], cleared: [], next: {} });
});

Deno.test("diffConditions: a malformed/keyless fresh entry does not throw and is not a phantom event", () => {
  const heat = { kind: "heat", sev: "warn", label: "Heat 96F" };
  // null and {} both key to "" via the keyOf guard and must be skipped, not
  // recorded as started, and must not crash the scan (a malformed weather.sh
  // payload element previously threw inside _apply).
  const d = diffConditions({ heat: heat }, [heat, null, {}]);
  assertEquals(d.started, []);
  assertEquals(d.cleared, []);
  assertEquals(d.next, { heat: heat });
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
