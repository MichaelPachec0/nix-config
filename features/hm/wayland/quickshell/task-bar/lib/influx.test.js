// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/influx.test.js  (--allow-read needed for readTextFile)
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./influx.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

const FRAME = `ryzen_monitor_ng,host=thanatos,name=Core0 core_state="Active",core_active=1i,core_frequency=3700i,core_temperature=78.00
ryzen_monitor_ng,host=thanatos,name=Cores cores_maxtemperature=82.00,cores_totalpower=15.000
ryzen_monitor_ng,host=thanatos,name=Package soc_temperature=55.00,gfx_temperature=68.00,cpu_stapm=14.000,cpu_stapmlimit=15i,cpu_ppt=15.000,cpu_pptlimit=25i,cpu_tdc=22.000,cpu_tdclimit=40i,cpu_edc=30.000,cpu_edclimit=55i,cpu_thm=80.00,cpu_thmlimit=95i
ryzen_monitor_ng,host=thanatos,name=FabricIO cpu_coupled=true,cpu_fabricclock=1600,cpu_memoryclock=1600
ryzen_monitor_ng,host=thanatos,name=GFX gfx_temperature=68.00,gfx_busy=7.00`;

Deno.test("parseFrame numeric fields", () => {
  const f = parseFrame(FRAME);
  assertEquals(f.cpu_thm, 80);
  assertEquals(f.gfx_temperature, 68);
  assertEquals(f.cpu_pptlimit, 25);       // trailing i stripped -> integer
  assertEquals(f.cpu_ppt, 15);
  assertEquals(f.cpu_fabricclock, 1600);
  assertEquals(f.gfx_busy, 7);
  assertEquals(f.core_active, 1);
  assertEquals(f.core_frequency, 3700);
  assertEquals(f.cores_maxtemperature, 82);
  assertEquals(f.soc_temperature, 55);
});

Deno.test("parseFrame skips non-numeric fields", () => {
  const f = parseFrame(FRAME);
  assertEquals(f.cpu_coupled, undefined);  // "true" is NaN -> skipped
  assertEquals(f.core_state, undefined);   // "Active" is NaN -> skipped
});

Deno.test("parseFrame empty input", () => {
  const f = parseFrame("");
  assertEquals(f.cpu_thm, undefined);
  assertEquals(Object.keys(f).length, 0);
});

Deno.test("parseFrame garbage input", () => {
  assertEquals(Object.keys(parseFrame("no equals here")).length, 0);
});
