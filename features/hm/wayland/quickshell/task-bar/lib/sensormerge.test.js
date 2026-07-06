// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/sensormerge.test.js  (--allow-read needed for readTextFile)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./sensormerge.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("classifyChip", () => {
  assertEquals(classifyChip("amdgpu edge"), "gpu");
  assertEquals(classifyChip("thinkpad CPU"), "cpu");
  assertEquals(classifyChip("zenpower Tdie"), "cpu");
  assertEquals(classifyChip("nvme Composite"), "other");
  assertEquals(classifyChip("iwlwifi"), "other");
});

const LM_FULL = [
  { label: "thinkpad CPU", temp: 90 },
  { label: "amdgpu edge", temp: 66 },
  { label: "nvme Composite", temp: 51 },
  { label: "iwlwifi", temp: 61 },
];

const LM_SHORT = [
  { label: "thinkpad CPU", temp: 90 },
  { label: "nvme Composite", temp: 51 },
];

Deno.test("mergeSensors fallback when smu unavailable", () => {
  assertEquals(mergeSensors(LM_SHORT, { available: false }), LM_SHORT);
});

Deno.test("mergeSensors fallback when smu is null", () => {
  assertEquals(mergeSensors(LM_SHORT, null), LM_SHORT);
});

Deno.test("mergeSensors fallback when smu is undefined", () => {
  assertEquals(mergeSensors(LM_SHORT, undefined), LM_SHORT);
});

Deno.test("mergeSensors full SMU merge (with peak)", () => {
  const result = mergeSensors(LM_FULL, { available: true, cpu: 80, peak: 92, soc: 55, gfx: 68 });
  assertEquals(result, [
    { label: "CPU", temp: 80 },
    { label: "CPU Pk", temp: 92 },
    { label: "SoC", temp: 55 },
    { label: "GFX", temp: 68 },
    { label: "nvme Composite", temp: 51 },
    { label: "iwlwifi", temp: 61 },
  ]);
});

Deno.test("mergeSensors peak-only still suppresses lm CPU", () => {
  const result = mergeSensors(LM_FULL, { available: true, cpu: 0, peak: 92, soc: 0, gfx: 0 });
  assertEquals(result[0], { label: "CPU Pk", temp: 92 });
  // thinkpad CPU dropped (peak marks cpu supplied); amdgpu edge kept
  assertEquals(result.find(function(e) { return e.label === "thinkpad CPU"; }), undefined);
  assertEquals(result.find(function(e) { return e.label === "amdgpu edge"; }),
               { label: "amdgpu edge", temp: 66 });
});

Deno.test("mergeSensors partial SMU (cpu only)", () => {
  const result = mergeSensors(LM_FULL, { available: true, cpu: 80, soc: 0, gfx: 0 });
  // thinkpad CPU dropped (cpu supplied), amdgpu edge kept (gpu not supplied)
  assertEquals(result[0], { label: "CPU", temp: 80 });
  // No SoC or GFX entries added
  assertEquals(result.find(function(e) { return e.label === "SoC"; }), undefined);
  assertEquals(result.find(function(e) { return e.label === "GFX"; }), undefined);
  // amdgpu edge is present (gpu not supplied by SMU)
  assertEquals(result.find(function(e) { return e.label === "amdgpu edge"; }),
               { label: "amdgpu edge", temp: 66 });
});
