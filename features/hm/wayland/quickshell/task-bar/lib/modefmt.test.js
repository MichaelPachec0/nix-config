// Deno test: indirect-eval the dual-use JS resource, then assert.
// Run: deno test --allow-read lib/modefmt.test.js
import { assertEquals } from "https://deno.land/std/assert/mod.ts";

const code = await Deno.readTextFile(new URL("./modefmt.js", import.meta.url));
const load = eval; // indirect eval -> global scope
load(code);

Deno.test("glyphFor converts a hex codepoint to its glyph", () => {
  assertEquals(glyphFor("f065"), String.fromCharCode(0xf065));
  assertEquals(glyphFor("F065"), String.fromCharCode(0xf065));
});

Deno.test("glyphFor returns empty string for absent input", () => {
  assertEquals(glyphFor(""), "");
  assertEquals(glyphFor(null), "");
  assertEquals(glyphFor(undefined), "");
});

// A bad codepoint must render as nothing, not as U+0000. parseInt("zz", 16) is
// NaN and String.fromCharCode(NaN) is " ", which paints a garbage box.
Deno.test("glyphFor rejects non-hex input instead of emitting U+0000", () => {
  assertEquals(glyphFor("zz"), "");
  assertEquals(glyphFor("not-a-codepoint"), "");
  assertEquals(glyphFor("  "), "");
});
